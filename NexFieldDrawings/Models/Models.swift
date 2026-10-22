import Foundation
import CoreGraphics
import SwiftUI

// MARK: - User & Project Models

struct User: Codable, Identifiable, Equatable {
    var id: Int = 0
    var name: String = ""
    var email: String = ""
    var role: String = "engineer"
    var companyId: Int = 0
    var rememberToken: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, email, role
        case companyId = "company_id"
        case rememberToken = "remember_token"
    }

    init(
        id: Int = 0,
        name: String = "",
        email: String = "",
        role: String = "engineer",
        companyId: Int = 0,
        rememberToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.companyId = companyId
        self.rememberToken = rememberToken
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeInt(c, forKey: .id) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        role = (try? c.decode(String.self, forKey: .role)) ?? "engineer"
        companyId = Self.decodeInt(c, forKey: .companyId) ?? 0
        rememberToken = try? c.decode(String.self, forKey: .rememberToken)
    }

    static func decodeInt<K: CodingKey>(_ c: KeyedDecodingContainer<K>, forKey key: K) -> Int? {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }

    var isPmOrSupervisor: Bool {
        role == "pm" || role == "supervisor"
    }
}

struct Project: Codable, Identifiable, Equatable {
    var id: Int = 0
    var name: String = ""
    var companyId: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, name
        case companyId = "company_id"
    }

    init(id: Int = 0, name: String = "", companyId: Int = 0) {
        self.id = id
        self.name = name
        self.companyId = companyId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = User.decodeInt(c, forKey: .id) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        companyId = User.decodeInt(c, forKey: .companyId) ?? 0
    }
}

enum StorageSyncState: String, Codable {
    case cloudOnly = "CLOUD_ONLY"
    case downloaded = "DOWNLOADED"
    case modifiedOffline = "MODIFIED_OFFLINE"
    case localOnly = "LOCAL_ONLY"
}

struct DrawingRecord: Codable, Identifiable, Equatable {
    var id: Int = 0
    var localId: String = ""
    var projectId: Int = 0
    var projectName: String? = "General"
    var name: String = ""
    var originalPath: String = ""
    var annotatedPath: String? = nil
    var scaleRatio: Double? = nil
    var annotationsData: String? = nil
    var updatedBy: Int? = nil
    var updatedByName: String? = nil
    var updatedAt: String? = nil

    // Local iPhone storage fields
    var localFilePath: String? = nil
    var syncState: StorageSyncState = .cloudOnly
    var baseServerAnnotationsData: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case localId = "local_id"
        case projectId = "project_id"
        case projectName = "project_name"
        case name
        case originalPath = "original_path"
        case annotatedPath = "annotated_path"
        case scaleRatio = "scale_ratio"
        case annotationsData = "annotations_data"
        case updatedBy = "updated_by"
        case updatedByName = "updated_by_name"
        case updatedAt = "updated_at"
        case localFilePath
        case syncState
        case baseServerAnnotationsData
    }

    init(
        id: Int = 0,
        localId: String? = nil,
        projectId: Int = 0,
        projectName: String? = "General",
        name: String = "",
        originalPath: String = "",
        annotatedPath: String? = nil,
        scaleRatio: Double? = nil,
        annotationsData: String? = nil,
        updatedBy: Int? = nil,
        updatedByName: String? = nil,
        updatedAt: String? = nil,
        localFilePath: String? = nil,
        syncState: StorageSyncState = .cloudOnly,
        baseServerAnnotationsData: String? = nil
    ) {
        self.id = id
        self.localId = localId ?? "srv_\(id)"
        self.projectId = projectId
        self.projectName = projectName
        self.name = name
        self.originalPath = originalPath
        self.annotatedPath = annotatedPath
        self.scaleRatio = scaleRatio
        self.annotationsData = annotationsData
        self.updatedBy = updatedBy
        self.updatedByName = updatedByName
        self.updatedAt = updatedAt
        self.localFilePath = localFilePath
        self.syncState = syncState
        self.baseServerAnnotationsData = baseServerAnnotationsData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = User.decodeInt(c, forKey: .id) ?? 0
        id = decodedId
        localId = (try? c.decode(String.self, forKey: .localId)) ?? "srv_\(decodedId)"
        projectId = User.decodeInt(c, forKey: .projectId) ?? 0
        projectName = (try? c.decode(String.self, forKey: .projectName)) ?? "General"
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        originalPath = (try? c.decode(String.self, forKey: .originalPath)) ?? ""
        annotatedPath = try? c.decode(String.self, forKey: .annotatedPath)
        if let d = try? c.decode(Double.self, forKey: .scaleRatio) {
            scaleRatio = d
        } else if let s = try? c.decode(String.self, forKey: .scaleRatio), let d = Double(s) {
            scaleRatio = d
        } else {
            scaleRatio = nil
        }
        annotationsData = try? c.decode(String.self, forKey: .annotationsData)
        updatedBy = User.decodeInt(c, forKey: .updatedBy)
        updatedByName = try? c.decode(String.self, forKey: .updatedByName)
        updatedAt = try? c.decode(String.self, forKey: .updatedAt)
        localFilePath = try? c.decode(String.self, forKey: .localFilePath)
        syncState = (try? c.decode(StorageSyncState.self, forKey: .syncState)) ?? .cloudOnly
        baseServerAnnotationsData = try? c.decode(String.self, forKey: .baseServerAnnotationsData)
    }

    var isPdf: Bool {
        (localFilePath ?? originalPath).lowercased().hasSuffix(".pdf")
    }

    var isReadOnlyOriginal: Bool {
        name.contains("(Original - Read Only)")
    }

    var hasAnnotations: Bool {
        !(annotatedPath ?? "").isEmpty || !(annotationsData ?? "").isEmpty
    }

    var isSavedOnPhone: Bool {
        !(localFilePath ?? "").isEmpty && syncState != .cloudOnly
    }
}

