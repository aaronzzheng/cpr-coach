// Lock-screen and Dynamic Island view of a running CPR session: the instruction, rate, depth and
// time, readable at a glance with the phone propped on the floor.
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CPRWidgets: WidgetBundle {
    var body: some Widget { CPRLiveActivity() }
}

private func toneColor(_ tone: String) -> Color {
    switch tone {
    case "good": Color(red: 0.19, green: 0.82, blue: 0.35)
    case "urgent": Color(red: 1, green: 0.27, blue: 0.23)
    case "swap": Color(red: 0.75, green: 0.35, blue: 0.95)
    default: Color(red: 1, green: 0.62, blue: 0.04)
    }
}

private let accent = Color(red: 1, green: 0.22, blue: 0.37)

struct CPRLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CPRActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(s.rate.map(String.init) ?? "—").font(.system(size: 34, weight: .bold)).monospacedDigit()
                        Text(s.rateUnit).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(s.depth.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: 34, weight: .bold)).monospacedDigit()
                        Text("cm").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(s.instruction).font(.headline).foregroundStyle(toneColor(s.tone)).lineLimit(1)
                        Spacer()
                        Text(context.attributes.startedAt, style: .timer).font(.headline).monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill").foregroundStyle(accent)
                    Text(s.rate.map(String.init) ?? "—").monospacedDigit().foregroundStyle(toneColor(s.tone))
                }
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer).monospacedDigit().frame(width: 44)
            } minimal: {
                Text(s.rate.map(String.init) ?? "♥").monospacedDigit().foregroundStyle(toneColor(s.tone))
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: CPRActivityAttributes
    let state: CPRActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: attributes.emergency ? "staroflife.fill" : "heart.fill").foregroundStyle(accent)
                    Text(attributes.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    Text(attributes.startedAt, style: .timer).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(state.instruction)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(toneColor(state.tone))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            metric(state.rate.map(String.init), state.rateUnit)
            metric(state.depth.map { String(format: "%.1f", $0) }, "cm")
        }
        .padding(16)
        .foregroundStyle(.white)
    }

    private func metric(_ value: String?, _ unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value ?? "—").font(.system(size: 30, weight: .bold)).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }
}
