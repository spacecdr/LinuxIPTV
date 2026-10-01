# MacIPTV 1.1.1 — Feedback EPG

Aggiunto il riquadro EPG con stato immediato e dettagli espandibili, visibile anche durante il video:

- Download, decompressione/parsing, guida caricata oppure errori specifici HTTP, DNS, timeout, HTTPS, gzip/XMLTV.
- Conteggi di canali con tvg-id, canali associati, programmi e canali con programmazione attuale/successiva.
- Data della guida e indicazione della copia salvata se il download fallisce.
- Esempi di ID non associati e ID della guida, senza mostrare gli URL di accesso.
- Riprova EPG per aggiornare subito senza attendere il ciclo automatico.

Build Universal macOS 13+, firma locale non notarizzata. Test mirati del feedback e della logica EPG; verifica grafica nativa non completata nell’ambiente ristretto. Nessuna modifica del motore video o dei dati privati. La presenza del tvg-id nell’M3U non garantisce che corrisponda all’ID usato dalla sorgente XMLTV.
