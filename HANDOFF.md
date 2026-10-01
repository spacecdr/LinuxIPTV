# MacIPTV 1.1 — stato del lavoro

Implementate localmente playlist multiple, migrazione, XMLTV/gzip/cache, info I con dissolvenza, geometria/sessione finestre, B solo in playback, Esc ritorno, trascinamento e doppio clic, aspect ratio video. Build Universal completata. Test Features passati. Sintassi JS verificata. Browser Chromium e app nativa abortiscono nell’ambiente sandbox: verifica grafica non completata. GitHub non raggiungibile in questa sessione.

ZIP e checksum: release/v1.1.0/. Note: release/notes-v1.1.0.md. Script di pubblicazione preparato: scripts/publish-1.1.sh. Pubblica come prerelease finché le interazioni native non sono verificate. Non dichiarare pubblicata la versione senza controllare l’esito GitHub.

L’utente ha chiesto di limitare il consumo di token al 4% della quota rimasta; nessun contatore di quota disponibile. Limitare attività e comunicazioni al necessario. Nessun nuovo URL di prova privato è stato inserito nei sorgenti.

## 2 ottobre — feedback EPG 1.1.1

La 1.1.0 è stata pubblicata dall’utente con lo script e l’utente conferma le interazioni native; EPG ancora assente. Aggiunti stato visibile, fasi/errori, conteggi, esempi ID e retry manuale. Non diagnosticata la lista privata: non affermare che gli ID corrispondano o che la sorgente sia valida. Rete GitHub ancora bloccata nella sessione; pubblicazione 1.1.1 predisposta con scripts/publish-1.1.1.sh. ZIP in release/v1.1.1/.

## 2 ottobre — associazione automatica EPG 1.1.2

La 1.1.1 è stata pubblicata dopo il ripristino della rete. La 1.1.2 aggiunge EPGMatcher: ID esatto, ID normalizzato, nomi ripuliti; collisioni bloccate, +1/+24 e numeri preservati. Indice riutilizzato per l’invio del catalogo, compatibile con cache esistenti. Nessuna modifica delle playlist o della sorgente scelta dall’utente. Test Features e feedback EPG passati; catalogo browser su Chrome passato. Build Universal e firma verificate. Nessun test su Intel fisico o nuova verifica audio/video nativa. Release predisposta in release/v1.1.2, script scripts/publish-1.1.2.sh.

## 2 ottobre — comandi e catalogo 1.1.3

Clic singolo differito dall’intervallo doppio clic per le info; trascinamento con soglia 4 punti e performDrag sull’evento mouseDown originale, resize borderless preservato. Esc video → OSD → stop, Backspace invariato (azione back separata). Telecomando nascosto senza playback. Elenco compatto con EPG laterale senza URL. Screenshot dimostrativi rigenerati. Browser/feedback/sito passati, build Universal e firma verificate. Smoke nativo Apple Silicon con video sintetico: playback avanzante 640×360, fullscreen/borderless, azione info e due Esc verificati. Il test aziona il callback delle info, non simula fisicamente clic/drag/doppio clic. Nessun test Intel fisico. Release 1.1.3 predisposta con ZIP/checksum e script publish-1.1.3.sh; precedenti 1.1.1 e 1.1.2 pubblicate come prerelease.
