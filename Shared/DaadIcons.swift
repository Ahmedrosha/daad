import UIKit

/// Icons SF Symbols doesn't have, drawn as template images so they take the button's tint.
enum DaadIcons {
    /// A small calculator: a body with a screen on top and a 3×3 grid of buttons.
    static func calculator(size: CGFloat = 22) -> UIImage {
        let w = size * 0.78, h = size
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in
            UIColor.black.setStroke()
            UIColor.black.setFill()
            let line = max(1.3, size * 0.075)
            let body = UIBezierPath(roundedRect: CGRect(x: line / 2, y: line / 2, width: w - line, height: h - line),
                                    cornerRadius: size * 0.16)
            body.lineWidth = line
            body.stroke()
            let inset = size * 0.17
            let screen = CGRect(x: inset, y: inset, width: w - inset * 2, height: h * 0.22)
            UIBezierPath(roundedRect: screen, cornerRadius: size * 0.05).fill()
            let gridTop = screen.maxY + size * 0.1
            let gap = size * 0.07
            let cell = (w - inset * 2 - gap * 2) / 3
            let rowH = (h - inset - gridTop - gap * 2) / 3
            for r in 0..<3 {
                for c in 0..<3 {
                    let rect = CGRect(x: inset + CGFloat(c) * (cell + gap), y: gridTop + CGFloat(r) * (rowH + gap),
                                      width: cell, height: rowH)
                    UIBezierPath(roundedRect: rect, cornerRadius: min(cell, rowH) * 0.3).fill()
                }
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
