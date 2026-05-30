import AppKit
import SwiftUI

@main
struct DiskoApp: App {
    @StateObject private var monitor = SystemMonitor()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(monitor: monitor)
                .frame(width: 390)
        } label: {
            MenuBarLoadView(
                cpu: monitor.snapshot.cpu.usageRatio ?? 0,
                memory: monitor.snapshot.memory.usedRatio
            )
        }
        .menuBarExtraStyle(.window)

        Window("Disko", id: "details") {
            DetailWindowView(monitor: monitor)
        }
        .defaultSize(width: 920, height: 680)
    }
}