// MARK: - Vector Annotation JSON Schema (100% compatible with Web & Android)

struct Point2D: Codable, Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
}

struct PinAnnotation: Codable, Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var type: String = "Pin 1"
    var baseType: String = "Pin"
    var color: String = "#ff3b30"
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0
    var userId: Int? = nil

    enum CodingKeys: String, CodingKey {
        case x, y, type, baseType, color, scale, rotation
        case userId = "user_id"
    }

    init(
        x: CGFloat = 0,
        y: CGFloat = 0,
        type: String = "Pin 1",
        baseType: String = "Pin",
        color: String = "#ff3b30",
        scale: CGFloat = 1.0,
        rotation: CGFloat = 0.0,
        userId: Int? = nil
    ) {
        self.x = x
        self.y = y
        self.type = type
        self.baseType = baseType
        self.color = color
        self.scale = scale
        self.rotation = rotation
        self.userId = userId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = (try? c.decode(CGFloat.self, forKey: .x)) ?? 0
        y = (try? c.decode(CGFloat.self, forKey: .y)) ?? 0
        type = (try? c.decode(String.self, forKey: .type)) ?? "Pin 1"
        baseType = (try? c.decode(String.self, forKey: .baseType)) ?? "Pin"
        color = (try? c.decode(String.self, forKey: .color)) ?? "#ff3b30"
        scale = (try? c.decode(CGFloat.self, forKey: .scale)) ?? 1.0
        rotation = (try? c.decode(CGFloat.self, forKey: .rotation)) ?? 0.0
        userId = User.decodeInt(c, forKey: .userId)
    }
}

struct ShapeAnnotation: Codable, Equatable {
    var type: String = "line" // "pen", "line", "arrow", "ruler", "rect", "circle", "triangle"
    var x: CGFloat = 0
    var y: CGFloat = 0
    var x2: CGFloat = 0
    var y2: CGFloat = 0
    var points: [Point2D]? = nil
    var color: String = "#ff3b30"
    var fill: Bool = false
    var orientation: String = "0" // "0", "90", "180", "270" for triangles
    var rotation: CGFloat = 0.0
    var lineWidth: CGFloat = 3.0
    var userId: Int? = nil

    enum CodingKeys: String, CodingKey {
        case type, x, y, x2, y2, points, color, fill, orientation, rotation, lineWidth
        case userId = "user_id"
    }

