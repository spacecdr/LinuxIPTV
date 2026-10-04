# Sviluppo LinuxIPTV

Il port vive in `Linux/` e riusa senza modifiche `Resources/index.html`, `info.html` e `panorama.svg`. Il nome LinuxIPTV viene applicato dal contenitore Linux a caricamento completato. I sorgenti Swift e `build.sh` originali rimangono disponibili per il Mac; istruzioni storiche in [docs/DEVELOPMENT-MacIPTV.md](docs/DEVELOPMENT-MacIPTV.md).

- `core.py`: M3U, SHA-256 compatibile con MacIPTV, archivio atomico, XMLTV/gzip e matching.
- `epg.py`: aggiornamenti in background, cache per playlist/sorgente e scarto dei risultati obsoleti.
- `player.py`: binding ctypes con firme esplicite LibVLC 3, operazioni serializzate fuori dal thread UI e frame Cairo per la composizione degli overlay.
- `app.py`: GTK/WebKit, bridge JavaScript originale, finestre, tastiera, file chooser, sessione, info e telecomando.
- `smoke.py`: verifica nativa isolata; dati temporanei e audio muto.
- `install.py`: installazione per utente e staging Debian.

Il backend GTK è X11, disponibile anche in una sessione Wayland attraverso XWayland. Le pagine WebKit sono locali, con CSP originale e navigazione bloccata verso altre pagine; le playlist non possono eseguire HTML. Loghi remoti HTTP/HTTPS restano consentiti. Non stampare URL privati nei log. I worker di rete non modificano GTK e le risposte obsolete sono scartate.

## Verifiche

```sh
python3 -m unittest discover -s Tests/linux -v
npm install --no-save --package-lock=false playwright@1.51.1
CHROME_PATH=/usr/bin/google-chrome node Tests/browser.cjs
CHROME_PATH=/usr/bin/google-chrome node Tests/EPGFeedback.cjs
```

Per Chromium distribuito da Playwright: `npx playwright install chromium` e ometti `CHROME_PATH`. La versione di test 1.51.1 funziona anche con Node 18; non è una dipendenza dell’app.

Test GTK/LibVLC, da una sessione grafica:

```sh
mkdir -p build
ffmpeg -f lavfi -i testsrc2=size=640x360:rate=25 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 60 -c:v mpeg2video -q:v 4 -c:a mp2 build/linux-fixture.ts
./linuxiptv --smoke-test --fixture build/linux-fixture.ts --screenshot-dir build/screenshots
```

Il test esce con codice diverso da zero in caso di errore o timeout. Importa una playlist locale sintetica tramite il percorso reale dell’app, carica XMLTV, interagisce con il bridge HTML e verifica il motore e le finestre. I test core verificano anche download HTTP locale, redirect, limiti, errori, ID, isolamento, persistenza e matching EPG.

Non usare dati personali negli screenshot o nei commit. Non dichiarare verificati ascolto audio, gesti fisici o hardware non effettivamente provati.

## Pacchetti

```sh
./build-linux.sh
sudo apt install ./dist/linuxiptv_1.2.0+linux1_all.deb
```

Output: `.deb`, archivio sorgenti `.tar.xz` e `SHA256SUMS` in `dist/`, esclusa da Git. Il pacchetto contiene Python e risorse; le librerie e i codec vengono risolti da `apt`, senza scaricamenti opachi al primo avvio. Lo script richiede `dpkg-deb`, `tar`, `xz`, `git`, Python 3 e gli strumenti standard di shell.
