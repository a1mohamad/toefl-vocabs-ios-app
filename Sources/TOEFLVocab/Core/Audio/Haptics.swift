import UIKit

/// Thin wrapper over UIKit feedback generators.
///
/// `UIImpactFeedbackGenerator` rather than SwiftUI's `.sensoryFeedback`, which
/// needs iOS 17 and would push the deployment target past what a sideloaded
/// build should require.
@MainActor
enum Haptics {

    static func answer(correct: Bool, enabled: Bool) {
        guard enabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(correct ? .success : .warning)
    }

    static func tap(enabled: Bool) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    static func milestone(enabled: Bool) {
        guard enabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}
