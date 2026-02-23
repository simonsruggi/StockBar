import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

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
                Text("Nessun titolo nella watchlist")
                    .foregroundColor(.secondary)
                Text("Premi + per aggiungere titoli")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            List {
                ForEach(sortedSymbols, id: \.self) { symbol in
                    if let quote = stockService.quotes[symbol] {
                        QuoteRow(quote: quote)
                            .contextMenu {
                                Button(role: .destructive) {
                                    storageService.removeFromWatchlist(symbol)
                                } label: {
                                    Label("Rimuovi dai preferiti", systemImage: "trash")
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
                                Label("Rimuovi dai preferiti", systemImage: "trash")
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
        }
    }
}

struct QuoteRow: View {
    let quote: StockQuote

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(quote.symbol)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    if quote.isExtendedHours, !quote.marketStateLabel.isEmpty {
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
                Text(String(format: "%.2f", quote.price))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                HStack(spacing: 2) {
                    Image(systemName: quote.isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9))
                    Text(String(format: "%+.2f (%.1f%%)", quote.change, quote.changePercent))
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundColor(quote.isPositive ? .green : .red)

                // Extended hours price
                if let extPrice = quote.isExtendedHours ? quote.effectivePrice : nil,
                   let extChg = quote.extendedChange,
                   let extPct = quote.extendedChangePercent {
                    HStack(spacing: 2) {
                        Text(String(format: "%.2f", extPrice))
                            .fontWeight(.medium)
                        Text(String(format: "%+.2f (%.1f%%)", extChg, extPct))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(extChg >= 0 ? .green.opacity(0.8) : .red.opacity(0.8))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
