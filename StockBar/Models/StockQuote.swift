import Foundation

struct StockQuote: Identifiable, Codable {
    let symbol: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double
    let currency: String
    let marketState: String

    // Extended hours
    let preMarketPrice: Double?
    let preMarketChange: Double?
    let preMarketChangePercent: Double?
    let postMarketPrice: Double?
    let postMarketChange: Double?
    let postMarketChangePercent: Double?

    var id: String { symbol }

    var isPositive: Bool { change >= 0 }

    /// Returns the most relevant current price based on market state
    var effectivePrice: Double {
        switch marketState {
        case "PRE":
            return preMarketPrice ?? price
        case "POST":
            return postMarketPrice ?? price
        case "CLOSED":
            // After hours closed: use post-market if available
            return postMarketPrice ?? price
        default:
            return price
        }
    }

    /// True if we have extended hours data to show
    var isExtendedHours: Bool {
        switch marketState {
        case "PRE": return preMarketPrice != nil
        case "POST": return postMarketPrice != nil
        case "CLOSED": return postMarketPrice != nil
        default: return false
        }
    }

    /// Extended hours change (from regular close)
    var extendedChange: Double? {
        switch marketState {
        case "PRE": return preMarketChange
        case "POST", "CLOSED": return postMarketChange
        default: return nil
        }
    }

    /// Extended hours change percent
    var extendedChangePercent: Double? {
        switch marketState {
        case "PRE": return preMarketChangePercent
        case "POST", "CLOSED": return postMarketChangePercent
        default: return nil
        }
    }

    /// Price respecting the extended hours preference
    func displayPrice(extendedHours: Bool) -> Double {
        extendedHours ? effectivePrice : price
    }

    var marketStateLabel: String {
        switch marketState {
        case "PRE": return "Pre"
        case "POST": return "Post"
        case "CLOSED":
            if postMarketPrice != nil { return "Post" }
            return "Closed"
        case "REGULAR": return ""
        default: return "Closed"
        }
    }
}

struct Portfolio: Identifiable, Codable {
    var id: UUID
    var name: String
    var holdings: [Holding]

    init(id: UUID = UUID(), name: String, holdings: [Holding] = []) {
        self.id = id
        self.name = name
        self.holdings = holdings
    }
}

struct Holding: Identifiable, Codable {
    var id: UUID
    var symbol: String
    var quantity: Double
    var avgPrice: Double

    init(id: UUID = UUID(), symbol: String, quantity: Double, avgPrice: Double) {
        self.id = id
        self.symbol = symbol
        self.quantity = quantity
        self.avgPrice = avgPrice
    }

    func pnl(currentPrice: Double) -> Double {
        (currentPrice - avgPrice) * quantity
    }

    func pnlPercent(currentPrice: Double) -> Double {
        guard avgPrice > 0 else { return 0 }
        return ((currentPrice - avgPrice) / avgPrice) * 100
    }

    func marketValue(currentPrice: Double) -> Double {
        currentPrice * quantity
    }
}

struct SearchResult: Identifiable, Codable {
    let symbol: String
    let name: String
    let exchange: String
    let type: String

    var id: String { symbol }

    private enum CodingKeys: String, CodingKey {
        case symbol
        case name = "longname"
        case exchange
        case type = "quoteType"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        exchange = try container.decodeIfPresent(String.self, forKey: .exchange) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    }

    init(symbol: String, name: String, exchange: String, type: String) {
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.type = type
    }
}
