import AppKit
import SwiftUI

extension Notification.Name {
    static let popoverDidClose = Notification.Name("popoverDidClose")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var stockService = StockService.shared
    private var storageService = StorageService.shared
    private var timer: Timer?
    private var tickerIndex = 0
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "StockBar")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let contentView = ContentView()
            .environmentObject(stockService)
            .environmentObject(storageService)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Start fetching
        Task {
            await stockService.refreshAll(storageService: storageService)
            updateMenuBarTitle()
        }

        // Refresh every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.stockService.refreshAll(storageService: self.storageService)
                self.updateMenuBarTitle()
            }
        }
    }

    private func updateMenuBarTitle() {
        var totalPnlEUR = 0.0
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                if let quote = stockService.quotes[holding.symbol] {
                    let pnl = holding.pnl(currentPrice: quote.effectivePrice)
                    let rate = stockService.rateToEUR(from: quote.currency)
                    totalPnlEUR += pnl * rate
                }
            }
        }

        let sign = totalPnlEUR >= 0 ? "+" : ""
        let title = " P&L \(sign)\(String(format: "%.2f", totalPnlEUR))\u{20AC}"

        statusItem.button?.image = nil
        statusItem.button?.title = title

        // Color via attributed string
        let color: NSColor = totalPnlEUR >= 0 ? .systemGreen : .systemRed
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: attrs)
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        NotificationCenter.default.post(name: .popoverDidClose, object: nil)
    }
}
