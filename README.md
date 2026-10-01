# MacIPTV

**Liste M3U, canali e preferiti. La tua IPTV sul Mac, con il player già incluso.**

[Scarica per Intel e Apple Silicon](https://github.com/spacecdr/MacIPTV/releases/tag/v1.1.3) · [Pagina del progetto](https://spacecdr.github.io/MacIPTV/) · [Comandi](#comandi) · [Compilazione e test](DEVELOPMENT.md)

![Catalogo MacIPTV: gruppi, ricerca e canali in griglia](docs/assets/catalogo.png)

*Interfaccia reale del catalogo, renderizzata con canali dimostrativi. Nessuna playlist o credenziale è inclusa.*

MacIPTV è un’applicazione standalone per macOS: carichi una lista M3U da file o URL, scegli il canale e lo guardi direttamente sul Mac. Al primo avvio parte a schermo intero, poi ricorda la sessione; si usa anche da tastiera e può diventare una piccola finestra video senza bordi, sempre in primo piano.

## Download e installazione

1. Scarica **MacIPTV-universal.zip** dalla [release](https://github.com/spacecdr/MacIPTV/releases/tag/v1.1.3).
2. Estrai lo ZIP e trascina **MacIPTV.app** in **Applicazioni**.
3. Apri l’app e usa **Gestisci lista M3U** per caricare un file o incollare un URL.

L’archivio contiene entrambe le architetture: **Intel x86_64 e Apple Silicon arm64**. Non occorre installare VLC, Python, Homebrew o un browser. Il player utilizza il motore VLC incorporato.

L’app ha una firma locale ad hoc e **non è notarizzata Apple**. Se macOS ne impedisce l’apertura, dopo il primo tentativo verifica **Impostazioni di Sistema → Privacy e sicurezza → Apri comunque**. Non occorre disattivare Gatekeeper. I checksum della release permettono di verificare l’integrità del download.

## Funzionalità

| Funzione | Cosa puoi fare |
| --- | --- |
| Liste M3U | Importare file e URL HTTP/HTTPS, aggiornare le liste remote ed esportare la lista salvata |
| Gruppi e ricerca | Cercare gruppi e canali, vedere i conteggi e consultare pagine da 60 canali |
| Griglia o elenco | Cambiare vista; nell’elenco trovi il programma EPG, gli orari e la progressione |
| Preferiti | Aggiungere o rimuovere un canale con la stella; ritrovarlo ai prossimi avvii |
| Player integrato | Riprodurre con LibVLC, regolare volume, pausa, muto e buffer da 1 a 10 secondi |
| Menu sul video | Premere Invio per riaprire il catalogo semitrasparente, conservando filtri e selezione |
| Fullscreen e finestra | Passare da schermo intero a finestra con F |
| Solo video | Premere B per una finestra senza bordi, ridimensionabile e sempre in primo piano |
| Cambio canale | Usare CH+/CH− all’interno del gruppo, della ricerca o dei preferiti correnti |
| VLC esterno | Aprire il canale selezionato in un’installazione separata di VLC, se disponibile |

### I canali che vuoi ritrovare

![Preferiti in MacIPTV](docs/assets/preferiti.png)

La stella è separata dal pulsante di riproduzione. I preferiti vengono salvati sul Mac e possono essere filtrati con la ricerca.

### Programmi EPG, elenco compatto

![Vista elenco di MacIPTV](docs/assets/elenco.png)

La vista elenco affianca nome e gruppo al programma EPG, con orari e progressione, in righe compatte senza URL.

### Il catalogo resta sopra il video

![Anteprima del catalogo semitrasparente](docs/assets/menu-video.png)

*Anteprima illustrativa: l’interfaccia reale è mostrata su uno sfondo grafico dimostrativo, non su una trasmissione TV.*

Durante la riproduzione, **Invio** riapre lo stesso catalogo senza fermare il player. Seleziona un altro canale oppure torna al video. **B** attiva la finestra flottante; trascina il video per spostarla e l’angolo inferiore destro per ridimensionarla. Premendo di nuovo B ripristini la finestra precedente.

## Comandi

| Tasto | Nel catalogo | Durante il video |
| --- | --- | --- |
| ↑ ↓ ← → | Navigazione; → dai gruppi entra nei canali | ↑/↓ cambia canale; ←/→ regola il volume |
| Invio | Attiva il controllo o riproduce il canale | Riapre il menu semitrasparente |
| Esc | Nell’OSD interrompe la riproduzione | Apre l’OSD |
| Backspace | Dai canali torna ai gruppi, poi al video | Riapre il catalogo |
| F | Schermo intero / finestra | Schermo intero / finestra |
| B | Solo durante la riproduzione | Borderless / modalità precedente |
| I | Info sul canale in riproduzione | Info con dissolvenza e chiusura dopo 5 secondi |
| Spazio | Pausa / riprendi | Pausa / riprendi |
| M | Audio / muto | Audio / muto |
| S | Stop | Stop |
| P | Preferito del canale selezionato | — |
| / | Cerca un canale | — |
| Cmd+O | Apri lista | Apri lista |
| Cmd+L | Catalogo | Catalogo |
| Cmd+Q | Esci | Esci |

Nei campi di testo, frecce e Backspace mantengono il normale comportamento di modifica; Esc torna alla navigazione. Tab e Shift+Tab raggiungono gli altri controlli. Nella modalità senza bordi, doppio clic sul video alterna fullscreen e modalità precedente.

## Requisiti

- **macOS 13 Ventura o successivo**, su Mac Intel o Apple Silicon.
- Una lista M3U con canali accessibili e formati supportati da VLC.
- Connessione al server della lista e dei canali. La lista può essere un file locale.
- VLC installato separatamente **solo** se vuoi usare il player esterno.

Limite della lista: **20 MB**. Un’importazione invalida conserva la lista precedente. Le liste importate da file vanno ricaricate per aggiornarle. Il comportamento di un canale dipende dal provider; non sono inclusi canali, abbonamenti, registrazione o supporto DRM.

**Stato delle verifiche della versione 1.0:** riproduzione nativa e transizioni finestra/fullscreen/flottante provate su Apple Silicon. La build e i componenti necessari contengono le architetture Intel e ARM; la prova su un Mac Intel fisico resta da effettuare. Il livello flottante è soggetto alle finestre riservate di macOS. Usando VLC esterno, finestra e comandi sono gestiti da VLC.

## Tecnologie

| Componente | Tecnologia |
| --- | --- |
| Applicazione e finestre | Swift, AppKit / Cocoa |
| Catalogo e menu | WKWebView locale, HTML, CSS e JavaScript |
| Video e audio | LibVLC 3.0.24 con runtime e codec incorporati |
| Importazione remota | Foundation URLSession |
| Dati locali | JSON, scrittura atomica, permessi privati |
| Identificatori dei canali | SHA-256 con CryptoKit |
| Build Universal | swiftc, lipo e codesign |
| Sito del progetto | HTML/CSS statici su GitHub Pages |

L’app non avvia un server web e non richiede servizi cloud propri. La WKWebView è integrata in macOS: l’interfaccia non dipende da Chrome o Safari installati come applicazioni separate.

## Dati locali

Lista e preferiti sono in `~/Library/Application Support/IPTVMac/`. Gli URL possono contenere credenziali: non condividere i file salvati o screenshot con indirizzi personali. La navigazione usa i server indicati dalla lista per playlist, stream e loghi. I metadati sono trattati come testo, non come codice HTML.

## Sviluppo e licenze

Consulta [DEVELOPMENT.md](DEVELOPMENT.md) per build, test e struttura del progetto. Il codice dell’app è distribuito con licenza **GPL-3.0-or-later**. VLC e le sue dipendenze conservano le rispettive licenze: dettagli, sorgenti e riferimenti in [THIRD_PARTY.md](THIRD_PARTY.md).

## Novità della versione 1.1.0

- **I / informazioni:** nome, logo, dimensioni effettive del video e categoria SD/HD/Full HD/UHD quando applicabile. Non vengono attribuite sigle progressive/interlacciate se il motore non le rende disponibili. Programma attuale, descrizione, orari e programma successivo quando presenti. Dissolvenza, chiusura automatica dopo 5 secondi o premendo di nuovo I.
- **EPG in background:** scoperta degli URL XMLTV tramite `x-tvg-url`, `url-tvg` o `tvg-url` dell’M3U. URL personalizzabile dalla modifica della lista. Supporto XML e gzip, cache locale, aggiornamento periodico senza attesa per navigazione o playback. Nessuna registrazione o servizio aggiuntivo. Se manca una guida, non vengono inventati programmi. Associazione tramite `tvg-id`, oppure nome esatto non ambiguo. In catalogo: titolo, orari e progressbar; descrizione soltanto nelle informazioni.
- **Più playlist:** + aggiunge una lista; con almeno due liste compare il selettore. Modifica nome/sorgente/guida, aggiorna, esporta e rimuovi con conferma. Preferiti e stato di navigazione separati. La copia offline riguarda il catalogo, non i flussi video remoti. Migrazione automatica della precedente lista e dei preferiti.
- **OSD essenziale:** gestione delle liste nascosta durante la riproduzione; il selettore resta utilizzabile per consultare altri cataloghi.
- **Finestre:** primo avvio fullscreen; successivamente modalità, posizione e dimensioni vengono ricordate. Una sessione chiusa in borderless riparte in finestra normale. La geometria borderless viene conservata separatamente. Finestre riportate nell’area dei monitor disponibili.
- **B solo durante il video**, senza pulsante Solo video. Esc dal borderless torna alla modalità precedente. Clic tenuto sul video trascina la finestra normale o borderless senza aprire l’OSD. Doppio clic alterna fullscreen e modalità precedente. Invio apre il catalogo.
- **Ridimensionamento proporzionale:** durante il video il rapporto include il pixel aspect ratio; senza riproduzione il ridimensionamento è libero. Nessuna riproduzione automatica alla riapertura.

**Verifica 1.1:** build Universal e test mirati di XMLTV, migrazione e più playlist completati. Test browser e nativi non completati a causa delle restrizioni dell’ambiente corrente; trattare questa build come anteprima.

## 1.1.1 — Feedback EPG

Il riquadro **EPG**, sotto la gestione della playlist e visibile anche nell’OSD, mostra subito stato e conteggi. Aprilo per i dettagli: fonti, canali con tvg-id, canali associati, programmi presenti, canali con programmi attuali/successivi, data della copia utilizzata ed esempi di ID non associati. **Riprova EPG** forza un nuovo tentativo senza aspettare un’ora.

Gli errori distinguono HTTP, timeout/DNS/HTTPS, file non leggibile, gzip non valido e XMLTV non valido. Gli URL con credenziali non vengono riportati nei messaggi. Un download riuscito non implica che i canali abbiano programmi nell’orario attuale: associazione e copertura temporale sono conteggiate separatamente.

## 1.1.2 — Associazione EPG automatica

La playlist resta invariata. MacIPTV cerca prima l’ID esatto, poi confronta gli ID ignorando maiuscole, spazi, punti, trattini e underscore. Se necessario, confronta i nomi ripulendo i prefissi italiani IT-/IT|/IT: e i suffissi di qualità separati SD/HD/FHD/UHD/4K/H264/H265/HEVC.

Gli abbinamenti automatici richiedono un unico canale della guida. Ambiguità e nomi discordanti non vengono risolti arbitrariamente. Numeri e +1/+24 restano distinti. Il pannello EPG distingue ID esatti, ID normalizzati, associazioni per nome, ambigui e mancanti. Le guide già in cache restano compatibili; nessuna nuova sorgente viene imposta.

Build Universal Intel/Apple Silicon, macOS 13+, firma locale non notarizzata. Verificati abbinamenti, collisioni, timeshift, cache e feedback EPG con test mirati. Nessuna modifica al motore video.

## 1.1.3 — Comandi e catalogo compatto

- Clic singolo sul video: informazioni del canale. Trascinamento e ridimensionamento non attivano le info; doppio clic mantiene fullscreen/ritorno. Il clic singolo attende l’intervallo del doppio clic.
- Esc dal video apre l’OSD, anche in borderless; Esc nell’OSD interrompe la riproduzione. Backspace conserva la navigazione precedente. B resta disponibile per uscire dal borderless.
- Telecomando nascosto quando non è selezionato un canale in riproduzione.
- Vista elenco compatta: nome/gruppo affiancati al programma EPG, orari e progressione. Rimossi gli URL dalle righe. Descrizioni dei programmi soltanto nelle info.

Build Universal Intel/Apple Silicon, macOS 13+, firma locale non notarizzata.
