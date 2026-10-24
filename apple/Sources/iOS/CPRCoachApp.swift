// iPhone relay entry point and its UI model: watch → laptop forwarding, laptop → watch commands.
import Observation
import SwiftUI
import UIKit

@main
struct CPRCoachApp: App {
    @State private var model = RelayModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
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
        watch = WatchLink(events: events, outbound: outbound)

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
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)),
              url.scheme == "ws" || url.scheme == "wss"
        else { return }
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
        case .imuIn: inCount += 1
        case .heartRate(let bpm): lastHeartRate = bpm
        case .socket(let s): socketState = s
        case .sent: outCount += 1
        case .dropped: droppedTotal += 1
        case .command(let cmd): watch.send(cmd)
        }
    }
}
