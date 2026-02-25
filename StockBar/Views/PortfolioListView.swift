import SwiftUI

struct PortfolioListView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @State private var showNewPortfolio = false
    @State private var newPortfolioName = ""

    var body: some View {
        if storageService.portfolios.isEmpty && !showNewPortfolio {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "briefcase")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("Nessun portafoglio")
                    .foregroundColor(.secondary)
                Button("Crea portafoglio") {
                    showNewPortfolio = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                List {
                    if showNewPortfolio {
                        HStack {
                            TextField("Nome portafoglio", text: $newPortfolioName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    createPortfolio()
                                }
                            Button("OK") {
                                createPortfolio()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newPortfolioName.isEmpty)
                        }
                        .padding(.vertical, 4)
                    }

                    ForEach(storageService.portfolios) { portfolio in
                        PortfolioSection(portfolio: portfolio)
                    }
                    .onDelete { offsets in
                        storageService.deletePortfolio(at: offsets)
                    }
                }
                .listStyle(.plain)

                Divider()

                Button(action: { showNewPortfolio = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Nuovo portafoglio")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        }
    }

    private func createPortfolio() {
        guard !newPortfolioName.isEmpty else { return }
        storageService.addPortfolio(name: newPortfolioName)
        newPortfolioName = ""
        showNewPortfolio = false
    }
}

struct PortfolioSection: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Environment(\.addHoldingAction) var addHoldingAction
    let portfolio: Portfolio

    var totalValueEUR: Double {
        portfolio.holdings.reduce(0) { sum, holding in
            guard let quote = stockService.quotes[holding.symbol] else { return sum }
            let rate = stockService.rateToEUR(from: quote.currency)
            return sum + holding.marketValue(currentPrice: quote.effectivePrice) * rate
        }
    }

    var totalPnlEUR: Double {
        portfolio.holdings.reduce(0) { sum, holding in
            guard let quote = stockService.quotes[holding.symbol] else { return sum }
            let rate = stockService.rateToEUR(from: quote.currency)
            return sum + holding.pnl(currentPrice: quote.effectivePrice) * rate
        }
    }

    var totalCostEUR: Double {
        portfolio.holdings.reduce(0) { sum, holding in
            guard let quote = stockService.quotes[holding.symbol] else { return sum }
            let rate = stockService.rateToEUR(from: quote.currency)
            return sum + (holding.avgPrice * holding.quantity) * rate
        }
    }

    var totalPnlPercent: Double {
        guard totalCostEUR > 0 else { return 0 }
        return (totalPnlEUR / totalCostEUR) * 100
    }

    var body: some View {
        Section {
            // Summary row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Valore totale")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f\u{20AC}", totalValueEUR))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("P&L")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 2) {
                        Text(String(format: "%+.2f\u{20AC}", totalPnlEUR))
                        Text(String(format: "(%.1f%%)", totalPnlPercent))
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(totalPnlEUR >= 0 ? .green : .red)
                }
            }
            .padding(.vertical, 2)

            // Column headers
            if !portfolio.holdings.isEmpty {
                HStack(spacing: 0) {
                    Text("Ticker")
                        .frame(width: 80, alignment: .leading)
                    Text("Prezzo")
                        .frame(maxWidth: .infinity)
                    Text("Valore / P&L")
                        .frame(width: 120, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.vertical, 1)
            }

            // Holdings
            ForEach(portfolio.holdings) { holding in
                HoldingRow(holding: holding, portfolioId: portfolio.id)
            }

            // Add holding button
            Button(action: { addHoldingAction.perform(portfolio.id) }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Aggiungi titolo")
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
        } header: {
            Text(portfolio.name)
                .font(.headline)
        }
    }
}

struct HoldingRow: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Environment(\.editHoldingAction) var editHoldingAction
    let holding: Holding
    let portfolioId: UUID

    var quote: StockQuote? {
        stockService.quotes[holding.symbol]
    }

    private func formatQty(_ qty: Double) -> String {
        qty == qty.rounded(.down) ? String(format: "%.0f", qty) : String(format: "%.2f", qty)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Col 1: Ticker + Qty@Avg
            VStack(alignment: .leading, spacing: 1) {
                Text(holding.symbol)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                Text("\(formatQty(holding.quantity))\u{00D7}\(String(format: "%.2f", holding.avgPrice))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            if let quote {
                let rate = stockService.rateToEUR(from: quote.currency)
                let currSymbol = quote.currency == "EUR" ? "\u{20AC}" : "$"

                // Col 2: Prezzo USD + badge
                HStack(spacing: 3) {
                    Text(String(format: "%.2f %@", quote.effectivePrice, currSymbol))
                        .font(.system(.caption, design: .monospaced))
                    if quote.isExtendedHours, !quote.marketStateLabel.isEmpty {
                        Text(quote.marketStateLabel)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(quote.marketState.hasPrefix("PRE") ? .orange : .purple)
                            )
                    }
                }
                .frame(maxWidth: .infinity)

                // Col 3: Controvalore EUR + P&L
                let marketVal = holding.marketValue(currentPrice: quote.effectivePrice) * rate
                let pnl = holding.pnl(currentPrice: quote.effectivePrice) * rate
                let pnlPct = holding.pnlPercent(currentPrice: quote.effectivePrice)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.2f\u{20AC}", marketVal))
                        .font(.system(.caption, design: .monospaced))
                    Text(String(format: "%+.2f\u{20AC} (%.1f%%)", pnl, pnlPct))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(pnl >= 0 ? .green : .red)
                }
                .frame(width: 120, alignment: .trailing)
            } else {
                Spacer()
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                editHoldingAction.perform(portfolioId, holding)
            } label: {
                Label("Modifica", systemImage: "pencil")
            }
            Button(role: .destructive) {
                storageService.removeHolding(from: portfolioId, holdingId: holding.id)
            } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
    }
}

struct EditHoldingView: View {
    @EnvironmentObject var storageService: StorageService

    let portfolioId: UUID
    let holding: Holding
    @Binding var isPresented: (portfolioId: UUID, holding: Holding)?

    @State private var quantityText: String
    @State private var avgPriceText: String

    init(portfolioId: UUID, holding: Holding, isPresented: Binding<(portfolioId: UUID, holding: Holding)?>) {
        self.portfolioId = portfolioId
        self.holding = holding
        self._isPresented = isPresented
        _quantityText = State(initialValue: String(format: "%.2f", holding.quantity))
        _avgPriceText = State(initialValue: String(format: "%.2f", holding.avgPrice))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Modifica \(holding.symbol)")
                    .font(.headline)
                Spacer()
                Button("Chiudi") { isPresented = nil }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.top)

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Quantita")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0", text: $quantityText)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("Prezzo medio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0.00", text: $avgPriceText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal)

            Spacer()

            Button("Salva") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(quantityText.isEmpty || avgPriceText.isEmpty)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        guard let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: "."))
        else { return }
        storageService.updateHolding(in: portfolioId, holdingId: holding.id, quantity: qty, avgPrice: price)
        isPresented = nil
    }
}
