import Foundation

@MainActor
class StockService: ObservableObject {
    static let shared = StockService()

    @Published var quotes: [String: StockQuote] = [:]
    @Published var isLoading = false
    @Published var exchangeRates: [String: Double] = [:]  // e.g. "USDEUR" -> 0.92

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
        ]
        session = URLSession(configuration: config)
    }

    func refreshAll(storageService: StorageService) async {
        var allSymbols = Set(storageService.watchlist)
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                allSymbols.insert(holding.symbol)
            }
        }

        guard !allSymbols.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        await fetchQuotes(symbols: Array(allSymbols))
        await fetchExchangeRate(from: "USD", to: "EUR")
    }

    func fetchQuotes(symbols: [String]) async {
        guard !symbols.isEmpty else { return }

        // Fetch each symbol via v8 chart API (v7 requires auth now)
        await withTaskGroup(of: Void.self) { group in
            for symbol in symbols {
                group.addTask { [weak self] in
                    await self?.fetchSingleQuote(symbol: symbol)
                }
            }
        }
    }

    private func fetchSingleQuote(symbol: String) async {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=2d") else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)

            guard let result = response.chart.result?.first else { return }
            let meta = result.meta

            let price = meta.regularMarketPrice
            let previousClose = meta.chartPreviousClose ?? price
            let change = price - previousClose
            let changePercent = previousClose > 0 ? (change / previousClose) * 100 : 0

            let quote = StockQuote(
                symbol: meta.symbol,
                name: meta.longName ?? meta.shortName ?? meta.symbol,
                price: price,
                change: change,
                changePercent: changePercent,
                currency: meta.currency ?? "USD",
                marketState: meta.marketState ?? "CLOSED"
            )

            quotes[meta.symbol] = quote
        } catch {
            print("Error fetching \(symbol): \(error)")
        }
    }

    func rateToEUR(from currency: String) -> Double {
        if currency == "EUR" { return 1.0 }
        return exchangeRates["\(currency)EUR"] ?? 1.0
    }

    private func fetchExchangeRate(from: String, to: String) async {
        let symbol = "\(from)\(to)=X"
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d") else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            if let result = response.chart.result?.first {
                exchangeRates["\(from)\(to)"] = result.meta.regularMarketPrice
            }
        } catch {
            print("Error fetching exchange rate \(from)\(to): \(error)")
        }
    }

    func search(query: String) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://query2.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=10&newsCount=0") else { return [] }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
            return response.quotes
        } catch {
            print("Error searching: \(error)")
            return []
        }
    }
}

// MARK: - Yahoo Finance v8 Chart API Models

private struct YahooChartResponse: Codable {
    let chart: ChartData

    struct ChartData: Codable {
        let result: [ChartResult]?
        let error: ChartError?
    }

    struct ChartResult: Codable {
        let meta: ChartMeta
    }

    struct ChartMeta: Codable {
        let symbol: String
        let currency: String?
        let regularMarketPrice: Double
        let chartPreviousClose: Double?
        let longName: String?
        let shortName: String?
        let marketState: String?
    }

    struct ChartError: Codable {
        let code: String?
        let description: String?
    }
}

private struct YahooSearchResponse: Codable {
    let quotes: [SearchResult]
}
