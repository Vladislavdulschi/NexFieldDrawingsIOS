import Foundation
import SwiftUI
import UIKit

@MainActor
final class DrawingsViewModel: ObservableObject {
    @Published var currentUser: User? = nil
    @Published var projects: [Project] = []
    @Published var drawings: [DrawingRecord] = []
    @Published var teamUsers: [User] = []

    @Published var isLoading: Bool = false
    @Published var statusBannerMessage: String? = nil
    @Published var activeDrawing: DrawingRecord? = nil

    private let api = NexFieldApiClient.shared

    init() {
        let localManifest = api.loadLocalDrawingsManifest()
        if !localManifest.isEmpty {
            self.drawings = localManifest
        }
        if let cached = api.getCachedUser() {
            self.currentUser = cached
            Task {
                await syncWithServer()
            }
        }
    }

    var baseUrl: String {
        get { api.baseUrl }
        set { api.baseUrl = newValue }
    }

    var savedEmail: String {
        get { api.savedEmail }
        set { api.savedEmail = newValue }
    }

    var savedPassword: String {
        get { api.savedPassword }
        set { api.savedPassword = newValue }
    }

    func getSavedAccounts() -> [SavedAccount] {
        api.getSavedAccounts()
    }

    func login(serverUrl: String, email: String, password: String) async {
        isLoading = true
        statusBannerMessage = nil
        api.baseUrl = serverUrl
        do {
            let user = try await api.login(email: email, password: password)
            api.saveAccountCredentials(serverUrl: serverUrl, email: email, password: password, userName: user.name)
            self.currentUser = user
            await syncWithServer()
        } catch {
            statusBannerMessage = error.localizedDescription
        }
        isLoading = false
    }

    func enterOfflineMode() {
        if let cached = api.getCachedUser() {
            self.currentUser = cached
        } else {
            self.currentUser = User(id: 0, name: "Offline Engineer", email: "offline@nexfield.co.uk", role: "engineer")
        }
        self.drawings = api.loadLocalDrawingsManifest()
        statusBannerMessage = "Working in Offline Mode (Phone Storage)."
    }

    func logout() {
        api.saveCachedUser(nil)
        api.rememberToken = nil
        currentUser = nil
        activeDrawing = nil
    }

    func syncWithServer() async {
        guard let user = currentUser, user.id > 0 else { return }
        isLoading = true
        do {
            let payload = try await api.fetchServerData(userId: user.id)
            if let u = payload.user {
                self.currentUser = u
                api.saveCachedUser(u)
            }
            self.projects = payload.projects
            self.teamUsers = payload.users

            let localList = api.loadLocalDrawingsManifest()
            var merged: [DrawingRecord] = []

            for srv in payload.drawings {
                if let loc = localList.first(where: { $0.id == srv.id && srv.id > 0 }) {
                    var updated = srv
                    updated.localFilePath = loc.localFilePath
                    if loc.syncState == .modifiedOffline {
                        let localMap = AnnotationsEnvelope.parse(loc.annotationsData)
                        let (mergedPages, _) = AnnotationsEnvelope.threeWayMerge(
                            baseJson: loc.baseServerAnnotationsData,
                            serverJson: srv.annotationsData,
                            localPagesMap: localMap
                        )
                        updated.annotationsData = AnnotationsEnvelope.serialize(mergedPages)
                        updated.syncState = .modifiedOffline
                        updated.baseServerAnnotationsData = srv.annotationsData
                    } else {
                        updated.syncState = (loc.localFilePath != nil) ? .downloaded : .cloudOnly
                        updated.baseServerAnnotationsData = srv.annotationsData
                    }
                    merged.append(updated)
                } else {
                    var fresh = srv
                    fresh.baseServerAnnotationsData = srv.annotationsData
                    merged.append(fresh)
                }
            }

            for locOnly in localList where locOnly.syncState == .localOnly {
                merged.append(locOnly)
            }

            self.drawings = merged
            api.saveLocalDrawingsManifest(merged)
            statusBannerMessage = "Synced \(merged.count) blueprints with nexfield.co.uk"
        } catch {
            statusBannerMessage = "Offline / Sync note: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func downloadAndOpenDrawing(_ drawing: DrawingRecord) async {
        if let localPath = drawing.localFilePath,
           FileManager.default.fileExists(atPath: localPath) {
            activeDrawing = drawing
            return
        }

        isLoading = true
        statusBannerMessage = "Downloading \(drawing.name)..."
        let ext = drawing.originalPath.lowercased().hasSuffix(".pdf") ? "pdf" : "png"
        let destURL = api.blueprintsDirectory.appendingPathComponent("drawing_\(drawing.id)_\(Int(Date().timeIntervalSince1970)).\(ext)")
        do {
            let savedURL = try await api.downloadBlueprintFile(remotePathOrDataUrl: drawing.originalPath, destFile: destURL)
            var updated = drawing
            updated.localFilePath = savedURL.path
            updated.syncState = .downloaded
            updated.baseServerAnnotationsData = drawing.annotationsData
            updateDrawingInList(updated)
            activeDrawing = updated
            statusBannerMessage = nil
        } catch {
            statusBannerMessage = "Download failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func importLocalBlueprint(from sourceURL: URL, projectId: Int, projectName: String) {
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }

        let fileName = sourceURL.lastPathComponent
        let destURL = api.blueprintsDirectory.appendingPathComponent("local_\(Int(Date().timeIntervalSince1970))_\(fileName)")
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            let newRec = DrawingRecord(
                id: 0,
                localId: "local_\(Int(Date().timeIntervalSince1970))",
                projectId: projectId,
                projectName: projectName,
                name: sourceURL.deletingPathExtension().lastPathComponent,
                originalPath: destURL.path,
                localFilePath: destURL.path,
                syncState: .localOnly
            )
            drawings.insert(newRec, at: 0)
            api.saveLocalDrawingsManifest(drawings)
            statusBannerMessage = "Imported \"\(newRec.name)\" onto iPhone."
        } catch {
            statusBannerMessage = "Import error: \(error.localizedDescription)"
        }
    }