    init(
        type: String = "line",
        x: CGFloat = 0,
        y: CGFloat = 0,
        x2: CGFloat = 0,
        y2: CGFloat = 0,
        points: [Point2D]? = nil,
        color: String = "#ff3b30",
        fill: Bool = false,
        orientation: String = "0",
        rotation: CGFloat = 0.0,
        lineWidth: CGFloat = 3.0,
        userId: Int? = nil
    ) {
        self.type = type
        self.x = x
        self.y = y
        self.x2 = x2
        self.y2 = y2
        self.points = points
        self.color = color
        self.fill = fill
        self.orientation = orientation
        self.rotation = rotation
        self.lineWidth = lineWidth
        self.userId = userId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "line"
        x = (try? c.decode(CGFloat.self, forKey: .x)) ?? 0
        y = (try? c.decode(CGFloat.self, forKey: .y)) ?? 0
        x2 = (try? c.decode(CGFloat.self, forKey: .x2)) ?? 0
        y2 = (try? c.decode(CGFloat.self, forKey: .y2)) ?? 0
        points = try? c.decode([Point2D].self, forKey: .points)
        color = (try? c.decode(String.self, forKey: .color)) ?? "#ff3b30"
        fill = (try? c.decode(Bool.self, forKey: .fill)) ?? false
        orientation = (try? c.decode(String.self, forKey: .orientation)) ?? "0"
        rotation = (try? c.decode(CGFloat.self, forKey: .rotation)) ?? 0.0
        lineWidth = (try? c.decode(CGFloat.self, forKey: .lineWidth)) ?? 3.0
        userId = User.decodeInt(c, forKey: .userId)
    }
}

struct TextAnnotation: Codable, Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var text: String = ""
    var color: String = "#ff3b30"
    var bgColor: String? = "transparent"
    var hasBorder: Bool = true
    var borderColor: String? = "#ff3b30"
    var borderWidth: CGFloat = 3.0
    var fontSize: Int = 16
    var fontWeight: String = "bold"
    var fontFamily: String = "Outfit, sans-serif"
    var rotation: Int = 0
    var origRotation: Int = 0
    var layout: String = "0"
    var isPdfReplacement: Bool = false
    var origWidth: CGFloat = 80
    var boxLeft: CGFloat = -8
    var boxRight: CGFloat = 88
    var boxTop: CGFloat = -21
    var boxBottom: CGFloat = 5
    var userId: Int? = nil

    enum CodingKeys: String, CodingKey {
        case x, y, text, color, bgColor, hasBorder, borderColor, borderWidth
        case fontSize, fontWeight, fontFamily, rotation, origRotation, layout
        case isPdfReplacement, origWidth, boxLeft, boxRight, boxTop, boxBottom
        case userId = "user_id"
    }

    init(
        x: CGFloat = 0,
        y: CGFloat = 0,
        text: String = "",
        color: String = "#ff3b30",
        bgColor: String? = "transparent",
        hasBorder: Bool = true,
        borderColor: String? = "#ff3b30",
        borderWidth: CGFloat = 3.0,
        fontSize: Int = 16,
        fontWeight: String = "bold",
        fontFamily: String = "Outfit, sans-serif",
        rotation: Int = 0,
        origRotation: Int = 0,
        layout: String = "0",
        isPdfReplacement: Bool = false,
        origWidth: CGFloat = 80,
        boxLeft: CGFloat = -8,
        boxRight: CGFloat = 88,
        boxTop: CGFloat = -21,
        boxBottom: CGFloat = 5,
        userId: Int? = nil
    ) {
        self.x = x
        self.y = y
        self.text = text
        self.color = color
        self.bgColor = bgColor
        self.hasBorder = hasBorder
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontFamily = fontFamily
        self.rotation = rotation
        self.origRotation = origRotation
        self.layout = layout
        self.isPdfReplacement = isPdfReplacement
        self.origWidth = origWidth
        self.boxLeft = boxLeft
        self.boxRight = boxRight
        self.boxTop = boxTop
        self.boxBottom = boxBottom
        self.userId = userId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = (try? c.decode(CGFloat.self, forKey: .x)) ?? 0
        y = (try? c.decode(CGFloat.self, forKey: .y)) ?? 0
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        color = (try? c.decode(String.self, forKey: .color)) ?? "#ff3b30"
        bgColor = (try? c.decode(String.self, forKey: .bgColor)) ?? "transparent"
        hasBorder = (try? c.decode(Bool.self, forKey: .hasBorder)) ?? true
        borderColor = (try? c.decode(String.self, forKey: .borderColor)) ?? color
        borderWidth = (try? c.decode(CGFloat.self, forKey: .borderWidth)) ?? 3.0
        fontSize = User.decodeInt(c, forKey: .fontSize) ?? 16
        fontWeight = (try? c.decode(String.self, forKey: .fontWeight)) ?? "bold"
        fontFamily = (try? c.decode(String.self, forKey: .fontFamily)) ?? "Outfit, sans-serif"
        rotation = User.decodeInt(c, forKey: .rotation) ?? 0
        origRotation = User.decodeInt(c, forKey: .origRotation) ?? 0
        layout = (try? c.decode(String.self, forKey: .layout)) ?? "0"
        isPdfReplacement = (try? c.decode(Bool.self, forKey: .isPdfReplacement)) ?? false
        origWidth = (try? c.decode(CGFloat.self, forKey: .origWidth)) ?? 80
        boxLeft = (try? c.decode(CGFloat.self, forKey: .boxLeft)) ?? -8
        boxRight = (try? c.decode(CGFloat.self, forKey: .boxRight)) ?? 88
        boxTop = (try? c.decode(CGFloat.self, forKey: .boxTop)) ?? -21
        boxBottom = (try? c.decode(CGFloat.self, forKey: .boxBottom)) ?? 5
        userId = User.decodeInt(c, forKey: .userId)
    }
}

