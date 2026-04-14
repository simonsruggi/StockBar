import Foundation

@MainActor
class StockService: ObservableObject {
    static let shared = StockService()

    @Published var quotes: [String: StockQuote] = [:]
    @Published var isLoading = false
    @Published var exchangeRates: [String: Double] = [:]  // e.g. "USDEUR" -> 0.92 (rate to preferred currency)
    @Published var historicalRates: [String: Double] = [:]  // e.g. "USDEUR:1704067200" -> 0.9045 (rate at date)

    private let session: URLSession
    private var crumb: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
        ]
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = .shared
        session = URLSession(configuration: config)
    }

    static func collectSymbols(storageService: StorageService) -> Set<String> {
        var syms = Set(storageService.watchlist)
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                syms.insert(holding.symbol)
            }
        }
        return syms
    }

    /// Full refresh: quotes (REST) + exchange rates. Use only at startup or when WSS is down.
    func refreshAll(storageService: StorageService) async {
        let allSymbols = Self.collectSymbols(storageService: storageService)
        guard !allSymbols.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        // Evict quotes for symbols no longer tracked
        let staleKeys = Set(quotes.keys).subtracting(allSymbols)
        for key in staleKeys { quotes.removeValue(forKey: key) }

        await fetchQuotes(symbols: Array(allSymbols))
        await refreshExchangeRates(storageService: storageService)
    }

    /// Refresh only exchange rates (current + historical). Called periodically while WSS handles quotes.
    func refreshExchangeRates(storageService: StorageService) async {
        let allSymbols = Self.collectSymbols(storageService: storageService)
        guard !allSymbols.isEmpty else { return }

        // Fetch exchange rates for all stock currencies toward both target currencies
        let preferredCurrency = storageService.preferredCurrency
        let priceCurrency = storageService.stockPriceCurrency

        // Collect all pairs we need: (from, to)
        var pairs = Set<String>() // "FROMTO" keys
        for symbol in allSymbols {
            guard let quote = quotes[symbol] else { continue }
            if quote.currency != preferredCurrency {
                pairs.insert("\(quote.currency)|\(preferredCurrency)")
            }
            if !priceCurrency.isEmpty && quote.currency != priceCurrency {
                pairs.insert("\(quote.currency)|\(priceCurrency)")
            }
        }

        // Evict exchange rates no longer needed
        let neededRateKeys = Set(pairs.map { pair -> String in
            let parts = pair.split(separator: "|")
            return "\(parts[0])\(parts[1])"
        })
        let staleRateKeys = Set(exchangeRates.keys).subtracting(neededRateKeys)
        for key in staleRateKeys { exchangeRates.removeValue(forKey: key) }

        await withTaskGroup(of: Void.self) { group in
            for pair in pairs {
                let parts = pair.split(separator: "|")
                let from = String(parts[0])
                let to = String(parts[1])
                group.addTask { [weak self] in
                    await self?.fetchExchangeRate(from: from, to: to)
                }
            }
        }

        // Fetch historical rates for holdings with purchase date — skip if already cached
        var neededHistoricalKeys = Set<String>()
        var historicalKeysToFetch = Set<String>()
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                guard let purchaseDate = holding.purchaseDate,
                      let quote = quotes[holding.symbol],
                      quote.currency != preferredCurrency
                else { continue }
                let dayStart = Calendar.current.startOfDay(for: purchaseDate)
                let ts = Int(dayStart.timeIntervalSince1970)
                let cacheKey = "\(quote.currency)\(preferredCurrency):\(ts)"
                neededHistoricalKeys.insert(cacheKey)
                if historicalRates[cacheKey] == nil {
                    historicalKeysToFetch.insert("\(quote.currency)|\(preferredCurrency)|\(ts)")
                }
            }
        }

        // Evict historical rates no longer needed
        let staleHistKeys = Set(historicalRates.keys).subtracting(neededHistoricalKeys)
        for key in staleHistKeys { historicalRates.removeValue(forKey: key) }

        await withTaskGroup(of: Void.self) { group in
            for key in historicalKeysToFetch {
                let parts = key.split(separator: "|")
                guard parts.count == 3,
                      let ts = Int(parts[2])
                else { continue }
                let from = String(parts[0])
                let to = String(parts[1])
                group.addTask { [weak self] in
                    await self?.fetchHistoricalExchangeRate(from: from, to: to, dateTimestamp: ts)
                }
            }
        }
    }

    func fetchQuotes(symbols: [String]) async {
        guard !symbols.isEmpty else { return }

        // Try v7 batch quote first (single HTTP call, live extended hours)
        if await fetchQuotesV7(symbols: symbols) {
            return
        }

        // Fallback: fetch each symbol via v8 chart API
        print("[StockService] v7 failed, falling back to v8 chart API")
        await withTaskGroup(of: Void.self) { group in
            for symbol in symbols {
                group.addTask { [weak self] in
                    await self?.fetchSingleQuote(symbol: symbol)
                }
            }
        }
    }

    // MARK: - v7 Quote API (batch, live extended hours)

    private func fetchCrumb() async -> Bool {
        // Step 1: GET fc.yahoo.com to collect cookies
        guard let cookieUrl = URL(string: "https://fc.yahoo.com") else { return false }
        _ = try? await session.data(from: cookieUrl)

        // Step 2: GET crumb using the cookies
        guard let crumbUrl = URL(string: "https://query2.finance.yahoo.com/v1/test/getcrumb") else { return false }
        do {
            let (data, response) = try await session.data(from: crumbUrl)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return false }
            guard let crumbValue = String(data: data, encoding: .utf8), !crumbValue.isEmpty else { return false }
            self.crumb = crumbValue
            return true
        } catch {
            print("[StockService] fetchCrumb error: \(error)")
            return false
        }
    }

    private func fetchQuotesV7(symbols: [String]) async -> Bool {
        // Ensure we have a crumb
        if crumb == nil {
            guard await fetchCrumb() else { return false }
        }

        guard let crumb = crumb else { return false }

        let joined = symbols.map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }.joined(separator: ",")
        let crumbEncoded = crumb.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? crumb
        guard let url = URL(string: "https://query2.finance.yahoo.com/v7/finance/quote?symbols=\(joined)&crumb=\(crumbEncoded)") else { return false }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResp = response as? HTTPURLResponse else { return false }

            // If 401, re-fetch crumb once and retry
            if httpResp.statusCode == 401 {
                self.crumb = nil
                guard await fetchCrumb() else { return false }
                return await fetchQuotesV7(symbols: symbols)
            }

            guard httpResp.statusCode == 200 else { return false }

            let decoded = try JSONDecoder().decode(YahooV7Response.self, from: data)
            guard let results = decoded.quoteResponse.result, !results.isEmpty else { return false }

            for q in results {
                let price = q.regularMarketPrice
                let previousClose = q.regularMarketPreviousClose ?? price
                let change = q.regularMarketChange ?? (price - previousClose)
                let changePercent = q.regularMarketChangePercent ?? (previousClose > 0 ? (change / previousClose) * 100 : 0)

                // Normalize marketState
                let rawState = q.marketState ?? "CLOSED"
                let marketState: String
                switch rawState {
                case "REGULAR": marketState = "REGULAR"
                case "PRE": marketState = "PRE"
                case "POST": marketState = "POST"
                default: marketState = "CLOSED" // PREPRE, POSTPOST, etc.
                }

                let preChg: Double? = if let pm = q.preMarketPrice { pm - price } else { nil }
                let prePct: Double? = if let ch = preChg, price > 0 { (ch / price) * 100 } else { nil }
                let postChg: Double? = if let pm = q.postMarketPrice { pm - price } else { nil }
                let postPct: Double? = if let ch = postChg, price > 0 { (ch / price) * 100 } else { nil }

                let quote = StockQuote(
                    symbol: q.symbol,
                    name: q.longName ?? q.shortName ?? q.symbol,
                    price: price,
                    change: change,
                    changePercent: changePercent,
                    currency: q.currency ?? "USD",
                    marketState: marketState,
                    preMarketPrice: q.preMarketPrice,
                    preMarketChange: preChg,
                    preMarketChangePercent: prePct,
                    postMarketPrice: q.postMarketPrice,
                    postMarketChange: postChg,
                    postMarketChangePercent: postPct
                )

                quotes[q.symbol] = quote
            }

            return true
        } catch {
            print("[StockService] v7 quote error: \(error)")
            return false
        }
    }

    private func fetchSingleQuote(symbol: String) async {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol

        // Two requests: daily for reliable price, intraday for extended hours
        guard let dailyUrl = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=2d"),
              let intraUrl = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1m&range=5d&includePrePost=true") else { return }

        do {
            // Fetch both in parallel
            async let dailyFetch = session.data(from: dailyUrl)
            async let intraFetch = session.data(from: intraUrl)

            let (dailyData, _) = try await dailyFetch
            let dailyResponse = try JSONDecoder().decode(YahooChartResponse.self, from: dailyData)
            guard let dailyResult = dailyResponse.chart.result?.first else { return }
            let meta = dailyResult.meta

            let price = meta.regularMarketPrice
            let previousClose = meta.chartPreviousClose ?? price
            let change = price - previousClose
            let changePercent = previousClose > 0 ? (change / previousClose) * 100 : 0

            // Determine market state from current trading period
            let now = Date().timeIntervalSince1970
            let ctp = meta.currentTradingPeriod
            let regEnd = ctp?.regular?.end ?? 0
            let regStart = ctp?.regular?.start ?? 0
            let preStart = ctp?.pre?.start ?? 0
            let postEnd = ctp?.post?.end ?? 0

            let marketState: String
            if now >= Double(regStart) && now < Double(regEnd) {
                marketState = "REGULAR"
            } else if now >= Double(preStart) && now < Double(regStart) {
                marketState = "PRE"
            } else if now >= Double(regEnd) && now < Double(postEnd) {
                marketState = "POST"
            } else {
                marketState = "CLOSED"
            }

            // Extract extended hours from intraday data
            var preMarketPrice: Double? = nil
            var postMarketPrice: Double? = nil

            if let (intraData, _) = try? await intraFetch,
               let intraResponse = try? JSONDecoder().decode(YahooChartResponse.self, from: intraData),
               let intraResult = intraResponse.chart.result?.first {

                let timestamps = intraResult.timestamp ?? []
                let closes = intraResult.indicators?.quote?.first?.close ?? []

                // Use regularMarketTime as the boundary for the last regular session
                let regTime = meta.regularMarketTime ?? 0

                // Find post-market: data after regularMarketTime on the last trading day
                for i in stride(from: timestamps.count - 1, through: 0, by: -1) {
                    if timestamps[i] > regTime, i < closes.count, let c = closes[i] {
                        postMarketPrice = c
                        break
                    }
                }

                // For pre-market: find data before regStart of today (only when market is PRE)
                if marketState == "PRE" {
                    for i in stride(from: timestamps.count - 1, through: 0, by: -1) {
                        if timestamps[i] >= preStart && timestamps[i] < regStart, i < closes.count, let c = closes[i] {
                            preMarketPrice = c
                            break
                        }
                    }
                }
            }

            let preChg: Double? = if let pm = preMarketPrice { pm - price } else { nil }
            let prePct: Double? = if let ch = preChg, price > 0 { (ch / price) * 100 } else { nil }
            let postChg: Double? = if let pm = postMarketPrice { pm - price } else { nil }
            let postPct: Double? = if let ch = postChg, price > 0 { (ch / price) * 100 } else { nil }

            let quote = StockQuote(
                symbol: meta.symbol,
                name: meta.longName ?? meta.shortName ?? meta.symbol,
                price: price,
                change: change,
                changePercent: changePercent,
                currency: meta.currency ?? "USD",
                marketState: marketState,
                preMarketPrice: preMarketPrice,
                preMarketChange: preChg,
                preMarketChangePercent: prePct,
                postMarketPrice: postMarketPrice,
                postMarketChange: postChg,
                postMarketChangePercent: postPct
            )

            quotes[meta.symbol] = quote
        } catch {
            print("Error fetching \(symbol): \(error)")
        }
    }

    func rate(from currency: String, for purchaseDate: Date? = nil) -> Double {
        let preferred = StorageService.shared.preferredCurrency
        if currency == preferred { return 1.0 }
        if let date = purchaseDate {
            let dayStart = Calendar.current.startOfDay(for: date)
            let ts = Int(dayStart.timeIntervalSince1970)
            let key = "\(currency)\(preferred):\(ts)"
            if let historical = historicalRates[key] { return historical }
        }
        return exchangeRates["\(currency)\(preferred)"] ?? 1.0
    }

    func priceRate(from currency: String) -> Double {
        let target = StorageService.shared.stockPriceCurrency
        if target.isEmpty || currency == target { return 1.0 }
        return exchangeRates["\(currency)\(target)"] ?? 1.0
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

    private func fetchHistoricalExchangeRate(from: String, to: String, dateTimestamp: Int) async {
        let symbol = "\(from)\(to)=X"
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        let period1 = dateTimestamp
        let period2 = dateTimestamp + 86400
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&period1=\(period1)&period2=\(period2)") else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = response.chart.result?.first,
                  let closes = result.indicators?.quote?.first?.close,
                  !closes.isEmpty
            else { return }
            let validCloses = closes.compactMap { $0 }
            guard let rate = validCloses.first ?? validCloses.last else { return }
            historicalRates["\(from)\(to):\(dateTimestamp)"] = rate
        } catch {
            print("Error fetching historical rate \(from)\(to) for \(dateTimestamp): \(error)")
        }
    }

    /// Ensures historical rate is loaded for a holding (e.g. when opening edit view)
    func ensureHistoricalRate(for holding: Holding) async {
        guard let purchaseDate = holding.purchaseDate,
              let quote = quotes[holding.symbol],
              quote.currency != StorageService.shared.preferredCurrency
        else { return }
        let dayStart = Calendar.current.startOfDay(for: purchaseDate)
        let ts = Int(dayStart.timeIntervalSince1970)
        let key = "\(quote.currency)\(StorageService.shared.preferredCurrency):\(ts)"
        guard historicalRates[key] == nil else { return }
        await fetchHistoricalExchangeRate(from: quote.currency, to: StorageService.shared.preferredCurrency, dateTimestamp: ts)
    }

    /// Update a quote from a WebSocket tick. Returns true if the quote was meaningful.
    func applyTick(_ ticker: Yaticker) -> Bool {
        let symbol = ticker.id
        guard !symbol.isEmpty, ticker.price > 0 else { return false }

        let existing = quotes[symbol]

        let marketState: String
        switch ticker.marketHours {
        case .preMarket: marketState = "PRE"
        case .postMarket, .extendedHoursMarket: marketState = "POST"
        case .regularMarket: marketState = "REGULAR"
        default: marketState = existing?.marketState ?? "CLOSED"
        }

        let price = Double(ticker.price)
        let change = Double(ticker.change)
        let changePercent = Double(ticker.changePercent)

        // Keep extended hours data from existing quote if WSS doesn't provide it
        let quote = StockQuote(
            symbol: symbol,
            name: existing?.name ?? ticker.shortName,
            price: price,
            change: change,
            changePercent: changePercent,
            currency: ticker.currency.isEmpty ? (existing?.currency ?? "USD") : ticker.currency,
            marketState: marketState,
            preMarketPrice: marketState == "PRE" ? price : existing?.preMarketPrice,
            preMarketChange: marketState == "PRE" ? change : existing?.preMarketChange,
            preMarketChangePercent: marketState == "PRE" ? changePercent : existing?.preMarketChangePercent,
            postMarketPrice: marketState == "POST" ? price : existing?.postMarketPrice,
            postMarketChange: marketState == "POST" ? change : existing?.postMarketChange,
            postMarketChangePercent: marketState == "POST" ? changePercent : existing?.postMarketChangePercent
        )

        quotes[symbol] = quote
        return true
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
        let timestamp: [Int]?
        let indicators: Indicators?
    }

    struct Indicators: Codable {
        let quote: [QuoteData]?
    }

    struct QuoteData: Codable {
        let close: [Double?]?
    }

    struct ChartMeta: Codable {
        let symbol: String
        let currency: String?
        let regularMarketPrice: Double
        let regularMarketTime: Int?
        let chartPreviousClose: Double?
        let longName: String?
        let shortName: String?
        let currentTradingPeriod: TradingPeriods?
    }

    struct TradingPeriods: Codable {
        let pre: PeriodInfo?
        let regular: PeriodInfo?
        let post: PeriodInfo?
    }

    struct PeriodInfo: Codable {
        let start: Int
        let end: Int
    }

    struct ChartError: Codable {
        let code: String?
        let description: String?
    }
}

// MARK: - Yahoo Finance v7 Quote API Models

private struct YahooV7Response: Codable {
    let quoteResponse: QuoteResponse

    struct QuoteResponse: Codable {
        let result: [V7Quote]?
        let error: V7Error?
    }

    struct V7Quote: Codable {
        let symbol: String
        let longName: String?
        let shortName: String?
        let currency: String?
        let regularMarketPrice: Double
        let regularMarketChange: Double?
        let regularMarketChangePercent: Double?
        let regularMarketPreviousClose: Double?
        let marketState: String?
        let preMarketPrice: Double?
        let postMarketPrice: Double?
    }

    struct V7Error: Codable {
        let code: String?
        let description: String?
    }
}

private struct YahooSearchResponse: Codable {
    let quotes: [SearchResult]
}
