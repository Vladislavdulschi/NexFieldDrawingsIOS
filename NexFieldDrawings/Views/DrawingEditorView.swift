import SwiftUI
import UIKit

struct SelectedElementRef: Equatable {
    var type: String // "pin", "text", "shape", "photo"
    var index: Int
}

struct ElementGeometry {
    var cx: CGFloat
    var cy: CGFloat
    var halfW: CGFloat
    var halfH: CGFloat
    var bottomY: CGFloat { cy + halfH }
    var rightX: CGFloat { cx + halfW }
}

struct SmartAlignmentGuide {
    var isHorizontalLevel: Bool
    var refCx: CGFloat
    var refCy: CGFloat
    var refBottomY: CGFloat
    var refRightX: CGFloat
    var targetCx: CGFloat
    var targetCy: CGFloat
    var targetBottomY: CGFloat
    var targetRightX: CGFloat
    var distancePx: CGFloat
}

struct DrawingEditorView: View {
    @ObservedObject var viewModel: DrawingsViewModel
    let drawing: DrawingRecord

    // Page & Image State
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    @State private var pageUIImage: UIImage? = nil
    @State private var allPagesAnnotations: [Int: PageAnnotations] = [:]
    @State private var scaleRatio: Double? = nil

    // Undo / Redo Stacks
    @State private var undoStack: [PageAnnotations] = []
    @State private var redoStack: [PageAnnotations] = []

    // Active Tool & Style Options
    @State private var activeTool: DrawingTool = .pan
    @State private var drawColorHex: String = "#ff3b30"
    @State private var fillShape: Bool = false
    @State private var lineWidthPx: CGFloat = 3.0
    @State private var selectedPinBaseType: String = "Standard Pin"

    // Selection & Multi-Tap Cycling (Move -> Resize -> Rotate)
    @State private var selectedElement: SelectedElementRef? = nil
    @State private var selectionManipMode: SelectionManipMode = .move
    @State private var smartAlignmentGuide: SmartAlignmentGuide? = nil

    // Viewport Transform
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var rotationAngle: Double = 0
    @State private var isFocusMode: Bool = false
    @State private var showBottomToolsMenu: Bool = false

    // Gesture / Drag State
    @State private var dragStartCanvasPt: CGPoint? = nil
    @State private var dragCurrentCanvasPt: CGPoint? = nil
    @State private var activePenPoints: [Point2D] = []
    @State private var hasPassedSlop: Bool = false
    @State private var tappedAlreadySelected: Bool = false
    @State private var initialShapeSnapshot: ShapeAnnotation? = nil
    @State private var initialPinSnapshot: PinAnnotation? = nil
    @State private var initialTextSnapshot: TextAnnotation? = nil

    // Dialogs & Export
    @State private var showTextPrompt: Bool = false
    @State private var pendingTextPt: CGPoint = .zero
    @State private var textPromptInput: String = ""
    @State private var showScalePrompt: Bool = false
    @State private var pendingScalePxDist: CGFloat = 0
    @State private var scaleMetersInput: String = "1.0"
    @State private var isCalibratingScale: Bool = false
    @State private var exportedPdfURL: URL? = nil
    @State private var showShareSheet: Bool = false

    private var activePageAnnotations: PageAnnotations {
        get { allPagesAnnotations[currentPage] ?? PageAnnotations() }
        nonmutating set { allPagesAnnotations[currentPage] = newValue }
    }

    private var selectedShapeObj: ShapeAnnotation? {
        guard let sel = selectedElement, sel.type == "shape",
              activePageAnnotations.shapes.indices.contains(sel.index) else { return nil }
        return activePageAnnotations.shapes[sel.index]
    }

    private var selectedTextObj: TextAnnotation? {
        guard let sel = selectedElement, sel.type == "text",
              activePageAnnotations.texts.indices.contains(sel.index) else { return nil }
        return activePageAnnotations.texts[sel.index]
    }

    private var selectedPinObj: PinAnnotation? {
        guard let sel = selectedElement, sel.type == "pin",
              activePageAnnotations.pins.indices.contains(sel.index) else { return nil }
        return activePageAnnotations.pins[sel.index]
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.11)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. Top Header Bar (Hidden in Focus Mode)
                if !isFocusMode {
                    topHeaderBar
                }