struct PhotoAnnotation: Codable, Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var url: String = ""
    var localPath: String? = nil
    var caption: String = ""
    var scale: CGFloat = 1.0
    var rotation: CGFloat = 0.0
    var userId: Int? = nil

    enum CodingKeys: String, CodingKey {
        case x, y, url, localPath, caption, scale, rotation
        case userId = "user_id"
    }

    init(
        x: CGFloat = 0,
        y: CGFloat = 0,
        url: String = "",
        localPath: String? = nil,
        caption: String = "",
        scale: CGFloat = 1.0,
        rotation: CGFloat = 0.0,
        userId: Int? = nil
    ) {
        self.x = x
        self.y = y
        self.url = url
        self.localPath = localPath
        self.caption = caption
        self.scale = scale
        self.rotation = rotation
        self.userId = userId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = (try? c.decode(CGFloat.self, forKey: .x)) ?? 0
        y = (try? c.decode(CGFloat.self, forKey: .y)) ?? 0
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        localPath = try? c.decode(String.self, forKey: .localPath)
        caption = (try? c.decode(String.self, forKey: .caption)) ?? ""
        scale = (try? c.decode(CGFloat.self, forKey: .scale)) ?? 1.0
        rotation = (try? c.decode(CGFloat.self, forKey: .rotation)) ?? 0.0
        userId = User.decodeInt(c, forKey: .userId)
    }
}

enum SelectionManipMode: String, CaseIterable {
    case move = "Move"
    case resize = "Resize"
    case rotate = "Rotate"

    var iconEmoji: String {
        switch self {
        case .move: return "✋"
        case .resize: return "⤡"
        case .rotate: return "🔄"
        }
    }

    func next() -> SelectionManipMode {
        switch self {
        case .move: return .resize
        case .resize: return .rotate
        case .rotate: return .move
        }
    }
}

struct PageAnnotations: Codable, Equatable {
    var pins: [PinAnnotation] = []
    var texts: [TextAnnotation] = []
    var shapes: [ShapeAnnotation] = []
    var photos: [PhotoAnnotation] = []

    init(
        pins: [PinAnnotation] = [],
        texts: [TextAnnotation] = [],
        shapes: [ShapeAnnotation] = [],
        photos: [PhotoAnnotation] = []
    ) {
        self.pins = pins
        self.texts = texts
        self.shapes = shapes
        self.photos = photos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pins = (try? c.decode([PinAnnotation].self, forKey: .pins)) ?? []
        texts = (try? c.decode([TextAnnotation].self, forKey: .texts)) ?? []
        shapes = (try? c.decode([ShapeAnnotation].self, forKey: .shapes)) ?? []
        photos = (try? c.decode([PhotoAnnotation].self, forKey: .photos)) ?? []
    }
}

struct AnnotationsEnvelope: Codable {
    var pages: [String: PageAnnotations]? = nil
    var pins: [PinAnnotation]? = nil
    var texts: [TextAnnotation]? = nil
    var shapes: [ShapeAnnotation]? = nil
    var photos: [PhotoAnnotation]? = nil

    static func parse(_ jsonStr: String?) -> [Int: PageAnnotations] {
        guard let raw = jsonStr, !raw.trimmingCharacters(inSpacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8) else {
            return [:]
        }
        var result: [Int: PageAnnotations] = [:]
        if let env = try? JSONDecoder().decode(AnnotationsEnvelope.self, from: data) {
            if let pages = env.pages, !pages.isEmpty {
                for (k, v) in pages {
                    if let pageNum = Int(k) {
                        result[pageNum] = v
                    }
                }
                return result
            }
        }
        if let singlePage = try? JSONDecoder().decode(PageAnnotations.self, from: data) {
            result[1] = singlePage
        }
        return result
    }

