# MacIPTV 1.1.2 — Associazione EPG automatica

La playlist resta invariata. MacIPTV cerca prima l’ID esatto, poi confronta gli ID ignorando maiuscole, spazi, punti, trattini e underscore. Se necessario, confronta i nomi ripulendo i prefissi italiani IT-/IT|/IT: e i suffissi di qualità separati SD/HD/FHD/UHD/4K/H264/H265/HEVC.

Gli abbinamenti automatici richiedono un unico canale della guida. Ambiguità e nomi discordanti non vengono risolti arbitrariamente. Numeri e +1/+24 restano distinti. Il pannello EPG distingue ID esatti, ID normalizzati, associazioni per nome, ambigui e mancanti. Le guide già in cache restano compatibili; nessuna nuova sorgente viene imposta.

Build Universal Intel/Apple Silicon, macOS 13+, firma locale non notarizzata. Verificati abbinamenti, collisioni, timeshift, cache e feedback EPG con test mirati. Nessuna modifica al motore video.
