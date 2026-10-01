# Sviluppo di MacIPTV

## Build

Richiede macOS, Command Line Tools di Apple, Swift e un SDK in grado di compilare le architetture arm64 e x86_64.

```sh
git clone https://github.com/spacecdr/MacIPTV.git
cd MacIPTV
./build.sh
```

L’output è `dist/MacIPTV.app`. Alla prima esecuzione lo script scarica VLC 3.0.24 Universal dal sito ufficiale e ne copia runtime, codec e risorse. `vendor/`, `build/` e `dist/` sono esclusi dal repository. Lo script crea entrambi i binari con deployment macOS 13, li unisce con `lipo` e firma il bundle ad hoc.

Puoi scegliere l’SDK con `IPTV_SDK=/percorso/MacOSX.sdk ./build.sh`. La build iniziale usa Swift 6.4 in modalità Swift 5 e SDK macOS 26.5. Se presente, lo script preferisce questo SDK; altrimenti usa quello selezionato da `xcrun`. La directory `vendor/mount` può restare montata dopo il primo download: al termine si può smontare con `hdiutil detach "$PWD/vendor/mount"`.

Il toolchain macOS 27 usato per la prima release non contiene tutte le librerie di back-deployment Intel per macOS 12: non abbassare il deployment senza verificare il toolchain. Con deployment 13 il linker può segnalare l’assenza della slice Intel dell’archivio opzionale swiftCompatibilityPacks; il progetto non usa parameter packs e il collegamento termina senza simboli irrisolti.

## Struttura

- `Sources/Catalog.swift`: parser M3U, identificatori e persistenza.
- `Sources/main.swift`: AppKit, bridge WKWebView, player e modalità finestra.
- `Sources/VLCBridge.h`: dichiarazioni C delle API LibVLC utilizzate.
- `Resources/index.html`: catalogo e navigazione da tastiera.
- `Tests/`: parser, test del catalogo e generatore dell’icona.
- `scripts/`: generazione delle immagini pubbliche e verifiche del sito.
- `docs/`: sito GitHub Pages e immagini dimostrative.

Le operazioni bloccanti di LibVLC sono serializzate fuori dal main thread. L’interfaccia resta nello stesso NSWindow del video. I dati usano la directory `Application Support/IPTVMac`, conservata anche dopo il cambio del nome pubblico dell’app.

## Test

Parser e persistenza:

```sh
mkdir -p build
xcrun swiftc -swift-version 5 Sources/Catalog.swift Tests/main.swift -o build/catalog-tests
./build/catalog-tests
```

Catalogo nel browser:

```sh
npm install --no-save --package-lock=false playwright
npx playwright install chromium
node Tests/browser.cjs
```

`PLAYWRIGHT_MODULE` permette di usare un’installazione esistente; `CHROME_PATH` sceglie un eseguibile Chrome/Chromium. Il test usa 6.442 canali sintetici. Nessun server IPTV o dato dell’utente è necessario.

Player nativo, con un video locale oppure un URL di test autorizzato:

```sh
"dist/MacIPTV.app/Contents/MacOS/MacIPTV" --smoke-test --fixture /percorso/video.ts
```

Lo smoke test usa una directory temporanea, azzera il volume, verifica stato e avanzamento video, catalogo, fullscreen e finestra flottante; poi chiude l’app. `--windowed` permette un avvio normale in finestra. I test non devono usare playlist personali nei file pubblici.

## Verifiche della prima release

Parser con 10.000 canali; catalogo con 6.442 canali, 159 gruppi, filtri, stelle, tastiera, pagine, viste e layout da 420 a 1280 px. Riproduzione nativa Apple Silicon da file, HTTP locale e HTTPS, con output video presente e tempo avanzante. Transizioni fullscreen/floating e chiusura completate. Firma del bundle verificata con `codesign`; binario Universal verificato con `lipo`.

Il test Intel su hardware fisico non è stato effettuato. Le prove native verificano lo stato del motore e della finestra; non costituiscono una verifica acustica o una cattura dell’intero desktop. Le immagini pubbliche sono render del catalogo reale con dati sintetici; sfondi video e schema flottante sono illustrativi.

## Rilasci

Lo ZIP dell’app va allegato alle GitHub Releases, non aggiunto alla cronologia Git. Pubblicare checksum SHA-256, note, licenze e accesso ai sorgenti delle dipendenze. La release 1.0.0 non è notarizzata: una distribuzione notarizzata richiede un account Apple Developer e la firma del titolare.

## Versione 1.1.0

Nuovi moduli Library (multi-playlist e migrazione), EPG (XMLTV/cache), Playlists (gestione), Windows (geometria/sessione), Info (overlay separato) e VideoSupport.c (SAR/gzip). `Tests/Features/main.swift` copre scoperta guida, ID, timezone, programmi, migrazione e isolamento preferiti.

In questa sessione l’ambiente limita rete e avvio GUI: il browser Chromium termina all’avvio. Non presentare i test grafici della 1.0 come verifica completa della 1.1. La pubblicazione GitHub richiede il ripristino dell’accesso di rete.