    static func serialize(_ pagesMap: [Int: PageAnnotations]) -> String {
        var strMap: [String: PageAnnotations] = [:]
        for (k, v) in pagesMap {
            strMap[String(k)] = v
        }
        let page1 = pagesMap[1] ?? PageAnnotations()
        let env = AnnotationsEnvelope(
            pages: strMap,
            pins: page1.pins,
            texts: page1.texts,
            shapes: page1.shapes,
            photos: page1.photos
        )
        guard let data = try? JSONEncoder().encode(env),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    static func threeWayMerge(
        baseJson: String?,
        serverJson: String?,
        localPagesMap: [Int: PageAnnotations]
    ) -> (merged: [Int: PageAnnotations], preservedTeamItems: Int) {
        let baseMap = parse(baseJson)
        let serverMap = parse(serverJson)
        var allPageNums = Set(baseMap.keys).union(serverMap.keys).union(localPagesMap.keys)
        if allPageNums.isEmpty { allPageNums.insert(1) }

        var mergedResult: [Int: PageAnnotations] = [:]
        var teamCount = 0

        for pageNum in allPageNums {
            let basePage = baseMap[pageNum] ?? PageAnnotations()
            let srvPage = serverMap[pageNum] ?? PageAnnotations()
            let locPage = localPagesMap[pageNum] ?? PageAnnotations()

            if srvPage.pins.isEmpty && srvPage.texts.isEmpty && srvPage.shapes.isEmpty && srvPage.photos.isEmpty {
                mergedResult[pageNum] = locPage
                continue
            }

            var mergedPins = locPage.pins
            var mergedTexts = locPage.texts
            var mergedShapes = locPage.shapes
            var mergedPhotos = locPage.photos

            for sPin in srvPage.pins {
                let inLocal = mergedPins.contains { samePin($0, sPin) }
                let wasInBase = basePage.pins.contains { samePin($0, sPin) }
                if !inLocal && !wasInBase {
                    mergedPins.append(sPin)
                    teamCount += 1
                }
            }

            for sTxt in srvPage.texts {
                let inLocal = mergedTexts.contains { sameText($0, sTxt) }
                let wasInBase = basePage.texts.contains { sameText($0, sTxt) }
                let overridden = mergedTexts.contains { hypot($0.x - sTxt.x, $0.y - sTxt.y) < 8.0 }
                if !inLocal && !wasInBase && !overridden {
                    mergedTexts.append(sTxt)
                    teamCount += 1
                }
            }

            for sShape in srvPage.shapes {
                let inLocal = mergedShapes.contains { sameShape($0, sShape) }
                let wasInBase = basePage.shapes.contains { sameShape($0, sShape) }
                if !inLocal && !wasInBase {
                    mergedShapes.append(sShape)
                    teamCount += 1
                }
            }

            for sPhoto in srvPage.photos {
                let inLocal = mergedPhotos.contains { samePhoto($0, sPhoto) }
                let wasInBase = basePage.photos.contains { samePhoto($0, sPhoto) }
                if !inLocal && !wasInBase {
                    mergedPhotos.append(sPhoto)
                    teamCount += 1
                }
            }

            mergedResult[pageNum] = PageAnnotations(
                pins: mergedPins,
                texts: mergedTexts,
                shapes: mergedShapes,
                photos: mergedPhotos
            )
        }
        return (mergedResult, teamCount)
    }

    private static func samePin(_ a: PinAnnotation, _ b: PinAnnotation) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 4.0 && a.type == b.type && a.color.caseInsensitiveCompare(b.color) == .orderedSame
    }

    private static func sameText(_ a: TextAnnotation, _ b: TextAnnotation) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 4.0 && a.text == b.text && a.rotation == b.rotation && a.layout == b.layout
    }

    private static func sameShape(_ a: ShapeAnnotation, _ b: ShapeAnnotation) -> Bool {
        if a.type != b.type || a.color.caseInsensitiveCompare(b.color) != .orderedSame { return false }
        if a.type == "pen" {
            guard let ptsA = a.points, let ptsB = b.points, ptsA.count == ptsB.count, let fA = ptsA.first, let fB = ptsB.first, let lA = ptsA.last, let lB = ptsB.last else { return false }
            return hypot(fA.x - fB.x, fA.y - fB.y) < 4.0 && hypot(lA.x - lB.x, lA.y - lB.y) < 4.0
        }
        return hypot(a.x - b.x, a.y - b.y) < 4.0 && hypot(a.x2 - b.x2, a.y2 - b.y2) < 4.0
    }

    private static func samePhoto(_ a: PhotoAnnotation, _ b: PhotoAnnotation) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 6.0 && (a.url == b.url || a.caption == b.caption)
    }
}

