import SwiftUI

enum SearchMode {
    case watchlist
    case holding(portfolioId: UUID)
}

struct SearchView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    let mode: SearchMode
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Search")
                    .font(.headline)
                Spacer()
                Button("Close") { isPresented = false }
                    .buttonStyle(.borderless)
            }
            .padding()

            TextField("Symbol, name or ISIN (e.g. AAPL, Tesla, IE00B4L5Y983)", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onChange(of: query) { _, newValue in
                    searchTask?.cancel()
                    guard newValue.count >= 2 else {
                        results = []
                        return
                    }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        isSearching = true
                        print("[SearchView] searching for: \(newValue)")
                        let searchResults = await stockService.search(query: newValue)
                        print("[SearchView] got \(searchResults.count) results")
                        for r in searchResults {
                            print("[SearchView] result: \(r.symbol) - \(r.name)")
                        }
                        guard !Task.isCancelled else { return }
                        results = searchResults
                        isSearching = false
                        // Fetch prices for search results
                        let symbols = searchResults.map(\.symbol)
                        print("[SearchView] fetching quotes for \(symbols)")
                        if !symbols.isEmpty {
                            await stockService.fetchQuotes(symbols: symbols)
                            print("[SearchView] after fetch, quotes keys: \(Array(stockService.quotes.keys))")
                            for s in symbols {
                                if let q = stockService.quotes[s] {
                                    print("[SearchView] \(s) -> \(q.price)")
                                } else {
                                    print("[SearchView] \(s) -> NO QUOTE")
                                }
                            }
                        }
                    }
                }

            Divider()
                .padding(.top, 8)

            if isSearching {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if results.isEmpty && query.count >= 2 {
                Spacer()
                Text("No results")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(results) { result in
                    Button(action: { addResult(result) }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.symbol)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                                Text(result.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()

                            if let quote = stockService.quotes[result.symbol] {
                                Text("\(quote.price.formatted(.number.precision(.fractionLength(2)))) \(quote.currency)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                            }

                            Text(result.exchange)
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            if isAlreadyAdded(result.symbol) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queryLooksLikeISIN: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.count >= 6 && q.prefix(2).allSatisfy(\.isLetter) && q.dropFirst(2).allSatisfy { $0.isLetter || $0.isNumber }
    }

    private func addResult(_ result: SearchResult) {
        switch mode {
        case .watchlist:
            storageService.addToWatchlist(result.symbol)
            if queryLooksLikeISIN {
                storageService.setISIN(query.trimmingCharacters(in: .whitespaces).uppercased(), for: result.symbol)
            }
            isPresented = false
            Task {
                await stockService.fetchQuotes(symbols: [result.symbol])
            }
        case .holding:
            // For holdings, we dismiss and the AddHoldingView handles it
            break
        }
    }

    private func isAlreadyAdded(_ symbol: String) -> Bool {
        switch mode {
        case .watchlist:
            return storageService.watchlist.contains(symbol)
        case .holding:
            return false
        }
    }
}
