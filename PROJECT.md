# StockBar

App macOS per la menu bar che mostra in tempo reale le quotazioni di borsa e il P&L del portafoglio. Non richiede account né API key: i dati vengono direttamente da Yahoo Finance.

## Descrizione

StockBar è un'app leggera che vive nella menu bar di macOS. Con un click sull'icona si apre un popover con watchlist, portafogli e impostazioni. I prezzi si aggiornano in tempo reale via WebSocket (~1 update/sec per simbolo).

## Stack tecnologico

- **Linguaggio**: Swift 5.9
- **UI**: SwiftUI
- **Piattaforma**: macOS 14+ (Sonoma)
- **Build system**: Swift Package Manager (`Package.swift`)
- **Dati real-time**: Yahoo Finance WebSocket (`wss://streamer.finance.yahoo.com`) via protobuf
- **Dati fallback**: Yahoo Finance REST API (v7 batch quotes + v8 chart)
- **Dipendenze**: [apple/swift-protobuf](https://github.com/apple/swift-protobuf) (decodifica messaggi WSS)

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
│   │   ├── StockService.swift      # Fetch quotazioni e tassi di cambio da Yahoo Finance REST
│   │   ├── WebSocketService.swift  # Streaming real-time via WSS + protobuf + auto-reconnect
│   │   ├── yaticker.pb.swift       # Codice Swift generato da yaticker.proto
│   │   └── StorageService.swift    # Persistenza locale (JSON in Application Support)
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
- **Watchlist**: aggiunta titoli per simbolo, nome o ISIN con ricerca live; prezzi in valuta originale o convertiti; badge PRE/POST per extended hours; filtro locale per nome, simbolo o ISIN
- **Portafogli multipli**: prezzo medio di carico, data acquisto per tasso di cambio storico, P&L per holding e totale
- **Conversione valuta**: supporta EUR, USD, GBP, CHF, JPY, CAD, AUD; tassi di cambio live e storici
- **Extended hours**: prezzi pre-market e after-hours con rispettivo P&L
- **Persistenza**: dati salvati in `~/Library/Application Support/StockBar/data.json` (watchlist, portafogli, isinMap, preferenze); nessun dato inviato a server esterni
- **Menu bar reattiva**: si aggiorna immediatamente ad ogni modifica di portafoglio, impostazioni o chiusura popover (oltre ai tick WebSocket e REST polling)

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

## Architettura dati

- **WebSocket (primario)**: `WebSocketService` si connette a `wss://streamer.finance.yahoo.com/?version=2`, riceve tick in formato JSON-wrapped base64 protobuf. I tick vengono bufferizzati e flushati in batch 1 volta al secondo per evitare SwiftUI redraw eccessivi.
- **REST polling (secondario)**: ogni 5 min per exchange rates (correnti e storici). Usato anche come bootstrap iniziale e fallback se il WSS cade.
- **Cache eviction**: ad ogni refresh REST, vengono rimossi quotes, exchange rates e historical rates non più necessari.
- **Sleep/Wake**: il WSS si disconnette su system sleep e si riconnette al wake con refresh immediato.
- **Auto-reconnect**: backoff esponenziale (2s, 4s, 8s... max 120s) in caso di disconnessione WSS.

## Note importanti

- **Nessuna API key richiesta**: Yahoo Finance non richiede autenticazione, ma usa un meccanismo cookie+crumb gestito automaticamente dal `StockService`
- **Fallback API**: se la v7 batch quote fallisce, viene usata la v8 chart API per ogni simbolo singolarmente
- **Protobuf**: lo schema `yaticker.proto` nella root genera `yaticker.pb.swift` via `protoc --swift_out`. Rigenerare se cambia lo schema: `protoc --swift_out=StockBar/Services/ yaticker.proto`
- **Requisiti**: Xcode 15+ e macOS 14 Sonoma o successivo
- **Firma/Entitlements**: `StockBar.entitlements` presente nella root per eventuali accessi di rete
