import SwiftUI

struct AddHoldingView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    let portfolioId: UUID
    @Binding var isPresented: UUID?

    @State private var searchText = ""
    @State private var quantityText = ""
    @State private var avgPriceText = ""
    @State private var purchaseDate = Date()
    @State private var searchResults: [SearchResult] = []
    @State private var selectedSymbol: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add holding")
                    .font(.headline)
                Spacer()
                Button("Close") { isPresented = nil }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.top)

            // Symbol search
            if let selected = selectedSymbol {
                HStack {
                    Text(selected)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: {
                        selectedSymbol = nil
                        searchText = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            } else {
                TextField("Symbol, name or ISIN (e.g. AAPL, IE00B4L5Y983)", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .onChange(of: searchText) { _, newValue in
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

                if !searchResults.isEmpty {
                    List(searchResults.prefix(5)) { result in
                        Button(action: {
                            searchTask?.cancel()
                            selectedSymbol = result.symbol
                            searchResults = []
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
            }

            // Quantity & price
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Quantity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0", text: $quantityText)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("Avg price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("0.00", text: $avgPriceText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Purchase date")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            .padding(.horizontal)

            Spacer()

            Button("Add") {
                addHolding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSymbol == nil || quantityText.isEmpty || avgPriceText.isEmpty)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addHolding() {
        guard let sym = selectedSymbol,
              let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: "."))
        else { return }

        storageService.addHolding(to: portfolioId, symbol: sym, quantity: qty, avgPrice: price, purchaseDate: purchaseDate)
        Task {
            await stockService.refreshAll(storageService: storageService)
        }
        isPresented = nil
    }
}
