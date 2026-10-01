# MacIPTV 1.1.4 — Correzione crash fullscreen

Corretto il crash al ritorno in finestra dopo lo stop del video e successivi passaggi fullscreen/finestra, tramite F o pulsante. Il ripristino del ridimensionamento libero ora usa gli incrementi della finestra anziché impostare un rapporto 0:0, che poteva produrre un’altezza NaN in AppKit. Il rapporto proporzionale durante il video resta attivo.

Aggiunta regressione nativa con due cicli fullscreen/finestra dopo Esc/OSD/stop, controllo delle dimensioni e del ridimensionamento libero.

Build Universal Intel/Apple Silicon, macOS 13+, firma locale non notarizzata.
