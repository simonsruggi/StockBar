import SwiftUI

enum Tab: String, CaseIterable {
    case watchlist = "Watchlist"
    case portfolios = "Portafogli"
}

struct ContentView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @State private var selectedTab: Tab = .watchlist
    @State private var showSearch = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("StockBar")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                if stockService.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                Button(action: {
                    Task {
                        await stockService.refreshAll(storageService: storageService)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)

                Button(action: { showSearch = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Content
            switch selectedTab {
            case .watchlist:
                WatchlistView()
            case .portfolios:
                PortfolioListView()
            }
        }
        .frame(width: 380, height: 520)
        .sheet(isPresented: $showSearch) {
            SearchView(mode: .watchlist)
        }
    }
}
