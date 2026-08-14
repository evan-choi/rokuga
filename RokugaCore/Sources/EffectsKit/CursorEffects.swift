import Foundation
import SettingsKit

/// Cursor compositing options snapshotted at recording start.
/// The Metal compositor (task 6.1) renders these into recorded frames only — nothing is drawn on the live screen.
public struct CursorEffectOptions: Equatable, Sendable {
    public var showCursor: Bool
    public var pointerStyle: PointerStyle
    public var highlight: Bool
    public var animateClicks: Bool

    public init(showCursor: Bool, pointerStyle: PointerStyle, highlight: Bool, animateClicks: Bool) {
        self.showCursor = showCursor
        self.pointerStyle = pointerStyle
        self.highlight = highlight
        self.animateClicks = animateClicks
    }

    public static func fromSettings(_ settings: SettingsStore) -> Self {
        .init(
            showCursor: settings.showCursor,
            pointerStyle: settings.pointerStyle,
            highlight: settings.highlightCursor,
            animateClicks: settings.animateClicks
        )
    }

    /// True when frames can bypass the compositor entirely (zero-cost path).
    public var isPassthrough: Bool {
        showCursor && pointerStyle == .system && !highlight && !animateClicks
    }
}
