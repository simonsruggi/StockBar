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
        let displayMode = storageService.menuBarDisplay

        // Icon only
        if displayMode == "icon" {
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusItem.button?.title = ""
            statusItem.button?.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "StockBar")
            return
        }

        // Compute portfolio stats
        var totalPnl = 0.0
        var totalValue = 0.0
        var totalCost = 0.0
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                if let quote = stockService.quotes[holding.symbol] {
                    let rate = stockService.rate(from: quote.currency)
                    totalPnl += holding.pnl(currentPrice: quote.displayPrice(extendedHours: storageService.showExtendedHours)) * rate
                    totalValue += holding.marketValue(currentPrice: quote.displayPrice(extendedHours: storageService.showExtendedHours)) * rate
                    let costRate = stockService.rate(from: quote.currency, for: holding.purchaseDate)
                    totalCost += (holding.avgPrice * holding.quantity) * costRate
                }
            }
        }
        let totalPnlPct = totalCost > 0 ? (totalPnl / totalCost) * 100 : 0

        // Find best/worst watchlist stock by daily change %
        let bestStock = storageService.watchlist.compactMap { stockService.quotes[$0] }
            .max(by: { $0.changePercent < $1.changePercent })
        let worstStock = storageService.watchlist.compactMap { stockService.quotes[$0] }
            .min(by: { $0.changePercent < $1.changePercent })

        let currSymbol = StorageService.currencySymbol(for: storageService.preferredCurrency)
        let title: String
        let color: NSColor

        switch displayMode {
        case "totalValue":
            title = " \(String(format: "%.2f", totalValue))\(currSymbol)"
            color = totalPnl >= 0 ? .systemGreen : .systemRed

        case "pnlPercent":
            let sign = totalPnlPct >= 0 ? "+" : ""
            title = " P&L \(sign)\(String(format: "%.1f", totalPnlPct))%"
            color = totalPnlPct >= 0 ? .systemGreen : .systemRed

        case "pnlFull":
            let sign = totalPnl >= 0 ? "+" : ""
            let pctSign = totalPnlPct >= 0 ? "+" : ""
            title = " \(sign)\(String(format: "%.2f", totalPnl))\(currSymbol) (\(pctSign)\(String(format: "%.1f", totalPnlPct))%)"
            color = totalPnl >= 0 ? .systemGreen : .systemRed

        case "bestStock":
            if let best = bestStock {
                let sign = best.changePercent >= 0 ? "+" : ""
                title = " \(best.symbol) \(sign)\(String(format: "%.1f", best.changePercent))%"
                color = best.changePercent >= 0 ? .systemGreen : .systemRed
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "worstStock":
            if let worst = worstStock {
                let sign = worst.changePercent >= 0 ? "+" : ""
                title = " \(worst.symbol) \(sign)\(String(format: "%.1f", worst.changePercent))%"
                color = worst.changePercent >= 0 ? .systemGreen : .systemRed
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "bestWorst":
            if let best = bestStock, let worst = worstStock {
                let bSign = best.changePercent >= 0 ? "+" : ""
                let wSign = worst.changePercent >= 0 ? "+" : ""
                title = " ▲\(best.symbol) \(bSign)\(String(format: "%.1f", best.changePercent))%  ▼\(worst.symbol) \(wSign)\(String(format: "%.1f", worst.changePercent))%"
                color = .labelColor
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        default: // "pnl"
            let sign = totalPnl >= 0 ? "+" : ""
            title = " P&L \(sign)\(String(format: "%.2f", totalPnl))\(currSymbol)"
            color = totalPnl >= 0 ? .systemGreen : .systemRed
        }

        statusItem.button?.image = nil
        statusItem.button?.title = title

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
