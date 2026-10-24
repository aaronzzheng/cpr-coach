// iPhone app entry point. Coach tab: standalone coaching on the phone (camera + watch).
// Laptop link tab: relays the watch to the laptop dashboard and laptop commands back.
import Observation
import SwiftUI
import UIKit

@main
struct CPRCoachApp: App {
    @State private var model = RelayModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.coach)
        }
    }
}

@MainActor
@Observable
final class RelayModel {
    var socketState: LaptopSocket.State = .disconnected
    var wantConnected = false
    var watchPaired = false
    var watchInstalled = false
    var watchReachable = false
    var inPerSecond = 0
    var outPerSecond = 0
    var droppedTotal = 0
    var lastHeartRate: Int?
    let coach: CoachModel
    var addressError: String?
    var lastSocketError: String?

    @ObservationIgnored private let watch: WatchLink
    @ObservationIgnored private let socket: LaptopSocket
    @ObservationIgnored private let outbound: AsyncStream<Outbound>.Continuation
    @ObservationIgnored private var inCount = 0
    @ObservationIgnored private var outCount = 0

    init() {
        let (eventStream, events) = AsyncStream.makeStream(of: RelayEvent.self)
        // One consumer keeps frames in watch order; if the laptop stalls, keep only the newest.
        let (outStream, outbound) = AsyncStream.makeStream(of: Outbound.self, bufferingPolicy: .bufferingNewest(25))
        let socket = LaptopSocket(events: events)
        self.socket = socket
        self.outbound = outbound
        let watch = WatchLink(events: events)
        self.watch = watch
        coach = CoachModel(sendToWatch: { cmd in watch.send(cmd) })

        Task { [weak self] in
            for await event in eventStream { self?.apply(event) }
        }
        Task {
            for await frame in outStream { await socket.send(frame) }
        }
        Task { [weak self] in
            var tick = 0
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                tick += 1
                self.publishRates()
                if tick % 2 == 0 { self.sendStatus() }
            }
        }
        watch.activate()
    }

    func connect(address: String) {
        guard let url = laptopURL(from: address) else {
            addressError = "Enter the laptop's address, e.g. 192.168.1.20 or ws://192.168.1.20:8000/ingest"
            return
        }
        addressError = nil
        lastSocketError = nil
        wantConnected = true
        UIApplication.shared.isIdleTimerDisabled = true
        Task { await socket.connect(to: url) }
    }

    func disconnect() {
        wantConnected = false
        UIApplication.shared.isIdleTimerDisabled = false
        Task { await socket.disconnect() }
    }

    func command(_ cmd: WatchCommand) {
        watch.send(cmd)
    }

    private func publishRates() {
        inPerSecond = inCount
        outPerSecond = outCount
        inCount = 0
        outCount = 0
    }

    private func sendStatus() {
        guard socketState == .connected else { return }
        outbound.yield(.text(jsonString([
            "t": "status", "watch_reachable": watchReachable, "drops": droppedTotal,
        ])))
    }

    private func apply(_ event: RelayEvent) {
        switch event {
        case .watchState(let paired, let installed, let reachable):
            watchPaired = paired
            watchInstalled = installed
            watchReachable = reachable
        case .imu(let packet):
            inCount += 1
            coach.ingest(packet)
            if wantConnected { outbound.yield(.imu(packet)) }
        case .heartRate(let bpm, let watchTs):
            lastHeartRate = bpm
            coach.heartRate(bpm)
            if wantConnected {
                outbound.yield(.text(jsonString([
                    "t": "hr", "bpm": bpm, "ts": watchTs, "phone_rx": Date().timeIntervalSince1970,
                ])))
            }
        case .socket(let s):
            socketState = s
            if s == .connected { lastSocketError = nil }
        case .socketError(let message): lastSocketError = message
        case .sent: outCount += 1
        case .dropped: droppedTotal += 1
        case .command(let cmd): watch.send(cmd)
        }
    }
}

/// Accepts "192.168.1.20", "192.168.1.20:8000" or a full "ws://…/ingest" URL and fills in the
/// defaults (ws scheme, port 8000, /ingest path).
nonisolated func laptopURL(from address: String) -> URL? {
    var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") { text = "ws://" + text }
    guard var c = URLComponents(string: text), let host = c.host, !host.isEmpty else { return nil }
    if c.scheme == "http" { c.scheme = "ws" }
    if c.scheme == "https" { c.scheme = "wss" }
    guard c.scheme == "ws" || c.scheme == "wss" else { return nil }
    if c.port == nil { c.port = 8000 }
    if c.path.isEmpty || c.path == "/" { c.path = "/ingest" }
    return c.url
}

struct RootView: View {
    @Environment(CoachModel.self) private var coach

    var body: some View {
        TabView {
            CoachView()
                .toolbar(coach.phase == .setup || coach.phase == .summary ? .visible : .hidden, for: .tabBar)
                .tabItem { Label("Coach", systemImage: "waveform.path.ecg") }
            ContentView()
                .tabItem { Label("Laptop link", systemImage: "laptopcomputer") }
        }
        .tint(Palette.good)
    }
}
