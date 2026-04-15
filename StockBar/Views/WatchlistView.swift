import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Binding var showSearch: Bool
    @State private var searchText = ""
    @State private var addToPortfolio: (symbol: String, portfolioId: UUID)? = nil

    var sortedSymbols: [String] {
        storageService.watchlist.sorted { a, b in
            let pctA = stockService.quotes[a]?.changePercent ?? 0
            let pctB = stockService.quotes[b]?.changePercent ?? 0
            return pctA > pctB
        }
    }

    var filteredSymbols: [String] {
        guard !searchText.isEmpty else { return sortedSymbols }
        let query = searchText.lowercased()
        return sortedSymbols.filter { symbol in
            symbol.lowercased().contains(query) ||
            (stockService.quotes[symbol]?.name.lowercased().contains(query) ?? false) ||
            (storageService.isinMap[symbol]?.lowercased().contains(query) ?? false)
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
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Filter watchlist…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            List {
                ForEach(filteredSymbols, id: \.self) { symbol in
                    if let quote = stockService.quotes[symbol] {
                        QuoteRow(quote: quote)
                            .contextMenu {
                                watchlistContextMenu(symbol: symbol)
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
                            watchlistContextMenu(symbol: symbol)
                        }
                    }
                }
                .onDelete { offsets in
                    let currentList = filteredSymbols
                    let symbols = offsets.compactMap { idx in
                        idx < currentList.count ? currentList[idx] : nil
                    }
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
            .sheet(item: Binding<AddToPortfolioItem?>(
                get: {
                    if let atp = addToPortfolio {
                        return AddToPortfolioItem(symbol: atp.symbol, portfolioId: atp.portfolioId)
                    }
                    return nil
                },
                set: { addToPortfolio = $0.map { ($0.symbol, $0.portfolioId) } }
            )) { item in
                QuickAddHoldingView(symbol: item.symbol, portfolioId: item.portfolioId) {
                    addToPortfolio = nil
                }
                .environmentObject(stockService)
                .environmentObject(storageService)
                .frame(width: 300, height: 220)
            }
        }
    }

    @ViewBuilder
    private func watchlistContextMenu(symbol: String) -> some View {
        if !storageService.portfolios.isEmpty {
            Menu {
                ForEach(storageService.portfolios) { portfolio in
                    Button(portfolio.name) {
                        addToPortfolio = (symbol, portfolio.id)
                    }
                }
            } label: {
                Label("Add to Portfolio", systemImage: "plus.rectangle.on.folder")
            }
            Divider()
        }
        Button(role: .destructive) {
            storageService.removeFromWatchlist(symbol)
        } label: {
            Label("Remove from Watchlist", systemImage: "trash")
        }
    }
}

private struct AddToPortfolioItem: Identifiable {
    let symbol: String
    let portfolioId: UUID
    var id: String { "\(symbol)-\(portfolioId)" }
}

struct QuickAddHoldingView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    let symbol: String
    let portfolioId: UUID
    let onDismiss: () -> Void

    @State private var quantityText = ""
    @State private var avgPriceText = ""
    @State private var purchaseDate = Date()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add \(symbol)")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Quantity").font(.caption).foregroundColor(.secondary)
                    TextField("0", text: $quantityText)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("Avg price").font(.caption).foregroundColor(.secondary)
                    TextField("0.00", text: $avgPriceText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading) {
                Text("Purchase date").font(.caption).foregroundColor(.secondary)
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            Spacer()

            Button("Add") {
                guard let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
                      let price = Double(avgPriceText.replacingOccurrences(of: ",", with: "."))
                else { return }
                storageService.addHolding(to: portfolioId, symbol: symbol, quantity: qty, avgPrice: price, purchaseDate: purchaseDate)
                Task { await stockService.refreshAll(storageService: storageService) }
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(quantityText.isEmpty || avgPriceText.isEmpty)
        }
        .padding()
        .onAppear {
            // Pre-fill current price
            if let quote = stockService.quotes[symbol] {
                avgPriceText = String(format: "%.2f", quote.price)
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
