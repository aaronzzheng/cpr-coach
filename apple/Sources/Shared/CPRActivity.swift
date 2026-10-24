// Live Activity shared by the app (which starts and updates it) and the widget extension (which
// draws it on the lock screen and in the Dynamic Island). Strings arrive already translated.
import ActivityKit
import Foundation

struct CPRActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var rate: Int?
        var depth: Double?
        /// The coach's current instruction, in the app's language.
        var instruction: String
        /// "good", "warning", "urgent" or "swap" — colours the instruction.
        var tone: String
        var rateUnit: String
    }

    var startedAt: Date
    var emergency: Bool
    var title: String
}
