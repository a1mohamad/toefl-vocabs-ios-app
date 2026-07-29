import SwiftUI
import UIKit

/// Keeps UIKit's idea of the writing direction in step with the app's language
/// setting.
///
/// `\.layoutDirection` in the SwiftUI environment only describes the SwiftUI
/// tree. The UIKit layer underneath — the window, and the scroll views that back
/// `ScrollView`, `List` and `Form` — carries its own `semanticContentAttribute`,
/// and UIKit mirrors a right-to-left scroll view by transforming it rather than
/// by laying it out differently.
///
/// Overriding only the environment left the two layers disagreeing after a
/// round trip through Persian: the window stayed right-to-left while the SwiftUI
/// content had gone back to left-to-right, and a mirrored container holding
/// unmirrored content is what put the English text on screen backwards.
///
/// Writing the attribute onto the windows on every change is what makes the two
/// layers agree again.
enum LayoutDirectionBridge {

    static func attribute(for direction: LayoutDirection) -> UISemanticContentAttribute {
        direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
    }

    @MainActor
    static func apply(_ direction: LayoutDirection) {
        let attribute = attribute(for: direction)

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.semanticContentAttribute != attribute {
                window.semanticContentAttribute = attribute
                // The attribute alone marks the hierarchy dirty; this is what
                // makes already-visible views redraw in the new direction
                // instead of waiting for the next unrelated layout pass.
                window.subviews.forEach { $0.setNeedsLayout() }
            }
        }
    }
}
