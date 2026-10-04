# LinuxIPTV — stato del port

Port Linux derivato da MacIPTV commit `b6e40fde4d6907cc5c387afe43331f8a8d58de4b`.
Codice in `Linux/`, pagine originali in `Resources/`, launcher `linuxiptv`.

Verifiche eseguite su Ubuntu 24.04 x86_64, sessione Wayland/XWayland:

- 8 test core: M3U con 10.000 canali, encoding, URL relativi/header/ID, limiti download HTTP, conservazione su errori, permessi, isolamento preferiti, XMLTV/gzip/timezone, ambiguità, scarto risultati EPG obsoleti.
- Test browser originali: catalogo con 6.442 canali, navigazione, layout, preferiti, modali e feedback EPG.
- Test nativo da file e da HTTP locale, anche sull’installazione per utente: frame/video avanzante, composizione del menu, info/telecomando, fullscreen, flottante/ritorno, doppio Esc e regressione fullscreen dopo stop.
- Pacchetto Debian generato con dipendenze di sistema; sorgenti e checksum in `dist/` (ignorata da Git).

Nessuna playlist personale usata. Screenshot Linux soltanto con catalogo, guida e video sintetici. Audio mantenuto muto nelle verifiche; ascolto, provider reali, altre distribuzioni/architetture e prestazioni 4K non certificati.

Gli appunti Mac precedenti sono archiviati in `docs/HANDOFF-MacIPTV.md`; non rappresentano verifiche del port Linux.

## Correzione audio — Linux 1.2.0+linux2

Riprodotto volume effettivo 0 e muto 1, nonostante la UI indicasse audio attivo: il mixer ripristinava lo stato degli smoke test dopo i setter iniziali. Aggiunti bootstrap audio dopo l’avvio della traccia, identificatore LinuxIPTV separato e output dummy per gli smoke test. Test PCM su sink virtuale: segnale presente in riproduzione e dopo cambio canale, zero con muto/volume zero; nessun flusso del mixer creato dai test silenziosi. Nessuna playlist personale utilizzata nelle verifiche.
