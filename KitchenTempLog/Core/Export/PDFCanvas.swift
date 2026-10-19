import UIKit

/// A cursor-based PDF writer for plain, printable reports on US Letter. Handles page breaks,
/// wrapped table cells and a running footer, so report code only says what goes on the page.
final class PDFCanvas {
    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    static let margin: CGFloat = 48
    static var contentWidth: CGFloat { page.width - margin * 2 }

    private let context: UIGraphicsPDFRendererContext
    private let footer: String
    private(set) var y: CGFloat = 0
    private(set) var pageNumber = 0

    private let titleFont = UIFont.boldSystemFont(ofSize: 20)
    private let headingFont = UIFont.boldSystemFont(ofSize: 13)
    private let bodyFont = UIFont.systemFont(ofSize: 10.5)
    private let smallFont = UIFont.systemFont(ofSize: 9)
    private let cellFont = UIFont.systemFont(ofSize: 9.5)
    private let cellBoldFont = UIFont.boldSystemFont(ofSize: 9.5)

    private init(context: UIGraphicsPDFRendererContext, footer: String) {
        self.context = context
        self.footer = footer
    }

    static func render(footer: String, _ body: (PDFCanvas) throws -> Void) throws -> URL {
        let url = ExportFile.temporaryURL(suffix: "report", extension: "pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        var failure: Error?
        try renderer.writePDF(to: url) { context in
            let canvas = PDFCanvas(context: context, footer: footer)
            canvas.newPage()
            do { try body(canvas) } catch { failure = error }
        }
        if let failure { throw failure }
        return url
    }

    // MARK: Pages

    func newPage() {
        context.beginPage()
        pageNumber += 1
        y = Self.margin
        drawFooter()
    }

    private func drawFooter() {
        let attributes: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: UIColor.gray]
        let text = "\(footer)   ·   Page \(pageNumber)"
        let rect = CGRect(x: Self.margin, y: Self.page.height - Self.margin + 12, width: Self.contentWidth, height: 14)
        text.draw(in: rect, withAttributes: attributes)
    }

    private func ensure(_ height: CGFloat) {
        if y + height > Self.page.height - Self.margin { newPage() }
    }

    // MARK: Text

    func title(_ text: String) {
        ensure(30)
        text.draw(at: CGPoint(x: Self.margin, y: y), withAttributes: [.font: titleFont])
        y += 28
    }

    func subtitle(_ text: String) {
        ensure(16)
        text.draw(at: CGPoint(x: Self.margin, y: y), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.darkGray])
        y += 18
    }

    func heading(_ text: String) {
        ensure(34)
        y += 10
        text.draw(at: CGPoint(x: Self.margin, y: y), withAttributes: [.font: headingFont])
        y += 18
        rule()
    }

    func paragraph(_ text: String, color: UIColor = .black) {
        let attributes: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: color]
        let height = Self.height(of: text, width: Self.contentWidth, attributes: attributes)
        ensure(height + 6)
        text.draw(in: CGRect(x: Self.margin, y: y, width: Self.contentWidth, height: height), withAttributes: attributes)
        y += height + 6
    }

    func keyValues(_ pairs: [(String, String)]) {
        let keyWidth: CGFloat = 130
        for (key, value) in pairs {
            let valueAttributes: [NSAttributedString.Key: Any] = [.font: bodyFont]
            let height = max(14, Self.height(of: value, width: Self.contentWidth - keyWidth, attributes: valueAttributes))
            ensure(height + 4)
            key.draw(in: CGRect(x: Self.margin, y: y, width: keyWidth, height: height), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.darkGray])
            value.draw(in: CGRect(x: Self.margin + keyWidth, y: y, width: Self.contentWidth - keyWidth, height: height), withAttributes: valueAttributes)
            y += height + 4
        }
    }

    func spacer(_ height: CGFloat = 8) { y += height }

    private func rule() {
        context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
        context.cgContext.setLineWidth(0.5)
        context.cgContext.move(to: CGPoint(x: Self.margin, y: y))
        context.cgContext.addLine(to: CGPoint(x: Self.page.width - Self.margin, y: y))
        context.cgContext.strokePath()
        y += 6
    }

    // MARK: Table

    /// `widths` are fractions of the content width and should sum to 1.
    func table(headers: [String], widths: [CGFloat], rows: [[String]]) {
        let padding: CGFloat = 4
        let columnWidths = widths.map { $0 * Self.contentWidth }

        func drawRow(_ cells: [String], font: UIFont, background: UIColor?) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let height = zip(cells, columnWidths).map { cell, width in
                Self.height(of: cell, width: width - padding * 2, attributes: attributes)
            }.max() ?? 12
            let rowHeight = height + padding * 2
            ensure(rowHeight)
            if let background {
                context.cgContext.setFillColor(background.cgColor)
                context.cgContext.fill(CGRect(x: Self.margin, y: y, width: Self.contentWidth, height: rowHeight))
            }
            var x = Self.margin
            for (cell, width) in zip(cells, columnWidths) {
                cell.draw(in: CGRect(x: x + padding, y: y + padding, width: width - padding * 2, height: height), withAttributes: attributes)
                x += width
            }
            y += rowHeight
            context.cgContext.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
            context.cgContext.setLineWidth(0.4)
            context.cgContext.move(to: CGPoint(x: Self.margin, y: y))
            context.cgContext.addLine(to: CGPoint(x: Self.page.width - Self.margin, y: y))
            context.cgContext.strokePath()
        }

        if rows.isEmpty {
            paragraph("None recorded.", color: .darkGray)
            return
        }
        drawRow(headers, font: cellBoldFont, background: UIColor(white: 0.94, alpha: 1))
        for row in rows { drawRow(row, font: cellFont, background: nil) }
        y += 4
    }

    // MARK: Images

    func image(_ image: UIImage, caption: String, maxHeight: CGFloat = 160) {
        let scale = min(maxHeight / image.size.height, (Self.contentWidth / 2) / image.size.width, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ensure(size.height + 22)
        image.draw(in: CGRect(x: Self.margin, y: y, width: size.width, height: size.height))
        y += size.height + 2
        caption.draw(at: CGPoint(x: Self.margin, y: y), withAttributes: [.font: smallFont, .foregroundColor: UIColor.darkGray])
        y += 18
    }

    // MARK: Measuring

    static func height(of text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        guard !text.isEmpty else { return 12 }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes, context: nil
        )
        return ceil(bounds.height)
    }
}