                // 2. Main Interactive Blueprint Canvas Area
                GeometryReader { geo in
                    ZStack {
                        canvasView(in: geo.size)

                        // Floating Contextual Additional Toolbar: ONLY (Move, Colour, Clone, Delete, px thickness)
                        if !showBottomToolsMenu && (selectedElement != nullRef || activeTool != .pan) {
                            VStack {
                                Spacer()
                                additionalToolbar
                                    .padding(.bottom, 64)
                            }
                        }

                        // Expandable Tools Palette
                        if showBottomToolsMenu {
                            VStack {
                                Spacer()
                                toolsMenuPalette
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 66)
                            }
                        }

                        // Bottom Quick-Access Dock: [↩️ | ↪️] + [Tools ▲] + [🔄] + [⛶]
                        VStack {
                            Spacer()
                            bottomDockBar
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadDrawingData()
        }
        .alert("Add Text Label", isPresented: $showTextPrompt) {
            TextField("Enter text...", text: $textPromptInput)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let clean = textPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }
                pushUndoSnapshot()
                var page = activePageAnnotations
                page.texts.append(
                    TextAnnotation(
                        x: pendingTextPt.x,
                        y: pendingTextPt.y,
                        text: clean,
                        color: drawColorHex,
                        bgColor: fillShape ? "#ffffff" : "transparent",
                        hasBorder: true,
                        borderColor: drawColorHex,
                        borderWidth: lineWidthPx,
                        fontSize: 16,
                        userId: viewModel.currentUser?.id
                    )
                )
                allPagesAnnotations[currentPage] = page
                selectedElement = SelectedElementRef(type: "text", index: page.texts.count - 1)
                selectionManipMode = .move
            }
        }
        .alert("Calibrate Blueprint Scale", isPresented: $showScalePrompt) {
            TextField("Real distance in meters (e.g. 2.5)", text: $scaleMetersInput)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { isCalibratingScale = false }
            Button("Set Scale") {
                if let meters = Double(scaleMetersInput.replacingOccurrences(of: ",", with: ".")), meters > 0 {
                    scaleRatio = Double(pendingScalePxDist) / meters
                    viewModel.statusBannerMessage = String(format: "Scale calibrated: %.1f px/m", scaleRatio ?? 0)
                }
                isCalibratingScale = false
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedPdfURL {
                ShareSheetView(items: [url])
            }
        }
    }

    private var nullRef: SelectedElementRef? { nil }

    // MARK: - Top Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.activeDrawing = nil
            } label: {
                Text("← Back")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.15, green: 0.20, blue: 0.29))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Text(drawing.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)

            if totalPages > 1 {
                HStack(spacing: 4) {
                    Button("◀") {
                        if currentPage > 1 {
                            currentPage -= 1
                            selectedElement = nil
                            renderCurrentPage()
                        }
                    }
                    .disabled(currentPage <= 1)
                    Text("\(currentPage)/\(totalPages)")
                        .font(.system(size: 11, weight: .bold))
                    Button("▶") {
                        if currentPage < totalPages {
                            currentPage += 1
                            selectedElement = nil
                            renderCurrentPage()
                        }
                    }
                    .disabled(currentPage >= totalPages)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(red: 0.15, green: 0.20, blue: 0.29))
                .cornerRadius(6)
            }

            Spacer()

            Button {
                viewModel.saveAnnotationsToPhone(
                    drawing: drawing,
                    allPagesAnnotations: allPagesAnnotations,
                    scaleRatio: scaleRatio
                )
            } label: {
                Text("💾 Phone")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.05, green: 0.58, blue: 0.53))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Button {
                Task {
                    let preview: UIImage? = pageUIImage.map {
                        BlueprintPdfEngine.renderCompositeImage(
                            baseImage: $0,
                            annotations: activePageAnnotations,
                            scaleRatio: scaleRatio
                        )
                    }
                    await viewModel.saveAnnotationsToCloud(
                        drawing: drawing,
                        allPagesAnnotations: allPagesAnnotations,
                        scaleRatio: scaleRatio,
                        previewImage: preview
                    )
                }
            } label: {
                Text("☁️ Cloud")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.15, green: 0.39, blue: 0.92))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Button {
                exportPdf()
            } label: {
                Text("📄 PDF")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.96, green: 0.62, blue: 0.04))
                    .foregroundColor(.black)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(red: 0.07, green: 0.10, blue: 0.16))
    }

    // MARK: - Simplified Additional Toolbar: ONLY (Move, Colour, Clone, Delete, px thickness)

    private var additionalToolbar: some View {
        let colorOptions: [(hex: String, name: String)] = [
            ("#ff3b30", "Red"),
            ("#007aff", "Blue"),
            ("#34c759", "Green"),
            ("#ff9500", "Orange"),
            ("#af52de", "Purple"),
            ("#18181b", "Black")
        ]
        let effectiveHex = selectedShapeObj?.color
            ?? selectedTextObj?.color
            ?? selectedPinObj?.color
            ?? drawColorHex
        let activeColorName = colorOptions.first(where: { $0.hex.caseInsensitiveCompare(effectiveHex) == .orderedSame })?.name ?? "Colour"
        let isCurrentlyFilled: Bool = {
            if let sh = selectedShapeObj { return sh.fill }
            if let t = selectedTextObj { return !(t.bgColor ?? "").isEmpty && t.bgColor != "transparent" }
            return fillShape
        }()
        let isMoveActive = (selectedElement != nil && selectionManipMode == .move) || (selectedElement == nil && activeTool == .select)
        let canClone = selectedElement != nil || !activePageAnnotations.shapes.isEmpty
        let canDelete = selectedElement != nil
        let curWidth = Int(selectedShapeObj?.lineWidth ?? lineWidthPx)

        return HStack(spacing: 6) {
            // 1. Move
            Button {
                activeTool = .select
                selectionManipMode = .move
            } label: {
                Text("✋ Move")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(isMoveActive ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(red: 0.12, green: 0.16, blue: 0.23))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isMoveActive ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.gray.opacity(0.5), lineWidth: 1)
                    )
            }

            // 2. Colour (with Fill option under all colors)
            Menu {
                ForEach(colorOptions, id: \.hex) { item in
                    Button {
                        applyColorSelection(item.hex)
                    } label: {
                        Label(item.name, systemImage: effectiveHex.caseInsensitiveCompare(item.hex) == .orderedSame ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
                Divider()
                Button {
                    applyFillToggle(!isCurrentlyFilled)
                } label: {
                    Label(isCurrentlyFilled ? "☑ Fill (On)" : "☐ Fill (Off)", systemImage: isCurrentlyFilled ? "checkmark.square.fill" : "square")
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(BlueprintPdfEngine.parseHexColor(effectiveHex))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    Text("\(activeColorName) ▼")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color(red: 0.12, green: 0.16, blue: 0.23))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
            }

            // 3. Clone
            Button {
                if selectedElement == nil, !activePageAnnotations.shapes.isEmpty {
                    selectedElement = SelectedElementRef(type: "shape", index: activePageAnnotations.shapes.count - 1)
                }
                cloneSelectedElement()
            } label: {
                Text("📋 Clone")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(canClone ? .white : .gray)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(canClone ? Color(red: 0.23, green: 0.51, blue: 0.96) : Color(red: 0.12, green: 0.16, blue: 0.23))
                    .cornerRadius(14)
            }
            .disabled(!canClone)

            // 4. Delete
            Button {
                deleteSelectedElement()
            } label: {
                Text("🗑️ Delete")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(canDelete ? .white : .gray)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(canDelete ? Color(red: 0.94, green: 0.27, blue: 0.27) : Color(red: 0.12, green: 0.16, blue: 0.23))
                    .cornerRadius(14)
            }
            .disabled(!canDelete)

            // 5. px thickness
            Menu {
                ForEach([1, 3, 6, 10], id: \.self) { w in
                    Button("\(w)px") {
                        applyLineWidth(CGFloat(w))
                    }
                }
            } label: {
                Text("\(curWidth)px ▼")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color(red: 0.12, green: 0.16, blue: 0.23))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.95))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(red: 0.22, green: 0.25, blue: 0.32), lineWidth: 1)
        )
        .shadow(radius: 8)
    }

    // MARK: - Bottom Dock Bar: [↩️ | ↪️] + [Tools ▲] + [🔄] + [⛶]

    private var bottomDockBar: some View {
        HStack {
            // 1. Undo / Redo Pill
            HStack(spacing: 6) {
                Button {
                    performUndo()
                } label: {
                    Text("↩️")
                        .font(.system(size: 15))
                        .opacity(undoStack.isEmpty ? 0.35 : 1.0)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .disabled(undoStack.isEmpty)

                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 1, height: 18)

                Button {
                    performRedo()
                } label: {
                    Text("↪️")
                        .font(.system(size: 15))
                        .opacity(redoStack.isEmpty ? 0.35 : 1.0)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .disabled(redoStack.isEmpty)
            }
            .padding(.horizontal, 6)
            .background(Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.95))
            .cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.gray.opacity(0.35), lineWidth: 1))

            Spacer()

            // 2. Clean "Tools ▲" Button (Text + Arrow only, no extra icons)
            Button {
                showBottomToolsMenu.toggle()
            } label: {
                let arrow = showBottomToolsMenu ? "▼" : "▲"
                Text("Tools \(arrow)")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(Color(red: 0.07, green: 0.09, blue: 0.15))
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Color(red: 0.96, green: 0.62, blue: 0.04))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(showBottomToolsMenu ? Color.white : Color(red: 0.85, green: 0.47, blue: 0.02), lineWidth: 1.5)
                    )
                    .shadow(radius: 6)
            }

            Spacer()

            // 3. Rotate Blueprint + Focus Mode Buttons
            HStack(spacing: 8) {
                Button {
                    rotationAngle = (rotationAngle + 90).truncatingRemainder(dividingBy: 360)
                } label: {
                    Text("🔄")
                        .font(.system(size: 16))
                        .frame(width: 40, height: 40)
                        .background(Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.95))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.35), lineWidth: 1))
                }

                Button {
                    isFocusMode.toggle()
                } label: {
                    Text(isFocusMode ? "✕" : "⛶")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(isFocusMode ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.95))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.35), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Expandable Tools Menu Palette

    private var toolsMenuPalette: some View {
        let groups: [(title: String, tools: [DrawingTool])] = [
            ("NAVIGATION & EDITING", [.select, .pan, .eraser]),
            ("MARKERS & MEASUREMENTS", [.pin, .text, .ruler]),
            ("SHAPES & MARKUP", [.pen, .line, .arrow, .rect, .circle, .triangle])
        ]

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DRAWING TOOLS")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                Spacer()
                Button("🔍 Fit Page") {
                    zoomScale = 1.0
                    panOffset = .zero
                    showBottomToolsMenu = false
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 0.12, green: 0.16, blue: 0.23))
                .cornerRadius(12)

                Button("✕") {
                    showBottomToolsMenu = false
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.gray)
                .padding(.leading, 6)
            }

            ForEach(groups, id: \.title) { grp in
                Text(grp.title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)

                let rows = stride(from: 0, to: grp.tools.count, by: 3).map {
                    Array(grp.tools[$0..<min($0 + 3, grp.tools.count)])
                }
                ForEach(rows.indices, id: \.self) { rIdx in
                    HStack(spacing: 6) {
                        ForEach(rows[rIdx]) { tool in
                            let isCurrent = activeTool == tool
                            Button {
                                activeTool = tool
                                showBottomToolsMenu = false
                            } label: {
                                Text("\(tool.iconEmoji) \(tool.label)")
                                    .font(.system(size: 11, weight: isCurrent ? .black : .semibold))
                                    .foregroundColor(isCurrent ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(isCurrent ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 0.12, green: 0.16, blue: 0.23))
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.97))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.96, green: 0.62, blue: 0.04), lineWidth: 1.5))
        .shadow(radius: 14)
    }

    // MARK: - Interactive Blueprint Canvas

    private func canvasView(in containerSize: CGSize) -> some View {
        let imgSize = pageUIImage?.size ?? CGSize(width: 1200, height: 900)
        let fitScale = min(
            max(0.1, containerSize.width / max(1, imgSize.width)),
            max(0.1, containerSize.height / max(1, imgSize.height))
        )
        let effScale = fitScale * zoomScale
        let originX = (containerSize.width - imgSize.width * effScale) / 2.0 + panOffset.width
        let originY = (containerSize.height - imgSize.height * effScale) / 2.0 + panOffset.height

        func toCanvas(_ screenPt: CGPoint) -> CGPoint {
            CGPoint(
                x: (screenPt.x - originX) / effScale,
                y: (screenPt.y - originY) / effScale
            )
        }

        return Canvas { context, _ in
            context.translateBy(x: originX, y: originY)
            context.scaleBy(x: effScale, y: effScale)

            // 1. Draw Blueprint Background
            if let uiImg = pageUIImage {
                context.draw(Image(uiImage: uiImg), in: CGRect(origin: .zero, size: imgSize))
            }

            // 2. Draw Vector Shapes
            for sh in activePageAnnotations.shapes {
                drawShape(sh, in: &context)
            }

            // 3. Draw Active Shape Preview while dragging
            if let sPt = dragStartCanvasPt, let cPt = dragCurrentCanvasPt, selectedElement == nil {
                if activeTool == .pen && activePenPoints.count > 1 {
                    let previewPen = ShapeAnnotation(type: "pen", points: activePenPoints, color: drawColorHex, lineWidth: lineWidthPx)
                    drawShape(previewPen, in: &context)
                } else if [.line, .arrow, .ruler, .rect, .circle, .triangle].contains(activeTool) {
                    let previewSh = ShapeAnnotation(
                        type: activeTool.rawValue,
                        x: sPt.x,
                        y: sPt.y,
                        x2: cPt.x,
                        y2: cPt.y,
                        color: drawColorHex,
                        fill: fillShape,
                        lineWidth: lineWidthPx
                    )
                    drawShape(previewSh, in: &context)
                }
            }

            // 4. Draw Texts
            for t in activePageAnnotations.texts {
                let color = BlueprintPdfEngine.parseHexColor(t.color)
                let txt = Text(t.text)
                    .font(.system(size: CGFloat(max(10, t.fontSize)), weight: .bold))
                    .foregroundColor(color)
                context.draw(txt, at: CGPoint(x: t.x, y: t.y), anchor: .bottomLeading)
            }

            // 5. Draw Pins
            for p in activePageAnnotations.pins {
                let r: CGFloat = 14.0 * max(0.5, p.scale)
                let pinRect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: pinRect), with: .color(BlueprintPdfEngine.parseHexColor(p.color)))
                context.stroke(Path(ellipseIn: pinRect), with: .color(.white), lineWidth: 2)
                let emoji = PinCatalog.resolveEmoji(p.baseType)
                context.draw(Text(emoji).font(.system(size: 13 * max(0.5, p.scale))), at: CGPoint(x: p.x, y: p.y))
            }

            // 6. Smart Level Alignment Guide Line
            if let guide = smartAlignmentGuide {
                let guideColor = Color(red: 0.23, green: 0.51, blue: 0.96)
                var linePath = Path()
                if guide.isHorizontalLevel {
                    let yLine = max(guide.refBottomY, guide.targetBottomY) + 10
                    linePath.move(to: CGPoint(x: min(guide.refCx, guide.targetCx) - 20, y: yLine))
                    linePath.addLine(to: CGPoint(x: max(guide.refCx, guide.targetCx) + 20, y: yLine))
                } else {
                    let xLine = max(guide.refRightX, guide.targetRightX) + 10
                    linePath.move(to: CGPoint(x: xLine, y: min(guide.refCy, guide.targetCy) - 20))
                    linePath.addLine(to: CGPoint(x: xLine, y: max(guide.refCy, guide.targetCy) + 20))
                }
                context.stroke(linePath, with: .color(guideColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }

            // 7. Selection Bounding Box & Manipulation Mode Handles (Move / Resize / Rotate)
            if let sel = selectedElement, let geom = getElementGeometry(sel) {
                let pad: CGFloat = 8
                let box = CGRect(
                    x: geom.cx - geom.halfW - pad,
                    y: geom.cy - geom.halfH - pad,
                    width: (geom.halfW + pad) * 2,
                    height: (geom.halfH + pad) * 2
                )
                let modeColor: Color = {
                    switch selectionManipMode {
                    case .move: return Color(red: 0.0, green: 0.48, blue: 1.0)
                    case .resize: return Color(red: 0.96, green: 0.62, blue: 0.04)
                    case .rotate: return Color(red: 0.06, green: 0.73, blue: 0.51)
                    }
                }()
                context.stroke(Path(box), with: .color(modeColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

                if selectionManipMode == .resize {
                    let corners = [
                        CGPoint(x: box.minX, y: box.minY),
                        CGPoint(x: box.maxX, y: box.minY),
                        CGPoint(x: box.minX, y: box.maxY),
                        CGPoint(x: box.maxX, y: box.maxY)
                    ]
                    for c in corners {
                        let hr = CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)
                        context.fill(Path(ellipseIn: hr), with: .color(modeColor))
                        context.stroke(Path(ellipseIn: hr), with: .color(.white), lineWidth: 2)
                    }
                } else if selectionManipMode == .rotate {
                    let stemTop = CGPoint(x: geom.cx, y: box.minY - 26)
                    var stem = Path()
                    stem.move(to: CGPoint(x: geom.cx, y: box.minY))
                    stem.addLine(to: stemTop)
                    context.stroke(stem, with: .color(modeColor), lineWidth: 2)
                    let hr = CGRect(x: stemTop.x - 9, y: stemTop.y - 9, width: 18, height: 18)
                    context.fill(Path(ellipseIn: hr), with: .color(modeColor))
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    let startCanvas = toCanvas(val.startLocation)
                    let currCanvas = toCanvas(val.location)
                    let screenDist = hypot(val.location.x - val.startLocation.x, val.location.y - val.startLocation.y)

                    if dragStartCanvasPt == nil {
                        dragStartCanvasPt = startCanvas
                        hasPassedSlop = false

                        if let hit = findElementAt(startCanvas) {
                            if selectedElement == hit {
                                tappedAlreadySelected = true
                            } else {
                                tappedAlreadySelected = false
                                selectedElement = hit
                                selectionManipMode = .move
                            }
                            captureInitialSelectedSnapshot()
                        } else {
                            tappedAlreadySelected = false
                            if activeTool == .select {
                                selectedElement = nil
                            } else if activeTool == .pen {
                                activePenPoints = [Point2D(x: startCanvas.x, y: startCanvas.y)]
                            }
                        }
                    }

                    dragCurrentCanvasPt = currCanvas
                    if screenDist > 12 {
                        if !hasPassedSlop && selectedElement != nil {
                            pushUndoSnapshot()
                        }
                        hasPassedSlop = true
                    }

                    if let sel = selectedElement {
                        if hasPassedSlop {
                            applyManipulationDrag(sel: sel, startPt: startCanvas, currPt: currCanvas)
                        }
                    } else if activeTool == .pan || activeTool == .select {
                        panOffset = CGSize(
                            width: lastPanOffset.width + val.translation.width,
                            height: lastPanOffset.height + val.translation.height
                        )
                    } else if activeTool == .pen {
                        activePenPoints.append(Point2D(x: currCanvas.x, y: currCanvas.y))
                    } else if activeTool == .eraser {
                        eraseElementAt(currCanvas)
                    }
                }
                .onEnded { val in
                    let startCanvas = dragStartCanvasPt ?? toCanvas(val.startLocation)
                    let endCanvas = toCanvas(val.location)

                    if let _ = selectedElement {
                        if !hasPassedSlop {
                            if tappedAlreadySelected {
                                selectionManipMode = selectionManipMode.next()
                            }
                        }
                        smartAlignmentGuide = nil
                    } else if activeTool == .pan || activeTool == .select {
                        lastPanOffset = panOffset
                    } else if activeTool == .pin {
                        pushUndoSnapshot()
                        var page = activePageAnnotations
                        let nextNum = page.pins.count + 1
                        page.pins.append(
                            PinAnnotation(
                                x: endCanvas.x,
                                y: endCanvas.y,
                                type: "\(selectedPinBaseType) \(nextNum)",
                                baseType: selectedPinBaseType,
                                color: drawColorHex,
                                userId: viewModel.currentUser?.id
                            )
                        )
                        allPagesAnnotations[currentPage] = page
                        selectedElement = SelectedElementRef(type: "pin", index: page.pins.count - 1)
                        selectionManipMode = .move
                    } else if activeTool == .text {
                        pendingTextPt = endCanvas
                        textPromptInput = ""
                        showTextPrompt = true
                    } else if activeTool == .pen && activePenPoints.count > 1 {
                        pushUndoSnapshot()
                        var page = activePageAnnotations
                        page.shapes.append(
                            ShapeAnnotation(
                                type: "pen",
                                points: activePenPoints,
                                color: drawColorHex,
                                lineWidth: lineWidthPx,
                                userId: viewModel.currentUser?.id
                            )
                        )
                        allPagesAnnotations[currentPage] = page
                    } else if [.line, .arrow, .ruler, .rect, .circle, .triangle].contains(activeTool) && hasPassedSlop {
                        if isCalibratingScale && activeTool == .ruler {
                            pendingScalePxDist = hypot(endCanvas.x - startCanvas.x, endCanvas.y - startCanvas.y)
                            showScalePrompt = true
                        } else {
                            pushUndoSnapshot()
                            var page = activePageAnnotations
                            page.shapes.append(
                                ShapeAnnotation(
                                    type: activeTool.rawValue,
                                    x: startCanvas.x,
                                    y: startCanvas.y,
                                    x2: endCanvas.x,
                                    y2: endCanvas.y,
                                    color: drawColorHex,
                                    fill: fillShape,
                                    lineWidth: lineWidthPx,
                                    userId: viewModel.currentUser?.id
                                )
                            )
                            allPagesAnnotations[currentPage] = page
                            selectedElement = SelectedElementRef(type: "shape", index: page.shapes.count - 1)
                            selectionManipMode = .move
                        }
                    }

                    dragStartCanvasPt = nil
                    dragCurrentCanvasPt = nil
                    activePenPoints = []
                    hasPassedSlop = false
                    tappedAlreadySelected = false
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { val in
                    zoomScale = max(0.5, min(6.0, lastZoomScale * val))
                }
                .onEnded { _ in
                    lastZoomScale = zoomScale
                }
        )
    }

    private func drawShape(_ sh: ShapeAnnotation, in context: inout GraphicsContext) {
        let color = BlueprintPdfEngine.parseHexColor(sh.color)
        let lw = max(1.5, sh.lineWidth)
        let cx = (sh.x + sh.x2) / 2.0
        let cy = (sh.y + sh.y2) / 2.0

        context.drawLayer { layer in
            if abs(sh.rotation) > 0.01 && sh.type != "pen" {
                layer.translateBy(x: cx, y: cy)
                layer.rotate(by: .degrees(Double(sh.rotation)))
                layer.translateBy(x: -cx, y: -cy)
            }

            switch sh.type {
            case "pen":
                if let pts = sh.points, pts.count > 1 {
                    var p = Path()
                    p.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
                    for pt in pts.dropFirst() {
                        p.addLine(to: CGPoint(x: pt.x, y: pt.y))
                    }
                    layer.stroke(p, with: .color(color), lineWidth: lw)
                }
            case "line", "ruler", "arrow":
                var p = Path()
                p.move(to: CGPoint(x: sh.x, y: sh.y))
                p.addLine(to: CGPoint(x: sh.x2, y: sh.y2))
                layer.stroke(p, with: .color(color), lineWidth: lw)

                if sh.type == "arrow" {
                    let angle = atan2(sh.y2 - sh.y, sh.x2 - sh.x)
                    let headLen = max(12.0, lw * 3.8)
                    var head = Path()
                    head.move(to: CGPoint(x: sh.x2, y: sh.y2))
                    head.addLine(to: CGPoint(x: sh.x2 - headLen * cos(angle - .pi / 6), y: sh.y2 - headLen * sin(angle - .pi / 6)))
                    head.move(to: CGPoint(x: sh.x2, y: sh.y2))
                    head.addLine(to: CGPoint(x: sh.x2 - headLen * cos(angle + .pi / 6), y: sh.y2 - headLen * sin(angle + .pi / 6)))
                    layer.stroke(head, with: .color(color), lineWidth: lw)
                }
            case "rect":
                let rect = CGRect(x: min(sh.x, sh.x2), y: min(sh.y, sh.y2), width: abs(sh.x2 - sh.x), height: abs(sh.y2 - sh.y))
                if sh.fill {
                    layer.fill(Path(rect), with: .color(color.opacity(0.32)))
                }
                layer.stroke(Path(rect), with: .color(color), lineWidth: lw)
            case "circle":
                let rect = CGRect(x: min(sh.x, sh.x2), y: min(sh.y, sh.y2), width: abs(sh.x2 - sh.x), height: abs(sh.y2 - sh.y))
                if sh.fill {
                    layer.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.32)))
                }
                layer.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: lw)
            case "triangle":
                let left = min(sh.x, sh.x2)
                let right = max(sh.x, sh.x2)
                let top = min(sh.y, sh.y2)
                let bottom = max(sh.y, sh.y2)
                let midX = (left + right) / 2.0
                var p = Path()
                p.move(to: CGPoint(x: midX, y: top))
                p.addLine(to: CGPoint(x: left, y: bottom))
                p.addLine(to: CGPoint(x: right, y: bottom))
                p.closeSubpath()
                if sh.fill {
                    layer.fill(p, with: .color(color.opacity(0.32)))
                }
                layer.stroke(p, with: .color(color), lineWidth: lw)
            default:
                break
            }
        }
    }

    // MARK: - Manipulation, Proportional Resize, Smart Level & Smart Clone

    private func captureInitialSelectedSnapshot() {
        guard let sel = selectedElement else { return }
        switch sel.type {
        case "shape":
            initialShapeSnapshot = activePageAnnotations.shapes[safe: sel.index]
        case "pin":
            initialPinSnapshot = activePageAnnotations.pins[safe: sel.index]
        case "text":
            initialTextSnapshot = activePageAnnotations.texts[safe: sel.index]
        default:
            break
        }
    }

    private func applyManipulationDrag(sel: SelectedElementRef, startPt: CGPoint, currPt: CGPoint) {
        var page = activePageAnnotations
        let dx = currPt.x - startPt.x
        let dy = currPt.y - startPt.y

        switch selectionManipMode {
        case .move:
            if sel.type == "shape", let initSh = initialShapeSnapshot, page.shapes.indices.contains(sel.index) {
                var moved = initSh
                moved.x += dx
                moved.y += dy
                moved.x2 += dx
                moved.y2 += dy
                let cx = (moved.x + moved.x2) / 2.0
                let cy = (moved.y + moved.y2) / 2.0
                let snap = computeSmartSnap(typeKey: "shape:\(moved.type)", excludeRef: sel, rawCx: cx, rawCy: cy, halfW: abs(moved.x2 - moved.x) / 2, halfH: abs(moved.y2 - moved.y) / 2)
                let snapDx = snap.cx - cx
                let snapDy = snap.cy - cy
                moved.x += snapDx
                moved.x2 += snapDx
                moved.y += snapDy
                moved.y2 += snapDy
                smartAlignmentGuide = snap.guide
                page.shapes[sel.index] = moved
            } else if sel.type == "pin", let initPin = initialPinSnapshot, page.pins.indices.contains(sel.index) {
                var moved = initPin
                moved.x += dx
                moved.y += dy
                page.pins[sel.index] = moved
            } else if sel.type == "text", let initTxt = initialTextSnapshot, page.texts.indices.contains(sel.index) {
                var moved = initTxt
                moved.x += dx
                moved.y += dy
                page.texts[sel.index] = moved
            }

        case .resize:
            // Proportional resizing: keep exact aspect ratio for triangles, circles, rectangles, etc.
            if sel.type == "shape", let initSh = initialShapeSnapshot, page.shapes.indices.contains(sel.index) {
                let cx = (initSh.x + initSh.x2) / 2.0
                let cy = (initSh.y + initSh.y2) / 2.0
                let initDist = max(10.0, hypot(startPt.x - cx, startPt.y - cy))
                let currDist = max(10.0, hypot(currPt.x - cx, currPt.y - cy))
                let uniformScale = max(0.2, min(6.0, currDist / initDist))
                let halfW = (initSh.x2 - initSh.x) / 2.0 * uniformScale
                let halfH = (initSh.y2 - initSh.y) / 2.0 * uniformScale
                var resized = initSh
                resized.x = cx - halfW
                resized.x2 = cx + halfW
                resized.y = cy - halfH
                resized.y2 = cy + halfH
                page.shapes[sel.index] = resized
            } else if sel.type == "pin", let initPin = initialPinSnapshot, page.pins.indices.contains(sel.index) {
                let initDist = max(12.0, hypot(startPt.x - initPin.x, startPt.y - initPin.y))
                let currDist = max(12.0, hypot(currPt.x - initPin.x, currPt.y - initPin.y))
                var resized = initPin
                resized.scale = max(0.5, min(3.5, initPin.scale * (currDist / initDist)))
                page.pins[sel.index] = resized
            }

        case .rotate:
            if sel.type == "shape", let initSh = initialShapeSnapshot, page.shapes.indices.contains(sel.index) {
                let cx = (initSh.x + initSh.x2) / 2.0
                let cy = (initSh.y + initSh.y2) / 2.0
                let a0 = atan2(startPt.y - cy, startPt.x - cx) * 180.0 / .pi
                let a1 = atan2(currPt.y - cy, currPt.x - cx) * 180.0 / .pi
                var rawDeg = (initSh.rotation + (a1 - a0)).truncatingRemainder(dividingBy: 360.0)
                if rawDeg < 0 { rawDeg += 360.0 }
                // Soft magnetic snap at 45° increments (±4°)
                for snapAngle in stride(from: 0.0, through: 360.0, by: 45.0) {
                    if abs(rawDeg - CGFloat(snapAngle)) <= 4.0 {
                        rawDeg = CGFloat(Int(snapAngle) % 360)
                        break
                    }
                }
                var rotated = initSh
                rotated.rotation = rawDeg
                page.shapes[sel.index] = rotated
            }
        }

        allPagesAnnotations[currentPage] = page
    }

    private func computeSmartSnap(
        typeKey: String,
        excludeRef: SelectedElementRef?,
        rawCx: CGFloat,
        rawCy: CGFloat,
        halfW: CGFloat,
        halfH: CGFloat
    ) -> (cx: CGFloat, cy: CGFloat, guide: SmartAlignmentGuide?) {
        let shapeSub = typeKey.replacingOccurrences(of: "shape:", with: "")
        for (idx, sh) in activePageAnnotations.shapes.enumerated().reversed() {
            if excludeRef?.type == "shape" && excludeRef?.index == idx { continue }
            guard sh.type == shapeSub else { continue }
            let rCx = (sh.x + sh.x2) / 2.0
            let rCy = (sh.y + sh.y2) / 2.0
            let rHalfW = max(12, abs(sh.x2 - sh.x) / 2.0)
            let rHalfH = max(12, abs(sh.y2 - sh.y) / 2.0)

            if abs(rawCy - rCy) <= 18.0 {
                let snappedCy = rCy
                let guide = SmartAlignmentGuide(
                    isHorizontalLevel: true,
                    refCx: rCx,
                    refCy: rCy,
                    refBottomY: rCy + rHalfH,
                    refRightX: rCx + rHalfW,
                    targetCx: rawCx,
                    targetCy: snappedCy,
                    targetBottomY: snappedCy + halfH,
                    targetRightX: rawCx + halfW,
                    distancePx: abs(rawCx - rCx)
                )
                return (rawCx, snappedCy, guide)
            } else if abs(rawCx - rCx) <= 18.0 {
                let snappedCx = rCx
                let guide = SmartAlignmentGuide(
                    isHorizontalLevel: false,
                    refCx: rCx,
                    refCy: rCy,
                    refBottomY: rCy + rHalfH,
                    refRightX: rCx + rHalfW,
                    targetCx: snappedCx,
                    targetCy: rawCy,
                    targetBottomY: rawCy + halfH,
                    targetRightX: snappedCx + halfW,
                    distancePx: abs(rawCy - rCy)
                )
                return (snappedCx, rawCy, guide)
            }
        }
        return (rawCx, rawCy, nil)
    }

    private func cloneSelectedElement() {
        guard let sel = selectedElement else { return }
        pushUndoSnapshot()
        var page = activePageAnnotations

        if sel.type == "shape", page.shapes.indices.contains(sel.index) {
            let orig = page.shapes[sel.index]
            let w = abs(orig.x2 - orig.x)
            let origCx = (orig.x + orig.x2) / 2.0
            let origCy = (orig.y + orig.y2) / 2.0

            // Measure step vector from previous same-type shape if available
            var stepDx = max(44.0, w + 24.0)
            var stepDy: CGFloat = 0.0
            if sel.index > 0 {
                for i in stride(from: sel.index - 1, through: 0, by: -1) {
                    let prev = page.shapes[i]
                    if prev.type == orig.type {
                        let pCx = (prev.x + prev.x2) / 2.0
                        let pCy = (prev.y + prev.y2) / 2.0
                        let d = hypot(origCx - pCx, origCy - pCy)
                        if d > 8.0 {
                            stepDx = origCx - pCx
                            stepDy = origCy - pCy
                            if abs(stepDy) <= 18.0 { stepDy = 0 }
                            if abs(stepDx) <= 18.0 { stepDx = 0 }
                        }
                        break
                    }
                }
            }

            var cloned = orig
            cloned.x += stepDx
            cloned.x2 += stepDx
            cloned.y += stepDy
            cloned.y2 += stepDy
            page.shapes.append(cloned)
            allPagesAnnotations[currentPage] = page
            selectedElement = SelectedElementRef(type: "shape", index: page.shapes.count - 1)
            selectionManipMode = .move
        } else if sel.type == "pin", page.pins.indices.contains(sel.index) {
            var cloned = page.pins[sel.index]
            cloned.x += 48
            page.pins.append(cloned)
            allPagesAnnotations[currentPage] = page
            selectedElement = SelectedElementRef(type: "pin", index: page.pins.count - 1)
        } else if sel.type == "text", page.texts.indices.contains(sel.index) {
            var cloned = page.texts[sel.index]
            cloned.x += 60
            page.texts.append(cloned)
            allPagesAnnotations[currentPage] = page
            selectedElement = SelectedElementRef(type: "text", index: page.texts.count - 1)
        }
    }

    private func deleteSelectedElement() {
        guard let sel = selectedElement else { return }
        pushUndoSnapshot()
        var page = activePageAnnotations
        switch sel.type {
        case "shape":
            if page.shapes.indices.contains(sel.index) { page.shapes.remove(at: sel.index) }
        case "pin":
            if page.pins.indices.contains(sel.index) { page.pins.remove(at: sel.index) }
        case "text":
            if page.texts.indices.contains(sel.index) { page.texts.remove(at: sel.index) }
        default:
            break
        }
        allPagesAnnotations[currentPage] = page
        selectedElement = nil
        smartAlignmentGuide = nil
    }

    private func applyColorSelection(_ hex: String) {
        drawColorHex = hex
        guard let sel = selectedElement else { return }
        pushUndoSnapshot()
        var page = activePageAnnotations
        switch sel.type {
        case "shape":
            if page.shapes.indices.contains(sel.index) { page.shapes[sel.index].color = hex }
        case "pin":
            if page.pins.indices.contains(sel.index) { page.pins[sel.index].color = hex }
        case "text":
            if page.texts.indices.contains(sel.index) {
                page.texts[sel.index].color = hex
                page.texts[sel.index].borderColor = hex
            }
        default:
            break
        }
        allPagesAnnotations[currentPage] = page
    }

    private func applyFillToggle(_ newFill: Bool) {
        fillShape = newFill
        guard let sel = selectedElement else { return }
        pushUndoSnapshot()
        var page = activePageAnnotations
        if sel.type == "shape", page.shapes.indices.contains(sel.index) {
            page.shapes[sel.index].fill = newFill
        } else if sel.type == "text", page.texts.indices.contains(sel.index) {
            page.texts[sel.index].bgColor = newFill ? "#ffffff" : "transparent"
        }
        allPagesAnnotations[currentPage] = page
    }

    private func applyLineWidth(_ width: CGFloat) {
        lineWidthPx = width
        guard let sel = selectedElement, sel.type == "shape" else { return }
        pushUndoSnapshot()
        var page = activePageAnnotations
        if page.shapes.indices.contains(sel.index) {
            page.shapes[sel.index].lineWidth = width
        }
        allPagesAnnotations[currentPage] = page
    }

    // MARK: - Hit Testing & Helpers

    private func getElementGeometry(_ ref: SelectedElementRef) -> ElementGeometry? {
        switch ref.type {
        case "shape":
            guard let sh = activePageAnnotations.shapes[safe: ref.index] else { return nil }
            let cx = (sh.x + sh.x2) / 2.0
            let cy = (sh.y + sh.y2) / 2.0
            return ElementGeometry(cx: cx, cy: cy, halfW: max(14, abs(sh.x2 - sh.x) / 2.0), halfH: max(14, abs(sh.y2 - sh.y) / 2.0))
        case "pin":
            guard let p = activePageAnnotations.pins[safe: ref.index] else { return nil }
            let r = 16.0 * max(0.5, p.scale)
            return ElementGeometry(cx: p.x, cy: p.y, halfW: r, halfH: r)
        case "text":
            guard let t = activePageAnnotations.texts[safe: ref.index] else { return nil }
            return ElementGeometry(cx: t.x + 30, cy: t.y - 10, halfW: 36, halfH: 14)
        default:
            return nil
        }
    }

    private func findElementAt(_ pt: CGPoint) -> SelectedElementRef? {
        for (i, p) in activePageAnnotations.pins.enumerated().reversed() {
            if hypot(pt.x - p.x, pt.y - p.y) <= 24 * max(0.6, p.scale) {
                return SelectedElementRef(type: "pin", index: i)
            }
        }
        for (i, t) in activePageAnnotations.texts.enumerated().reversed() {
            if abs(pt.x - (t.x + 30)) <= 45 && abs(pt.y - (t.y - 10)) <= 24 {
                return SelectedElementRef(type: "text", index: i)
            }
        }
        for (i, sh) in activePageAnnotations.shapes.enumerated().reversed() {
            let minX = min(sh.x, sh.x2) - 16
            let maxX = max(sh.x, sh.x2) + 16
            let minY = min(sh.y, sh.y2) - 16
            let maxY = max(sh.y, sh.y2) + 16
            if pt.x >= minX && pt.x <= maxX && pt.y >= minY && pt.y <= maxY {
                return SelectedElementRef(type: "shape", index: i)
            }
        }
        return nil
    }

    private func eraseElementAt(_ pt: CGPoint) {
        if let hit = findElementAt(pt) {
            selectedElement = hit
            deleteSelectedElement()
        }
    }

    private func pushUndoSnapshot() {
        undoStack.append(activePageAnnotations)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func performUndo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(activePageAnnotations)
        allPagesAnnotations[currentPage] = prev
        selectedElement = nil
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(activePageAnnotations)
        allPagesAnnotations[currentPage] = next
        selectedElement = nil
    }

    private func loadDrawingData() {
        allPagesAnnotations = AnnotationsEnvelope.parse(drawing.annotationsData)
        scaleRatio = drawing.scaleRatio
        if let path = drawing.localFilePath {
            let url = URL(fileURLWithPath: path)
            totalPages = BlueprintPdfEngine.getPageCount(fileURL: url)
            renderCurrentPage()
        }
    }

    private func renderCurrentPage() {
        guard let path = drawing.localFilePath else { return }
        let url = URL(fileURLWithPath: path)
        pageUIImage = BlueprintPdfEngine.renderPageImage(fileURL: url, pageNumber1Based: currentPage)
    }

    private func exportPdf() {
        guard let path = drawing.localFilePath else { return }
        let url = URL(fileURLWithPath: path)
        if let out = try? BlueprintPdfEngine.exportAnnotatedPdf(
            sourceFileURL: url,
            drawingName: drawing.name,
            allPagesAnnotations: allPagesAnnotations,
            scaleRatio: scaleRatio
        ) {
            exportedPdfURL = out
            showShareSheet = true
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