private extension CharacterSet {
    static var inSpacesAndNewlines: CharacterSet { .whitespacesAndNewlines }
}

// MARK: - PDF Text Item & Tools

struct PdfTextItem: Identifiable, Equatable {
    var id = UUID()
    var str: String
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var fontHeight: CGFloat
    var fontSize: Int
    var fontWeight: String = "normal"
    var angleDeg: Int = 0
    var origRotation: Int = 0
    var layout: String = "0"
    var isExistingAnnotationIndex: Int? = nil
}

enum DrawingTool: String, CaseIterable, Identifiable {
    case select = "select"
    case pan = "pan"
    case eraser = "eraser"
    case pin = "pin"
    case pen = "pen"
    case ruler = "ruler"
    case line = "line"
    case arrow = "arrow"
    case rect = "rect"
    case circle = "circle"
    case triangle = "triangle"
    case photo = "photo"
    case text = "text"
    case editPdfText = "edit-text"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: return "Select"
        case .pan: return "Pan"
        case .eraser: return "Eraser"
        case .pin: return "Pin"
        case .pen: return "Pen"
        case .ruler: return "Ruler"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rect: return "Square"
        case .circle: return "Circle"
        case .triangle: return "Triangle"
        case .photo: return "Photo"
        case .text: return "Text"
        case .editPdfText: return "Edit PDF Text"
        }
    }

    var iconEmoji: String {
        switch self {
        case .select: return "🖱️"
        case .pan: return "✋"
        case .eraser: return "🧽"
        case .pin: return "📍"
        case .pen: return "✏️"
        case .ruler: return "📏"
        case .line: return "➖"
        case .arrow: return "➡️"
        case .rect: return "⬜"
        case .circle: return "⚪"
        case .triangle: return "🔺"
        case .photo: return "📷"
        case .text: return "🔠"
        case .editPdfText: return "✍️"
        }
    }
}

struct PinCategory {
    let categoryName: String
    let items: [(name: String, emoji: String)]
}

enum PinCatalog {
    static let categories: [PinCategory] = [
        PinCategory(
            categoryName: "📂 General / Site",
            items: [
                ("Standard Pin", "📍"),
                ("General Note", "📝"),
                ("Fix Needed", "🔧"),
                ("Water Leak", "💧")
            ]
        ),
        PinCategory(
            categoryName: "⚡ Electrical",
            items: [
                ("Ceiling Light", "💡"),
                ("Power Socket", "🔌"),
                ("Distribution Board", "⚡"),
                ("Light Switch", "🔘"),
                ("Isolator Switch", "🎚️")
            ]
        ),
        PinCategory(
            categoryName: "📶 Data & Telecom",
            items: [
                ("Cabinet / Rack", "🗄️"),
                ("Switch", "🔀"),
                ("Router / Gateway", "🌐"),
                ("Patch Panel", "🎛️"),
                ("Wi-Fi Access Point", "📶"),
                ("Data Outlet (RJ45)", "🔗"),
                ("Coax Outlet", "📺")
            ]
        ),
        PinCategory(
            categoryName: "🚨 Fire Alarm System",
            items: [
                ("Fire Alarm Panel", "🚨"),
                ("Smoke Detector", "🔥"),
                ("Heat Detector", "🌡️"),
                ("Break Glass Call Point", "🟩"),
                ("Sounder Strobe", "🔊")
            ]
        ),
        PinCategory(
            categoryName: "🛡️ Security & Access Control",
            items: [
                ("CCTV Camera", "📷"),
                ("Card Reader", "🔑"),
                ("Push to Exit Button", "🟢"),
                ("Magnetic Lock", "🧲"),
                ("Motion Sensor", "👁️"),
                ("Intercom Station", "📞"),
                ("Intruder Keypad", "🔢")
            ]
        )
    ]

    static func resolveEmoji(_ typeOrBase: String) -> String {
        for cat in categories {
            for item in cat.items {
                if typeOrBase.lowercased().hasPrefix(item.name.lowercased()) {
                    return item.emoji
                }
            }
        }
        return "📍"
    }
}
