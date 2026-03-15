# StockBar

App macOS per la menu bar che mostra in tempo reale le quotazioni di borsa e il P&L del portafoglio. Non richiede account né API key: i dati vengono direttamente da Yahoo Finance.

## Descrizione

StockBar è un'app leggera che vive nella menu bar di macOS. Con un click sull'icona si apre un popover con watchlist, portafogli e impostazioni. I prezzi si aggiornano ogni 5 secondi automaticamente.

## Stack tecnologico

- **Linguaggio**: Swift 5.9
- **UI**: SwiftUI
- **Piattaforma**: macOS 14+ (Sonoma)
- **Build system**: Swift Package Manager (`Package.swift`)
- **Dati**: Yahoo Finance API (v7 batch quotes + v8 chart come fallback)
- **Dipendenze esterne**: nessuna

## Struttura cartelle principali

```
StockBar/
├── Package.swift               # Configurazione SPM, target unico, macOS 14+
├── StockBar/
│   ├── StockBarApp.swift       # Entry point (@main), collega AppDelegate
│   ├── AppDelegate.swift       # NSStatusItem, popover, timer aggiornamento 5s
│   ├── Models/
│   │   └── StockQuote.swift    # Modelli: StockQuote, Portfolio, Holding, SearchResult
│   ├── Services/
│   │   ├── StockService.swift  # Fetch quotazioni e tassi di cambio da Yahoo Finance
│   │   └── StorageService.swift# Persistenza locale (JSON in Application Support)
│   ├── Views/
│   │   ├── ContentView.swift   # Contenitore con tab (Watchlist / Portfolios / Settings)
│   │   ├── WatchlistView.swift # Lista ticker con prezzi e variazione giornaliera
│   │   ├── PortfolioListView.swift # Portafogli con P&L per holding
│   │   ├── AddHoldingView.swift# Form aggiunta/modifica holding
│   │   ├── SearchView.swift    # Ricerca ticker per simbolo o nome
│   │   └── SettingsView.swift  # Valuta, extended hours, modalità menu bar
│   ├── Assets.xcassets
│   └── Resources/AppIcon.icns
└── screenshots/                # Screenshot per README
```

## Funzionalità chiave

- **Menu bar configurabile**: P&L assoluto, P&L %, P&L + %, valore totale portafoglio, miglior/peggior titolo watchlist, solo icona
- **Watchlist**: aggiunta titoli per simbolo con ricerca live, prezzi in valuta originale o convertiti, badge PRE/POST per extended hours
- **Portafogli multipli**: prezzo medio di carico, data acquisto per tasso di cambio storico, P&L per holding e totale
- **Conversione valuta**: supporta EUR, USD, GBP, CHF, JPY, CAD, AUD; tassi di cambio live e storici
- **Extended hours**: prezzi pre-market e after-hours con rispettivo P&L
- **Persistenza**: dati salvati in `~/Library/Application Support/StockBar/data.json`; nessun dato inviato a server esterni

## Come buildare e avviare

### Da sorgente con Swift PM

```bash
git clone https://github.com/simonsruggi/StockBar.git
cd StockBar
swift build -c release
# Eseguibile: .build/release/StockBar
```

### Build come app bundle (Xcode)

```bash
xcodebuild -scheme StockBar -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode build
```

### Avvio rapido (sviluppo)

```bash
swift run
```

L'app non compare nel Dock (`.accessory` policy): l'icona appare nella menu bar in alto a destra.

## Note importanti

- **Nessuna API key richiesta**: Yahoo Finance non richiede autenticazione, ma usa un meccanismo cookie+crumb gestito automaticamente dal `StockService`
- **Fallback API**: se la v7 batch quote fallisce, viene usata la v8 chart API per ogni simbolo singolarmente
- **Requisiti**: Xcode 15+ e macOS 14 Sonoma o successivo
- **Firma/Entitlements**: `StockBar.entitlements` presente nella root per eventuali accessi di rete
