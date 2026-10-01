Prima release pubblica di **MacIPTV**, player IPTV standalone per **macOS 13+**, compilato Universal per **Intel e Apple Silicon**.

### Download

Scarica **MacIPTV-universal.zip**, estrai l’archivio e copia **MacIPTV.app** in Applicazioni. Il motore VLC 3.0.24 è già incluso: non servono installazioni aggiuntive per il player interno.

### Funzionalità

- Liste M3U da file o URL, aggiornamento ed esportazione.
- Gruppi, ricerca, griglia/elenco, link e preferiti persistenti.
- Riproduzione interna con volume, muto, pausa e buffer; VLC esterno opzionale.
- Navigazione con frecce, Invio, Esc e Backspace.
- Invio durante il video: catalogo semitrasparente, con filtri e selezione conservati.
- F: fullscreen/finestra. B: finestra senza bordi, ridimensionabile e sempre in primo piano.

### Requisiti e stato

macOS 13 Ventura o successivo e una propria lista M3U con stream accessibili. Nessun canale, abbonamento, playlist privata o credenziale è incluso. EPG, registrazione e DRM non sono implementati.

**Firma locale ad hoc, senza notarizzazione Apple.** Se macOS blocca il primo avvio, verifica Privacy e sicurezza → Apri comunque dopo il tentativo di apertura. Non disattivare Gatekeeper.

Riproduzione e transizioni native provate su Apple Silicon. La build Intel è presente e verificata strutturalmente, ma la prova su hardware Intel fisico resta da effettuare.

### File allegati

- `MacIPTV-universal.zip`: applicazione pronta da installare.
- `SHA256SUMS.txt`: checksum dell’app e dell’archivio sorgenti VLC.
- `vlc-3.0.24.tar.xz`: sorgenti del motore VLC incorporato; ricette e riferimenti delle dipendenze in `contrib/src/`.
- I sorgenti MacIPTV sono disponibili nel tag e negli archivi Source code generati da GitHub.

[Pagina del progetto](https://spacecdr.github.io/MacIPTV/) · [Guida e comandi](https://github.com/spacecdr/MacIPTV#comandi) · [Licenze e dipendenze](https://github.com/spacecdr/MacIPTV/blob/main/THIRD_PARTY.md)
