import Foundation
import UIKit
import PDFKit
import SwiftUI

enum BlueprintPdfEngine {
    static let pdfRenderScale: CGFloat = 2.0

    static func parseHexUIColor(_ hex: String) -> UIColor {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") { clean.removeFirst() }
        if clean.count == 3 {
            let r = String(repeating: clean[clean.startIndex], count: 2)
            let gIdx = clean.index(clean.startIndex, offsetBy: 1)
            let bIdx = clean.index(clean.startIndex, offsetBy: 2)
            let g = String(repeating: clean[gIdx], count: 2)
            let b = String(repeating: clean[bIdx], count: 2)
            clean = r + g + b
        }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else {
            return UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    static func parseHexColor(_ hex: String) -> Color {
        Color(uiColor: parseHexUIColor(hex))
    }

    static func getPageCount(fileURL: URL) -> Int {
        if fileURL.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: fileURL) {
            return max(1, doc.pageCount)
        }
        return 1
    }

    static func renderPageImage(fileURL: URL, pageNumber1Based: Int) -> UIImage? {
        if fileURL.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: fileURL),
                  let page = doc.page(at: max(0, min(pageNumber1Based - 1, doc.pageCount - 1))) else {
                return nil
            }
            let pageRect = page.bounds(for: .mediaBox)
            let width = max(1, pageRect.width * pdfRenderScale)
            let height = max(1, pageRect.height * pdfRenderScale)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
            return renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: height)
                ctx.cgContext.scaleBy(x: pdfRenderScale, y: -pdfRenderScale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
        } else {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return UIImage(data: data)
        }
    }

    /// Renders a composite UIImage (background blueprint + vector annotations) for server PNG preview or export.
    static func renderCompositeImage(
        baseImage: UIImage,
        annotations: PageAnnotations,
        scaleRatio: Double?
    ) -> UIImage {
        let size = baseImage.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            baseImage.draw(in: CGRect(origin: .zero, size: size))
            drawAnnotationsInCGContext(
                cg: ctx.cgContext,
                annotations: annotations,
                scaleRatio: scaleRatio
            )
        }
    }

    /// Exports a full multi-page annotated PDF file to a temporary URL for sharing/saving on iPhone.
    static func exportAnnotatedPdf(
        sourceFileURL: URL,
        drawingName: String,
        allPagesAnnotations: [Int: PageAnnotations],
        scaleRatio: Double?
    ) throws -> URL {
        let totalPages = getPageCount(fileURL: sourceFileURL)
        let safeName = drawingName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)_Annotated.pdf")

        let firstImg = renderPageImage(fileURL: sourceFileURL, pageNumber1Based: 1)
        let defaultBounds = CGRect(origin: .zero, size: firstImg?.size ?? CGSize(width: 1200, height: 900))

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: defaultBounds)
        try pdfRenderer.writePDF(to: outURL) { pdfCtx in
            for pageNum in 1...totalPages {
                guard let baseImg = renderPageImage(fileURL: sourceFileURL, pageNumber1Based: pageNum) else { continue }
                let pageBounds = CGRect(origin: .zero, size: baseImg.size)
                pdfCtx.beginPage(withBounds: pageBounds, pageInfo: [:])
                baseImg.draw(in: pageBounds)
                let pageAnn = allPagesAnnotations[pageNum] ?? PageAnnotations()
                drawAnnotationsInCGContext(
                    cg: pdfCtx.cgContext,
                    annotations: pageAnn,
                    scaleRatio: scaleRatio
                )
            }
        }
        return outURL
    }

    static func drawAnnotationsInCGContext(
        cg: CGContext,
        annotations: PageAnnotations,
        scaleRatio: Double?
    ) {
        // 1. Shapes
        for sh in annotations.shapes {
            let color = parseHexUIColor(sh.color)
            cg.saveGState()
            cg.setStrokeColor(color.cgColor)
            cg.setFillColor(color.withAlphaComponent(0.32).cgColor)
            cg.setLineWidth(max(1.5, sh.lineWidth))
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let cx = (sh.x + sh.x2) / 2.0
            let cy = (sh.y + sh.y2) / 2.0
            if abs(sh.rotation) > 0.01 && sh.type != "pen" {
                cg.translateBy(x: cx, y: cy)
                cg.rotate(by: sh.rotation * .pi / 180.0)
                cg.translateBy(x: -cx, y: -cy)
            }

            switch sh.type {
            case "pen":
                if let pts = sh.points, pts.count > 1 {
                    cg.beginPath()
                    cg.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
                    for pt in pts.dropFirst() {
                        cg.addLine(to: CGPoint(x: pt.x, y: pt.y))
                    }
                    cg.strokePath()
                }
            case "line", "ruler":
                cg.beginPath()
                cg.move(to: CGPoint(x: sh.x, y: sh.y))
                cg.addLine(to: CGPoint(x: sh.x2, y: sh.y2))
                cg.strokePath()

                if sh.type == "ruler" {
                    let pxDist = hypot(sh.x2 - sh.x, sh.y2 - sh.y)
                    let label: String
                    if let sr = scaleRatio, sr > 0 {
                        label = String(format: "%.2f m", Double(pxDist) / sr)
                    } else {
                        label = "\(Int(pxDist)) px"
                    }
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 13),
                        .foregroundColor: UIColor.white,
                        .backgroundColor: color
                    ]
                    (label as NSString).draw(at: CGPoint(x: cx - 22, y: cy - 10), withAttributes: attrs)
                }
            case "arrow":
                cg.beginPath()
                cg.move(to: CGPoint(x: sh.x, y: sh.y))
                cg.addLine(to: CGPoint(x: sh.x2, y: sh.y2))
                cg.strokePath()

                let angle = atan2(sh.y2 - sh.y, sh.x2 - sh.x)
                let headLen: CGFloat = max(12.0, sh.lineWidth * 3.8)
                let p1 = CGPoint(
                    x: sh.x2 - headLen * cos(angle - .pi / 6),
                    y: sh.y2 - headLen * sin(angle - .pi / 6)
                )
                let p2 = CGPoint(
                    x: sh.x2 - headLen * cos(angle + .pi / 6),
                    y: sh.y2 - headLen * sin(angle + .pi / 6)
                )
                cg.beginPath()
                cg.move(to: CGPoint(x: sh.x2, y: sh.y2))
                cg.addLine(to: p1)
                cg.move(to: CGPoint(x: sh.x2, y: sh.y2))
                cg.addLine(to: p2)
                cg.strokePath()
            case "rect":
                let rect = CGRect(
                    x: min(sh.x, sh.x2),
                    y: min(sh.y, sh.y2),
                    width: abs(sh.x2 - sh.x),
                    height: abs(sh.y2 - sh.y)
                )
                if sh.fill { cg.fill(rect) }
                cg.stroke(rect)
            case "circle":
                let rect = CGRect(
                    x: min(sh.x, sh.x2),
                    y: min(sh.y, sh.y2),
                    width: abs(sh.x2 - sh.x),
                    height: abs(sh.y2 - sh.y)
                )
                if sh.fill { cg.fillEllipse(in: rect) }
                cg.strokeEllipse(in: rect)
            case "triangle":
                let left = min(sh.x, sh.x2)
                let right = max(sh.x, sh.x2)
                let top = min(sh.y, sh.y2)
                let bottom = max(sh.y, sh.y2)
                let midX = (left + right) / 2.0
                let midY = (top + bottom) / 2.0

                let pts: [CGPoint]
                switch sh.orientation {
                case "90":
                    pts = [CGPoint(x: right, y: midY), CGPoint(x: left, y: top), CGPoint(x: left, y: bottom)]
                case "180":
                    pts = [CGPoint(x: midX, y: bottom), CGPoint(x: left, y: top), CGPoint(x: right, y: top)]
                case "270":
                    pts = [CGPoint(x: left, y: midY), CGPoint(x: right, y: top), CGPoint(x: right, y: bottom)]
                default:
                    pts = [CGPoint(x: midX, y: top), CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom)]
                }
                cg.beginPath()
                cg.move(to: pts[0])
                cg.addLine(to: pts[1])
                cg.addLine(to: pts[2])
                cg.closePath()
                if sh.fill {
                    cg.drawPath(using: .fillStroke)
                } else {
                    cg.strokePath()
                }
            default:
                break
            }
            cg.restoreGState()
        }

        // 2. Texts
        for t in annotations.texts {
            cg.saveGState()
            cg.translateBy(x: t.x, y: t.y)
            if t.rotation != 0 {
                cg.rotate(by: CGFloat(t.rotation) * .pi / 180.0)
            }
            let color = parseHexUIColor(t.color)
            let font = UIFont.boldSystemFont(ofSize: CGFloat(max(8, t.fontSize)))
            let displayStr = t.layout == "column" ? t.text.map { String($0) }.joined(separator: "\n") : t.text
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let size = (displayStr as NSString).size(withAttributes: attrs)
            let bgRect = CGRect(x: -4, y: -size.height, width: size.width + 8, height: size.height + 6)
            if let bg = t.bgColor, !bg.isEmpty, bg != "transparent" {
                cg.setFillColor(parseHexUIColor(bg).cgColor)
                cg.fill(bgRect)
            }
            if t.hasBorder {
                cg.setStrokeColor(parseHexUIColor(t.borderColor ?? t.color).cgColor)
                cg.setLineWidth(max(1.0, t.borderWidth))
                cg.stroke(bgRect)
            }
            (displayStr as NSString).draw(at: CGPoint(x: 0, y: -size.height + 2), withAttributes: attrs)
            cg.restoreGState()
        }

        // 3. Pins
        for p in annotations.pins {
            cg.saveGState()
            cg.translateBy(x: p.x, y: p.y)
            if abs(p.rotation) > 0.01 {
                cg.rotate(by: p.rotation * .pi / 180.0)
            }
            let r: CGFloat = 14.0 * max(0.5, p.scale)
            let pinColor = parseHexUIColor(p.color)
            cg.setFillColor(pinColor.cgColor)
            cg.fillEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(2.0)
            cg.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))

            let emoji = PinCatalog.resolveEmoji(p.baseType)
            let emojiAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13 * max(0.5, p.scale))
            ]
            let eSize = (emoji as NSString).size(withAttributes: emojiAttrs)
            (emoji as NSString).draw(at: CGPoint(x: -eSize.width / 2, y: -eSize.height / 2), withAttributes: emojiAttrs)

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10 * max(0.6, p.scale)),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.black.withAlphaComponent(0.75)
            ]
            let lSize = (p.type as NSString).size(withAttributes: labelAttrs)
            (p.type as NSString).draw(at: CGPoint(x: -lSize.width / 2, y: r + 3), withAttributes: labelAttrs)
            cg.restoreGState()
        }
    }
}
