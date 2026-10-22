import Foundation

struct SavedAccount: Codable, Identifiable, Equatable {
    var id: String { "\(serverUrl)|\(email.lowercased())" }
    var serverUrl: String
    var email: String
    var password: String
    var userName: String = ""
}

struct ServerSyncPayload {
    var user: User?
    var projects: [Project]
    var drawings: [DrawingRecord]
    var users: [User]
}

final class NexFieldApiClient {
    static let shared = NexFieldApiClient()
    private let defaults = UserDefaults.standard
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    var baseUrl: String {
        get {
            defaults.string(forKey: "nexfield_base_url") ?? "https://nexfield.co.uk"
        }
        set {
            var cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            while cleaned.hasSuffix("/") { cleaned.removeLast() }
            if !cleaned.lowercased().hasPrefix("http") {
                cleaned = "https://\(cleaned)"
            }
            defaults.set(cleaned, forKey: "nexfield_base_url")
        }
    }

    var savedEmail: String {
        get { defaults.string(forKey: "nexfield_saved_email") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "nexfield_saved_email") }
    }

    var savedPassword: String {
        get { defaults.string(forKey: "nexfield_saved_password") ?? "" }
        set { defaults.set(newValue, forKey: "nexfield_saved_password") }
    }

    var rememberToken: String? {
        get { defaults.string(forKey: "nexfield_remember_token") }
        set { defaults.set(newValue, forKey: "nexfield_remember_token") }
    }

    func getSavedAccounts() -> [SavedAccount] {
        guard let data = defaults.data(forKey: "nexfield_saved_accounts"),
              let list = try? JSONDecoder().decode([SavedAccount].self, from: data) else {
            return []
        }
        return list
    }

    func saveAccountCredentials(serverUrl: String, email: String, password: String, userName: String) {
        self.baseUrl = serverUrl
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.savedEmail = cleanEmail
        self.savedPassword = password

        var list = getSavedAccounts()
        list.removeAll { $0.email.caseInsensitiveCompare(cleanEmail) == .orderedSame && $0.serverUrl.caseInsensitiveCompare(self.baseUrl) == .orderedSame }
        list.insert(SavedAccount(serverUrl: self.baseUrl, email: cleanEmail, password: password, userName: userName), at: 0)
        if let data = try? JSONEncoder().encode(Array(list.prefix(5))) {
            defaults.set(data, forKey: "nexfield_saved_accounts")
        }
    }

    func saveCachedUser(_ user: User?) {
        if let user = user, let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: "nexfield_cached_user")
        } else {
            defaults.removeObject(forKey: "nexfield_cached_user")
        }
    }

    func getCachedUser() -> User? {
        guard let data = defaults.data(forKey: "nexfield_cached_user") else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    // MARK: - Local iPhone Blueprint Storage

    var blueprintsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("NexFieldBlueprints", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func saveLocalDrawingsManifest(_ drawings: [DrawingRecord]) {
        if let data = try? JSONEncoder().encode(drawings) {
            defaults.set(data, forKey: "nexfield_local_drawings_manifest")
        }
    }

    func loadLocalDrawingsManifest() -> [DrawingRecord] {
        guard let data = defaults.data(forKey: "nexfield_local_drawings_manifest"),
              let list = try? JSONDecoder().decode([DrawingRecord].self, from: data) else {
            return []
        }
        return list
    }

    // MARK: - API Calls

    func login(email: String, password: String) async throws -> User {
        guard let url = URL(string: "\(baseUrl)/api.php?action=login") else {
            throw NSError(domain: "NexField", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "NexField", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        if (json["success"] as? Bool) == true, let userDict = json["user"] {
            let userData = try JSONSerialization.data(withJSONObject: userDict)
            let user = try JSONDecoder().decode(User.self, from: userData)
            if let tok = (json["token"] as? String) ?? user.rememberToken, !tok.isEmpty {
                rememberToken = tok
            }
            saveCachedUser(user)
            return user
        } else {
            let msg = (json["error"] as? String) ?? (json["message"] as? String) ?? "Invalid credentials"
            throw NSError(domain: "NexField", code: 401, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    func fetchServerData(userId: Int) async throws -> ServerSyncPayload {
        if let tok = rememberToken, !tok.isEmpty, let tokUrl = URL(string: "\(baseUrl)/api.php?action=token_login") {
            var tokReq = URLRequest(url: tokUrl)
            tokReq.httpMethod = "POST"
            tokReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            tokReq.httpBody = try? JSONSerialization.data(withJSONObject: ["token": tok])
            _ = try? await session.data(for: tokReq)
        }

        let cb = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "\(baseUrl)/api.php?action=get_project_data&user_id=\(userId)&_cb=\(cb)") else {
            throw NSError(domain: "NexField", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        let (data, _) = try await session.data(from: url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["success"] as? Bool) == true,
              let dataObj = root["data"] as? [String: Any] else {
            throw NSError(domain: "NexField", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to load project data"])
        }

        var user: User? = getCachedUser()
        if let uDict = dataObj["user"], let uData = try? JSONSerialization.data(withJSONObject: uDict) {
            user = (try? JSONDecoder().decode(User.self, from: uData)) ?? user
        }

        var projects: [Project] = []
        if let pArr = dataObj["projects"], let pData = try? JSONSerialization.data(withJSONObject: pArr) {
            projects = (try? JSONDecoder().decode([Project].self, from: pData)) ?? []
        }

        var drawings: [DrawingRecord] = []
        if let dArr = dataObj["drawings"], let dData = try? JSONSerialization.data(withJSONObject: dArr) {
            drawings = (try? JSONDecoder().decode([DrawingRecord].self, from: dData)) ?? []
        }

        var usersList: [User] = []
        if let uUrl = URL(string: "\(baseUrl)/api.php?action=get_users"),
           let (uData, _) = try? await session.data(from: uUrl),
           let uRoot = try? JSONSerialization.jsonObject(with: uData) as? [String: Any],
           let uArr = uRoot["data"],
           let uJson = try? JSONSerialization.data(withJSONObject: uArr) {
            usersList = (try? JSONDecoder().decode([User].self, from: uJson)) ?? []
        }

        return ServerSyncPayload(user: user, projects: projects, drawings: drawings, users: usersList)
    }

    func downloadBlueprintFile(remotePathOrDataUrl: String, destFile: URL) async throws -> URL {
        if remotePathOrDataUrl.hasPrefix("data:") {
            guard let commaIdx = remotePathOrDataUrl.firstIndex(of: ",") else {
                throw NSError(domain: "NexField", code: -3, userInfo: [NSLocalizedDescriptionKey: "Malformed data URL"])
            }
            let base64Part = String(remotePathOrDataUrl[remotePathOrDataUrl.index(after: commaIdx)...])
            guard let data = Data(base64Encoded: base64Part, options: .ignoreUnknownCharacters) else {
                throw NSError(domain: "NexField", code: -4, userInfo: [NSLocalizedDescriptionKey: "Base64 decode failed"])
            }
            try data.write(to: destFile, options: .atomic)
            return destFile
        }

        let fullUrlStr: String
        if remotePathOrDataUrl.lowercased().hasPrefix("http") {
            fullUrlStr = remotePathOrDataUrl
        } else if remotePathOrDataUrl.hasPrefix("/") {
            fullUrlStr = "\(baseUrl)\(remotePathOrDataUrl)"
        } else {
            fullUrlStr = "\(baseUrl)/\(remotePathOrDataUrl)"
        }

        guard let encoded = fullUrlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: fullUrlStr) ?? URL(string: encoded) else {
            throw NSError(domain: "NexField", code: -5, userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"])
        }

        let (data, _) = try await session.data(from: url)
        try data.write(to: destFile, options: .atomic)
        return destFile
    }

    func saveAnnotationToServer(
        drawingId: Int,
        annotatedDataUrl: String,
        annotationsDataJson: String,
        userId: Int
    ) async throws {
        guard let url = URL(string: "\(baseUrl)/api.php?action=save_annotation") else {
            throw NSError(domain: "NexField", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "drawing_id": drawingId,
            "annotated_path": annotatedDataUrl,
            "annotations_data": annotationsDataJson,
            "user_id": userId
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await session.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (json["success"] as? Bool) == true {
            return
        }
        throw NSError(domain: "NexField", code: -6, userInfo: [NSLocalizedDescriptionKey: "Failed to save annotations to server"])
    }

    func updateDrawingScaleOnServer(drawingId: Int, scaleRatio: Double) async throws {
        guard let url = URL(string: "\(baseUrl)/api.php?action=update_drawing_scale") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["drawing_id": drawingId, "scale_ratio": scaleRatio])
        _ = try? await session.data(for: req)
    }

    func deleteDrawingOnServer(userId: Int, drawingId: Int) async throws {
        guard let url = URL(string: "\(baseUrl)/api.php?action=delete_drawing") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["user_id": userId, "drawing_id": drawingId])
        _ = try await session.data(for: req)
    }
}
