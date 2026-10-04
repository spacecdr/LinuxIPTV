"""Background EPG downloads with source-sensitive cache and stale-result protection."""
import hashlib
import time
from core import EPG_LIMIT, fetch, guide_urls, parse_xmltv


class EPGService:
    def __init__(self, store, work, changed):
        self.store, self.work, self.changed = store, work, changed
        self.guides, self.states, self.tokens, self.fingerprints, self.attempts = {}, {}, {}, {}, {}
        self.busy = set()

    def cancel(self, identity):
        self.tokens[identity] = self.tokens.get(identity, 0) + 1
        for mapping in [self.guides, self.states, self.fingerprints, self.attempts]:
            mapping.pop(identity, None)
        self.busy.discard(identity)

    def refresh(self, playlist, force=False):
        identity, urls = playlist['id'], guide_urls(playlist)
        fingerprint = hashlib.sha256('\n'.join(urls).encode()).hexdigest()[:16]
        if self.fingerprints.get(identity) != fingerprint:
            self.cancel(identity)
            self.fingerprints[identity] = fingerprint
        if not urls:
            self.states[identity] = 'Nessuna sorgente EPG: configura un URL XMLTV in Modifica lista'
            self.changed()
            return
        if identity in self.busy or (not force and time.time() - self.attempts.get(identity, 0) < 3600):
            return
        token = self.tokens[identity] = self.tokens.get(identity, 0) + 1
        self.busy.add(identity)
        self.attempts[identity] = time.time()
        self.states[identity] = 'Scaricamento e lettura XMLTV…'
        self.changed()
        cache = f'epg-{identity}-{fingerprint}.json'

        def load():
            try:
                saved = self.store.load(cache)
            except (ValueError, OSError):
                saved = None
            merged = dict(programmes={}, names={}, fetched=time.time())
            successes, failures = 0, []
            for index, address in enumerate(urls):
                try:
                    data, _ = fetch(address, EPG_LIMIT)
                    parsed = parse_xmltv(data)
                    for key, values in parsed['programmes'].items():
                        merged['programmes'].setdefault(key, values)
                    for key, values in parsed['names'].items():
                        merged['names'][key] = sorted(set(merged['names'].get(key, []) + values))
                    successes += 1
                except Exception:
                    failures.append(f'Fonte {index + 1}: download o XMLTV non valido')
            if successes:
                self.store.save(cache, merged)
                return merged, 'Guida caricata' if not failures else 'Guida parziale · ' + ' · '.join(failures)
            return saved, ('Guida salvata in uso · ' if saved else 'Errore EPG · ') + ' · '.join(failures)

        def done(result, error):
            if self.tokens.get(identity) != token:
                return
            self.busy.discard(identity)
            if error:
                self.states[identity] = 'Impossibile aggiornare o salvare la guida.'
            else:
                guide, status = result
                if guide:
                    self.guides[identity] = guide
                self.states[identity] = status
            self.changed()
        self.work(load, done)