    func saveAnnotationsToPhone(
        drawing: DrawingRecord,
        allPagesAnnotations: [Int: PageAnnotations],
        scaleRatio: Double?
    ) {
        let jsonStr = AnnotationsEnvelope.serialize(allPagesAnnotations)
        var updated = drawing
        updated.annotationsData = jsonStr
        if let sr = scaleRatio { updated.scaleRatio = sr }
        if updated.syncState != .localOnly {
            updated.syncState = .modifiedOffline
        }
        updateDrawingInList(updated)
        activeDrawing = updated
        statusBannerMessage = "Saved on iPhone (Offline-ready)."
    }

    func saveAnnotationsToCloud(
        drawing: DrawingRecord,
        allPagesAnnotations: [Int: PageAnnotations],
        scaleRatio: Double?,
        previewImage: UIImage?
    ) async {
        // Always save to iPhone first
        saveAnnotationsToPhone(drawing: drawing, allPagesAnnotations: allPagesAnnotations, scaleRatio: scaleRatio)

        guard let user = currentUser, user.id > 0, drawing.id > 0 else {
            statusBannerMessage = "Saved on iPhone (Offline / Local blueprint)."
            return
        }

        isLoading = true
        do {
            // Pull latest server annotations for 3-way conflict-free merge
            let srvPayload = try? await api.fetchServerData(userId: user.id)
            let latestSrvDrawing = srvPayload?.drawings.first(where: { $0.id == drawing.id })

            let (mergedPages, teamPreserved) = AnnotationsEnvelope.threeWayMerge(
                baseJson: drawing.baseServerAnnotationsData,
                serverJson: latestSrvDrawing?.annotationsData,
                localPagesMap: allPagesAnnotations
            )
            let mergedJson = AnnotationsEnvelope.serialize(mergedPages)

            var dataUrl = ""
            if let img = previewImage, let pngData = img.pngData() {
                dataUrl = "data:image/png;base64," + pngData.base64EncodedString()
            }

            try await api.saveAnnotationToServer(
                drawingId: drawing.id,
                annotatedDataUrl: dataUrl,
                annotationsDataJson: mergedJson,
                userId: user.id
            )
            if let sr = scaleRatio, sr > 0 {
                try? await api.updateDrawingScaleOnServer(drawingId: drawing.id, scaleRatio: sr)
            }

            var synced = drawing
            synced.annotationsData = mergedJson
            synced.baseServerAnnotationsData = mergedJson
            synced.scaleRatio = scaleRatio
            synced.syncState = .downloaded
            updateDrawingInList(synced)
            activeDrawing = synced

            if teamPreserved > 0 {
                statusBannerMessage = "Synced to Cloud (+preserved \(teamPreserved) team markup items)."
            } else {
                statusBannerMessage = "Saved & Synced to nexfield.co.uk Cloud!"
            }
        } catch {
            statusBannerMessage = "Saved on iPhone. Cloud sync deferred: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func updateDrawingInList(_ updated: DrawingRecord) {
        if let idx = drawings.firstIndex(where: {
            ($0.id > 0 && $0.id == updated.id) || $0.localId == updated.localId
        }) {
            drawings[idx] = updated
        } else {
            drawings.insert(updated, at: 0)
        }
        api.saveLocalDrawingsManifest(drawings)
    }
}
