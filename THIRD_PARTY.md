# Componenti di terze parti

MacIPTV è distribuito con licenza GPL-3.0-or-later. Il player incorpora le librerie dinamiche, i plugin e le risorse della distribuzione ufficiale **VLC 3.0.24 Universal per macOS**, senza modifiche al loro codice.

- [Distribuzione binaria originale](https://download.videolan.org/vlc/3.0.24/macosx/vlc-3.0.24-universal.dmg)
- [Sorgenti VLC 3.0.24](https://download.videolan.org/vlc/3.0.24/vlc-3.0.24.tar.xz), disponibili anche come allegato della release MacIPTV v1.0.0.
- [Archivio sorgenti delle dipendenze contrib di VideoLAN](https://download.videolan.org/pub/videolan/contrib/)
- Le ricette, versioni, URL degli archivi e checksum delle dipendenze si trovano in `contrib/src/` nell’archivio dei sorgenti VLC; gli script di compilazione macOS sono in `extras/package/macosx/`.
- [Informazioni sulle licenze di VideoLAN](https://www.videolan.org/legal.html)

LibVLC e libvlccore sono LGPL-2.1-or-later; i plugin includono componenti GPL e librerie con altre licenze. I file `COPYING`, `COPYING.LIB`, `THANKS` e gli avvisi nei sorgenti upstream descrivono i rispettivi titolari e condizioni. Le copie GPL e LGPL e gli avvisi del bundle sono in `Resources/`.

MacIPTV non usa il plugin dell’interfaccia completa di VLC, che dipende da Sparkle, né il plugin delle vecchie notifiche Growl. Questi due file vengono esclusi dal bundle. Sei plugin SIMD sono specifici di Intel; gli altri componenti necessari includono entrambe le architetture. Il collegamento a LibVLC è dinamico: è possibile sostituire le librerie con versioni compatibili modificate e ricompilare/firmare localmente l’app con `build.sh`.

AppKit, WebKit, Foundation e CryptoKit sono framework di sistema Apple, non copiati nel pacchetto. Playwright è usato soltanto negli strumenti di test, non nell’app.

Icona e sfondi dimostrativi sono disegni originali del progetto. I canali nelle immagini sono inventati e gli URL usano `example.org`. Nessun logo televisivo, playlist privata o contenuto del canale di prova viene pubblicato. MacIPTV non è un prodotto ufficiale VideoLAN e non implica un’affiliazione con VideoLAN o Apple.
