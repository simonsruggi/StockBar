import SwiftUI

struct AddHoldingView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Environment(\.dismiss) var dismiss

    let portfolioId: UUID

    @State private var symbol = ""
    @State private var quantityText = ""
    @State private var avgPriceText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var selectedSymbol: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Aggiungi titolo")
                    .font(.headline)
                Spacer()
                Button("Chiudi") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.top)

            // Symbol search
            TextField("Cerca simbolo (es. AAPL)", text: $symbol)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onChange(of: symbol) { _, newValue in
                    if selectedSymbol != nil {
                        // User edited the text after selecting → reset selection
                        if newValue != selectedSymbol {
                            selectedSymbol = nil
                        } else {
                            return
                        }
                    }
                    searchTask?.cancel()
                    guard newValue.count >= 1 else {
                        searchResults = []
                        return
                    }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        searchResults = await stockService.search(query: newValue)
                    }
                }

            if !searchResults.isEmpty && selectedSymbol == nil {
                List(searchResults.prefix(5)) { result in
                    Button(action: {
                        searchTask?.cancel()
                        searchResults = []
                        selectedSymbol = result.symbol
                        symbol = result.symbol
                    }) {
                        HStack {
                            Text(result.symbol)
                                .fontWeight(.semibold)
                            Text(result.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(height: min(CGFloat(searchResults.prefix(5).count) * 30, 150))
            }

            // Quantity & price
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

            Button("Aggiungi") {
                addHolding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSymbol == nil || quantityText.isEmpty || avgPriceText.isEmpty)
            .padding()
        }
        .frame(width: 340, height: 350)
    }

    private func addHolding() {
        guard let sym = selectedSymbol,
              let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: "."))
        else { return }

        storageService.addHolding(to: portfolioId, symbol: sym, quantity: qty, avgPrice: price)
        Task {
            await stockService.fetchQuotes(symbols: [sym])
        }
        dismiss()
    }
}
