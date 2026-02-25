import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var stockService: StockService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Stock Price Currency
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stock Price Currency")
                        .font(.headline)
                    Picker("Price currency", selection: $storageService.stockPriceCurrency) {
                        Text("Original").tag("")
                        ForEach(StorageService.supportedCurrencies, id: \.self) { code in
                            Text("\(StorageService.currencySymbol(for: code)) \(code)")
                                .tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: storageService.stockPriceCurrency) {
                        stockService.exchangeRates.removeAll()
                        Task {
                            await stockService.refreshAll(storageService: storageService)
                        }
                    }
                    Text(storageService.stockPriceCurrency.isEmpty
                         ? "Prices shown in their native currency"
                         : "All prices converted to \(storageService.stockPriceCurrency)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Portfolio Currency
                VStack(alignment: .leading, spacing: 6) {
                    Text("Portfolio Currency")
                        .font(.headline)
                    Picker("Portfolio currency", selection: $storageService.preferredCurrency) {
                        ForEach(StorageService.supportedCurrencies, id: \.self) { code in
                            Text("\(StorageService.currencySymbol(for: code)) \(code)")
                                .tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: storageService.preferredCurrency) {
                        stockService.exchangeRates.removeAll()
                        Task {
                            await stockService.refreshAll(storageService: storageService)
                        }
                    }
                    Text("Portfolio totals and P&L converted to \(storageService.preferredCurrency)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Extended Hours
                VStack(alignment: .leading, spacing: 6) {
                    Text("Market Hours")
                        .font(.headline)
                    Toggle("Show extended hours (Pre/Post)", isOn: $storageService.showExtendedHours)
                        .toggleStyle(.switch)
                    Text("Show pre-market and after-hours prices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Menu Bar Display
                VStack(alignment: .leading, spacing: 6) {
                    Text("Menu Bar Display")
                        .font(.headline)
                    Picker("Display", selection: $storageService.menuBarDisplay) {
                        Text("P&L (+321.09€)").tag("pnl")
                        Text("P&L % (+2.3%)").tag("pnlPercent")
                        Text("P&L + % (+321.09€ +2.3%)").tag("pnlFull")
                        Text("Total Value (14396.67€)").tag("totalValue")
                        Text("Best Stock (▲ AAPL +1.2%)").tag("bestStock")
                        Text("Worst Stock (▼ TSLA -0.8%)").tag("worstStock")
                        Text("Best & Worst").tag("bestWorst")
                        Text("Icon Only").tag("icon")
                    }
                    .pickerStyle(.menu)
                    Text("Choose what to show in the menu bar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
    }
}
