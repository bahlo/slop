import AppKit

/// Renders the menubar label (icon + time) into a single template image.
/// SwiftUI text in a MenuBarExtra label re-measures per update and jitters;
/// an image has exactly the width we draw, rounded to whole points, so the
/// item cannot resize between seconds.
enum LabelRenderer {
    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize, weight: .regular
    )
    private static let spacing: CGFloat = 5
    private static let height: CGFloat = 18

    static func render(icon: String, text: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,  // template: system recolors it
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let iconImage = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .regular))
        let iconSize = iconImage?.size ?? .zero

        let width = ceil(iconSize.width + spacing + textSize.width)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            iconImage?.draw(
                at: NSPoint(x: 0, y: (rect.height - iconSize.height) / 2),
                from: .zero, operation: .sourceOver, fraction: 1
            )
            (text as NSString).draw(
                at: NSPoint(x: iconSize.width + spacing, y: (rect.height - textSize.height) / 2),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}
