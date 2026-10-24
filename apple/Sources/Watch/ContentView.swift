// Single watch screen: Start/Stop, link status, sample counter, heart rate, metronome toggles.
import SwiftUI

struct ContentView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if model.running { model.stop() } else { Task { await model.start() } }
                } label: {
                    Text(model.running ? "Stop" : "Start")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                }
                .tint(model.running ? .red : .green)

                Text("Phone: \(model.phoneReachable ? "connected" : "not reachable")")
                    .foregroundStyle(model.phoneReachable ? .green : .orange)
                Text("Samples sent: \(model.samplesSent)")
                if model.batchesDropped > 0 {
                    Text("Dropped batches: \(model.batchesDropped)").foregroundStyle(.orange)
                }
                Text("HR: \(model.heartRate.map(String.init) ?? "—")")

                Toggle("Metronome", isOn: $model.metronomeOn)
                Toggle("Haptic every 2 beats", isOn: $model.everyOtherBeat)

                if let error = model.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .font(.footnote)
        }
    }
}
