// Relay screen: laptop address and connection, watch link status, traffic, watch controls.
import SwiftUI

struct ContentView: View {
    @Environment(RelayModel.self) private var model
    @AppStorage("laptopAddress") private var address = "ws://192.168.x.x:8000/ingest"

    var body: some View {
        NavigationStack {
            Form {
                Section("Laptop") {
                    TextField("Laptop IP, e.g. 192.168.1.20", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(model.wantConnected)
                    Button(model.wantConnected ? "Disconnect" : "Connect") {
                        if model.wantConnected { model.disconnect() } else { model.connect(address: address) }
                    }
                    LabeledContent("Socket", value: model.socketState.label)
                        .foregroundStyle(model.socketState == .connected ? .green : .secondary)
                    if let error = model.addressError ?? model.lastSocketError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("Watch") {
                    LabeledContent("Paired", value: yesNo(model.watchPaired))
                    LabeledContent("App installed", value: yesNo(model.watchInstalled))
                    LabeledContent("Reachable", value: yesNo(model.watchReachable))
                    LabeledContent("Heart rate", value: model.lastHeartRate.map { "\($0) bpm" } ?? "—")
                }

                Section("Traffic") {
                    LabeledContent("From watch", value: "\(model.inPerSecond) msg/s")
                    LabeledContent("To laptop", value: "\(model.outPerSecond) msg/s")
                    LabeledContent("Dropped", value: "\(model.droppedTotal)")
                }

                Section {
                    Button("Start watch") { model.command(.start) }
                    Button("Stop watch") { model.command(.stop) }
                    Button("Metronome on") { model.command(.metronome(on: true, bpm: 110)) }
                    Button("Metronome off") { model.command(.metronome(on: false, bpm: 110)) }
                } header: {
                    Text("Watch controls")
                } footer: {
                    Text("Keep this app open during the demo. Training tool – not a medical device.")
                }
            }
            .navigationTitle("CPR Coach Relay")
        }
    }

    private func yesNo(_ b: Bool) -> String { b ? "yes" : "no" }
}
