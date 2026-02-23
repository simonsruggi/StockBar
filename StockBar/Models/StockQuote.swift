import Foundation

struct StockQuote: Identifiable, Codable {
    let symbol: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double
    let currency: String
    let marketState: String

    var id: String { symbol }

    var isPositive: Bool { change >= 0 }
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
