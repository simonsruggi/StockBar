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
    let portfolio: Portfolio
    @State private var showAddHolding = false

    var totalValueEUR: Double {
        portfolio.holdings.reduce(0) { sum, holding in
            guard let quote = stockService.quotes[holding.symbol] else { return sum }
            let rate = stockService.rateToEUR(from: quote.currency)
            return sum + holding.marketValue(currentPrice: quote.price) * rate
        }
    }

    var totalPnlEUR: Double {
        portfolio.holdings.reduce(0) { sum, holding in
            guard let quote = stockService.quotes[holding.symbol] else { return sum }
            let rate = stockService.rateToEUR(from: quote.currency)
            return sum + holding.pnl(currentPrice: quote.price) * rate
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

            // Holdings
            ForEach(portfolio.holdings) { holding in
                HoldingRow(holding: holding, portfolioId: portfolio.id)
            }

            // Add holding button
            Button(action: { showAddHolding = true }) {
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
        .sheet(isPresented: $showAddHolding) {
            AddHoldingView(portfolioId: portfolio.id)
        }
    }
}

struct HoldingRow: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    let holding: Holding
    let portfolioId: UUID
    @State private var showEdit = false

    var quote: StockQuote? {
        stockService.quotes[holding.symbol]
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.symbol)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                Text("\(String(format: "%.2f", holding.quantity)) @ \(String(format: "%.2f", holding.avgPrice))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let quote {
                let rate = stockService.rateToEUR(from: quote.currency)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f\u{20AC}", holding.marketValue(currentPrice: quote.price) * rate))
                        .font(.system(.caption, design: .monospaced))
                    let pnl = holding.pnl(currentPrice: quote.price) * rate
                    let pnlPct = holding.pnlPercent(currentPrice: quote.price)
                    Text(String(format: "%+.2f\u{20AC} (%.1f%%)", pnl, pnlPct))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(pnl >= 0 ? .green : .red)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button {
                showEdit = true
            } label: {
                Label("Modifica", systemImage: "pencil")
            }
            Button(role: .destructive) {
                storageService.removeHolding(from: portfolioId, holdingId: holding.id)
            } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEdit) {
            EditHoldingView(portfolioId: portfolioId, holding: holding)
        }
    }
}

struct EditHoldingView: View {
    @EnvironmentObject var storageService: StorageService
    @Environment(\.dismiss) var dismiss

    let portfolioId: UUID
    let holding: Holding

    @State private var quantityText: String
    @State private var avgPriceText: String

    init(portfolioId: UUID, holding: Holding) {
        self.portfolioId = portfolioId
        self.holding = holding
        _quantityText = State(initialValue: String(format: "%.2f", holding.quantity))
        _avgPriceText = State(initialValue: String(format: "%.2f", holding.avgPrice))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Modifica \(holding.symbol)")
                    .font(.headline)
                Spacer()
                Button("Chiudi") { dismiss() }
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
        .frame(width: 320, height: 180)
    }

    private func save() {
        guard let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: "."))
        else { return }
        storageService.updateHolding(in: portfolioId, holdingId: holding.id, quantity: qty, avgPrice: price)
        dismiss()
    }
}
