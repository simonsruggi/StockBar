import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Binding var showSearch: Bool

    var sortedSymbols: [String] {
        storageService.watchlist.sorted { a, b in
            let pctA = stockService.quotes[a]?.changePercent ?? 0
            let pctB = stockService.quotes[b]?.changePercent ?? 0
            return pctA > pctB
        }
    }

    var body: some View {
        if storageService.watchlist.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "star")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("No stocks in watchlist")
                    .foregroundColor(.secondary)
                Button("Add stock") {
                    showSearch = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
            List {
                ForEach(sortedSymbols, id: \.self) { symbol in
                    if let quote = stockService.quotes[symbol] {
                        QuoteRow(quote: quote)
                            .contextMenu {
                                Button(role: .destructive) {
                                    storageService.removeFromWatchlist(symbol)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    } else {
                        HStack {
                            Text(symbol)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                storageService.removeFromWatchlist(symbol)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let symbols = offsets.map { storageService.watchlist[$0] }
                    symbols.forEach { storageService.removeFromWatchlist($0) }
                }
                .onMove { source, destination in
                    storageService.moveWatchlistItem(from: source, to: destination)
                }
            }
            .listStyle(.plain)

            Divider()

            Button(action: { showSearch = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add stock")
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .padding(8)
            }
        }
    }
}

struct QuoteRow: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    let quote: StockQuote

    private var displayCurrency: String {
        let pref = storageService.stockPriceCurrency
        return pref.isEmpty ? quote.currency : pref
    }

    private var priceRate: Double {
        stockService.priceRate(from: quote.currency)
    }

    private var currSymbol: String {
        StorageService.currencySymbol(for: displayCurrency)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(quote.symbol)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    if storageService.showExtendedHours, quote.isExtendedHours, !quote.marketStateLabel.isEmpty {
                        Text(quote.marketStateLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(quote.marketState.hasPrefix("PRE") ? .orange : .purple)
                            )
                    }
                }
                Text(quote.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Regular market price + change
                Text(String(format: "%.2f %@", quote.price * priceRate, currSymbol))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                HStack(spacing: 2) {
                    Image(systemName: quote.isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9))
                    Text(String(format: "%+.2f (%.1f%%)", quote.change * priceRate, quote.changePercent))
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundColor(quote.isPositive ? .green : .red)

                // Extended hours price
                if storageService.showExtendedHours,
                   let extPrice = quote.isExtendedHours ? quote.effectivePrice : nil,
                   let extChg = quote.extendedChange,
                   let extPct = quote.extendedChangePercent {
                    HStack(spacing: 2) {
                        Text(String(format: "%.2f", extPrice * priceRate))
                            .fontWeight(.medium)
                        Text(String(format: "%+.2f (%.1f%%)", extChg * priceRate, extPct))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(extChg >= 0 ? .green.opacity(0.8) : .red.opacity(0.8))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
