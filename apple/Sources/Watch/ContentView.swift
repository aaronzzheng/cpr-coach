// Watch screen. Running: the coach's cue, rate and depth, big enough to read mid-compression.
// Idle: Start, link status and settings.
import SwiftUI

struct ContentView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if model.running {
                    if model.coachOnWatch {
                        Text(model.cue?.text ?? tr("Start compressions"))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(model.cue?.color ?? .white)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        HStack(alignment: .firstTextBaseline) {
                            metric(model.rate.map { "\(Int($0.rounded()))" }, tr("/min"))
                            Spacer()
                            metric(model.depth.map { trNumber($0, digits: 1) }, "cm")
                        }
                    }
                    if let hr = model.heartRate {
                        Label("\(hr)", systemImage: "heart.fill").foregroundStyle(.pink)
                    }
                }
                Button {
                    if model.running { model.stop() } else { Task { await model.start() } }
                } label: {
                    Text(model.running ? tr("Stop") : tr("Start"))
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                }
                .tint(model.running ? .red : .green)

                Text(model.phoneReachable ? tr("Phone connected") : tr("Phone not reachable"))
                    .foregroundStyle(model.phoneReachable ? .green : .orange)
                if model.batchesDropped > 0 {
                    Text("Dropped batches: \(model.batchesDropped)").foregroundStyle(.orange)
                }
                Toggle(tr("Coach on watch"), isOn: $model.coachOnWatch)
                Toggle(tr("Metronome"), isOn: $model.metronomeOn)
                Toggle(tr("Haptic every 2 beats"), isOn: $model.everyOtherBeat)
                Text("Samples sent: \(model.samplesSent)").foregroundStyle(.secondary)

                if let error = model.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .font(.footnote)
        }
    }

    private func metric(_ value: String?, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value ?? "—").font(.system(size: 30, weight: .semibold)).monospacedDigit()
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
