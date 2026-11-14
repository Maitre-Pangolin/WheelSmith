import Foundation

/// What the outer ring of a slice shows: the app's open windows (only when it has more than one),
/// followed by the slice's configured sub-actions.
public enum RingLayout {
    /// Total sectors that fit comfortably around the wheel (8 × 29° = 229°).
    public static let maxEntries = 8
    /// Windows never take the whole ring, so at least a couple of sub-actions stay reachable.
    public static let maxWindows = 6

    /// How many windows and sub-actions to show.
    /// - Windows appear only when there are 2 or more (one window has nothing to choose between).
    public static func counts(windows: Int, actions: Int) -> (windows: Int, actions: Int) {
        let shownWindows = windows >= 2 ? min(windows, maxWindows) : 0
        let shownActions = min(actions, maxEntries - shownWindows)
        return (shownWindows, shownActions)
    }
}
