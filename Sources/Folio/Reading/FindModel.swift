import SwiftUI

/// Shared find-in-page state so Reading and Writing modes use one identical finder.
///
/// The bar drives `query`, `caseSensitive`, and navigation; whichever mode is on
/// screen computes the matches, publishes `total`, and reacts to `current` (the
/// focused match) by scrolling/selecting. The reading view stays *mounted* while
/// the editor is up (perf), so ownership is by visibility, not mounting: its
/// find handlers stand down (`guard ui.mode == .read`) whenever it's hidden.
final class FindModel: ObservableObject {
    @Published var active = false
    @Published var query = "" { didSet { if query != oldValue { current = 0 } } }
    @Published var caseSensitive = false
    @Published var current = 0        // 0-based index of the focused match
    @Published var total = 0          // total matches; set by the active mode
    /// Bumped to ask the bar's text field to (re)take focus — e.g. on ⌘F.
    @Published var focusRequest = 0

    var options: String.CompareOptions { caseSensitive ? [] : .caseInsensitive }

    func open() {
        active = true
        focusRequest &+= 1
    }

    func close() {
        active = false
        query = ""
        total = 0
        current = 0
    }

    func next() { if total > 0 { current = (current + 1) % total } }
    func prev() { if total > 0 { current = (current - 1 + total) % total } }
}
