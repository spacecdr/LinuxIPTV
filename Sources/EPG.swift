import Foundation
import CryptoKit

struct Programme: Codable {
    var title: String
    var description: String
    var start: Date
    var end: Date?
}
enum EPGMatchKind: String { case exactID, normalizedID, name, ambiguous, missing }
struct EPGMatch {
    let id: String?
    let kind: EPGMatchKind
}
struct EPGMatcher {
    let known: Set<String>
    private var ids: [String: Set<String>] = [:]
    private var names: [String: Set<String>] = [:]
    // Keep '+' and digits: time-shift channels must never collapse into the original.
    static func idKey(_ value: String) -> String {
        String(value.lowercased().filter { !$0.isWhitespace && !".-_".contains($0) })
    }
    static func nameKey(_ value: String) -> String {
        var s = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: #"^(?:it|it-it|italia|italy)\s*[-|:]\s*"#, with: "", options: .regularExpression)
        // Only terminal, separated quality tokens; never remove channel numbers or +1/+24.
        let quality = #"\s+(?:sd|hd|fhd|full\s*hd|uhd|4k|h[.]?26[45]|hevc)\s*$"#
        while true {
            let next = s.replacingOccurrences(of: quality, with: "", options: .regularExpression)
            if next == s { break }; s = next
        }
        return idKey(s)
    }
    init(_ guide: Guide) {
        known = Set(guide.programmes.keys).union(guide.names.values.flatMap { $0 })
        for id in known where !Self.idKey(id).isEmpty { ids[Self.idKey(id), default: []].insert(id) }
        for (name, values) in guide.names where !Self.nameKey(name).isEmpty {
            names[Self.nameKey(name), default: []].formUnion(values)
        }
    }
    func match(_ channel: Channel) -> EPGMatch {
        let id = channel.tvgID ?? ""
        if !id.isEmpty && known.contains(id) { return EPGMatch(id: id, kind: .exactID) }
        if !id.isEmpty, let candidates = ids[Self.idKey(id)] {
            return candidates.count == 1 ? EPGMatch(id: candidates.first, kind: .normalizedID) : EPGMatch(id: nil, kind: .ambiguous)
        }
        // Consider both names together: conflicting metadata is ambiguous, not first-wins.
        var candidates = Set<String>()
        for name in [channel.tvgName ?? "", channel.name] {
            candidates.formUnion(names[Self.nameKey(name)] ?? [])
        }
        if candidates.count == 1 { return EPGMatch(id: candidates.first, kind: .name) }
        return EPGMatch(id: nil, kind: candidates.isEmpty ? .missing : .ambiguous)
    }
}

struct Guide: Codable {
    var programmes: [String: [Programme]]
    var names: [String: [String]]
    var fetched = Date()
    func channelID(_ channel: Channel) -> String? { EPGMatcher(self).match(channel).id }
    func schedule(_ channel: Channel, now: Date = Date(), matcher: EPGMatcher? = nil) -> (Programme?, Programme?) {
        guard let id = (matcher ?? EPGMatcher(self)).match(channel).id, let list = programmes[id] else { return (nil, nil) }
        let current = list.last { $0.start <= now && ($0.end.map { now < $0 } ?? (now.timeIntervalSince($0.start) < 6 * 3600)) }
        let next = list.first { $0.start > now }
        return (current, next)
    }
}
final class XMLTV: NSObject, XMLParserDelegate {
    var guide = Guide(programmes: [:], names: [:])
    var channel = "", channelName = "", text = "", field = "", language = ""
    var programme: Programme?
    var programmeChannel = ""
    var depth = 0, fieldDepth = 0, rootSeen = false, forbidden = false
    let now: Date
    let allowedIDs: Set<String>
    var count = 0
    init(now: Date, channels: [Channel]) { self.now = now; allowedIDs = Set(channels.compactMap(\.tvgID).filter { !$0.isEmpty }) }
    static func date(_ raw: String?) -> Date? {
        guard let raw = raw else { return nil }
        let parts = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let value = parts.first, [12,14].contains(value.count), value.allSatisfy(\.isNumber) else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = value.count == 14 ? "yyyyMMddHHmmss Z" : "yyyyMMddHHmm Z"
        let zone = parts.count > 1 ? parts[1] : "+0000"
        return formatter.date(from: value + " " + zone)
    }
    static func parse(_ data: Data, channels: [Channel], now: Date = Date()) throws -> Guide {
        guard data.count <= 128 * 1024 * 1024 else { throw PlaylistError.invalid("Guida EPG troppo grande.") }
        let reader = XMLTV(now: now, channels: channels)
        let parser = XMLParser(data: data); parser.delegate = reader
        parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never
        guard parser.parse(), reader.rootSeen, !reader.forbidden else { throw PlaylistError.invalid("Guida XMLTV non valida.") }
        for (key, values) in reader.guide.programmes {
            let sorted = values.sorted { $0.start < $1.start }
            var unique: [Programme] = []
            for p in sorted where unique.last?.start != p.start { unique.append(p) }
            for i in unique.indices where unique[i].end == nil && i + 1 < unique.count { unique[i].end = unique[i+1].start }
            reader.guide.programmes[key] = unique
        }
        return reader.guide
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        depth += 1
        if depth == 1 { rootSeen = elementName == "tv" }
        if elementName == "channel" && depth == 2 { channel = a["id"] ?? "" }
        if elementName == "programme" && depth == 2 {
            programmeChannel = a["channel"] ?? ""
            if let start = Self.date(a["start"]), start < now.addingTimeInterval(3*86400), start > now.addingTimeInterval(-86400) {
                programme = Programme(title: "", description: "", start: start, end: Self.date(a["stop"]))
            } else { programme = nil }
        }
        if depth == 3 && ["display-name", "title", "desc"].contains(elementName) { field = elementName; text = ""; fieldDepth = depth; language = a["lang"] ?? "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if !field.isEmpty && text.count < 16000 { text += String(string.prefix(16000-text.count)) } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if field == elementName && depth == fieldDepth {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if field == "display-name", !channel.isEmpty { guide.names[value.lowercased(), default: []].append(channel) }
            if field == "title", programme?.title.isEmpty == true || language == "it" { programme?.title = value }
            if field == "desc", programme?.description.isEmpty == true || language == "it" { programme?.description = value }
            field = ""; text = ""
        }
        if elementName == "programme" && depth == 2, let p = programme, !p.title.isEmpty, !programmeChannel.isEmpty, p.end == nil || p.end! > now.addingTimeInterval(-3600) {
            count += 1
            if count > 300000 { parser.abortParsing(); return }
            guide.programmes[programmeChannel, default: []].append(p); programme = nil
        }
        if elementName == "channel" && depth == 2 { channel = "" }
        depth -= 1
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { forbidden = true; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { forbidden = true; parser.abortParsing() }
}

// Public entry points and published state belong to the main thread.
final class EPGService {
    let store: Store
    var guides: [String: Guide] = [:]
    var states: [String: String] = [:]
    var tasks: [String: URLSessionDownloadTask] = [:]
    var revisions: [String: UUID] = [:]
    var lastAttempt: [String: Date] = [:]
    var fingerprints: [String: String] = [:]
    var busy = Set<String>()
    var onChange: (() -> Void)?
    init(store: Store) { self.store = store }
    func publish(_ id: String, _ state: String) { states[id] = state; onChange?() }
    func cancel(_ id: String) {
        tasks[id]?.cancel(); tasks[id] = nil; revisions[id] = UUID()
        guides[id] = nil; fingerprints[id] = nil; lastAttempt[id] = nil; busy.remove(id)
    }
    static func networkMessage(_ error: Error) -> String {
        switch (error as NSError).code {
        case NSURLErrorTimedOut: return "Timeout: il server non ha risposto entro 45 secondi"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "Server EPG non trovato (DNS)"
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "Connessione Internet assente o interrotta"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate: return "Connessione HTTPS o certificato del server non valido"
        case NSURLErrorCannotConnectToHost: return "Impossibile collegarsi al server EPG"
        case NSURLErrorCancelled: return "Richiesta annullata"
        default: return "Download non riuscito (codice \((error as NSError).code))"
        }
    }
    static func diagnostics(_ playlist: Playlist, guide: Guide?, now: Date = Date()) -> [String: Any] {
        let channels = playlist.catalog.channels
        let withID = channels.filter { !($0.tvgID ?? "").isEmpty }.count
        var d: [String: Any] = ["total": channels.count, "withID": withID,
            "sourceCount": playlist.epgURLs.count, "source": playlist.epgOverride.isEmpty ? "Dalla playlist" : "XMLTV configurato",
            "matched": 0, "current": 0, "upcoming": 0, "guideChannels": 0, "programmes": 0]
        guard let guide = guide else { return d }
        let matcher = EPGMatcher(guide), known = matcher.known
        var matched = 0, current = 0, upcoming = 0, missing: [String] = []
        var counts: [String: Int] = [:]
        for c in channels {
            let id = c.tvgID ?? ""
            let match = matcher.match(c)
            counts[match.kind.rawValue, default: 0] += 1
            let associated = match.id != nil
            if associated { matched += 1 } else if missing.count < 3 { missing.append(c.name + " [" + (id.isEmpty ? "tvg-id assente" : id) + "]") }
            let pair = guide.schedule(c, now: now, matcher: matcher)
            if pair.0 != nil { current += 1 }; if pair.1 != nil { upcoming += 1 }
        }
        for kind in [EPGMatchKind.exactID, .normalizedID, .name, .ambiguous, .missing] { d[kind.rawValue] = counts[kind.rawValue] ?? 0 }
        d["matched"] = matched; d["current"] = current; d["upcoming"] = upcoming
        d["guideChannels"] = known.count; d["programmes"] = guide.programmes.values.reduce(0) { $0 + $1.count }
        d["fetched"] = guide.fetched.timeIntervalSince1970
        d["unmatchedExamples"] = missing; d["guideExamples"] = Array(known.sorted().prefix(5))
        if matched == 0 { d["hint"] = "Guida caricata, ma nessun canale associato: confronta i tvg-id con gli ID della guida." }
        else if current == 0 { d["hint"] = "Canali associati, ma nessun programma in onda adesso. La guida potrebbe non coprire l’orario attuale; verifica anche data e ora del Mac." }
        else { d["hint"] = "I programmi vengono mostrati solo per i canali associati e gli orari coperti dalla guida." }
        return d
    }
    func refresh(_ playlist: Playlist, force: Bool = false) {
        let urls = playlist.epgURLs, id = playlist.id
        let fingerprint = SHA256.hash(data: Data(urls.map(\.absoluteString).joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        if fingerprints[id] != fingerprint { cancel(id); fingerprints[id] = fingerprint }
        guard !urls.isEmpty else { publish(id, "Nessuna sorgente EPG: configura un URL XMLTV in Modifica lista"); return }
        guard force || (!busy.contains(id) && Date().timeIntervalSince(lastAttempt[id] ?? .distantPast) > 3600) else { return }
        tasks[id]?.cancel(); let token = UUID(); revisions[id] = token; lastAttempt[id] = Date(); busy.insert(id)
        let cache = "epg-\(id)-\(fingerprint.prefix(16)).json"
        publish(id, "Lettura della guida salvata e avvio aggiornamento…")
        DispatchQueue.global(qos: .utility).async {
            if let saved = try? self.store.load(cache, as: Guide.self) {
                DispatchQueue.main.async { if self.revisions[id] == token && self.guides[id] == nil { self.guides[id] = saved; self.onChange?() } }
            }
        }
        load(urls, index: 0, merged: Guide(programmes: [:], names: [:]), successes: 0, failures: [], playlist: playlist, token: token, cache: cache)
    }
    private func load(_ urls: [URL], index: Int, merged: Guide, successes: Int, failures: [String], playlist: Playlist, token: UUID, cache: String) {
        let id = playlist.id
        guard revisions[id] == token else { return }
        guard index < urls.count else {
            tasks[id] = nil; busy.remove(id)
            if successes > 0 {
                guides[id] = merged
                publish(id, failures.isEmpty ? "Guida caricata" : "Guida parziale · " + failures.joined(separator: " · "))
                DispatchQueue.global(qos: .utility).async { try? self.store.save(merged, as: cache) }
            } else {
                publish(id, (guides[id] == nil ? "Errore EPG · " : "Guida salvata in uso · aggiornamento fallito · ") + failures.joined(separator: " · "))
            }
            return
        }
        let url = urls[index], sourceLabel = "Fonte \(index+1)/\(urls.count)"
        publish(id, sourceLabel + (url.isFileURL ? " · Lettura XMLTV…" : " · Scaricamento…"))
        let complete: (Data?, String?) -> Void = { data, failure in
            var next = merged, n = successes, errors = failures
            if let data = data {
                DispatchQueue.main.async { if self.revisions[id] == token { self.publish(id, sourceLabel + " · Decompressione e lettura XMLTV…") } }
                if let unpacked = Self.unpack(data) {
                    do {
                        let parsed = try XMLTV.parse(unpacked, channels: playlist.catalog.channels)
                        next.programmes.merge(parsed.programmes) { old, _ in old }
                        next.names.merge(parsed.names) { Array(Set($0 + $1)) }; n += 1
                    } catch { errors.append(sourceLabel + ": XMLTV non valido o limite di parsing superato") }
                } else { errors.append(sourceLabel + ": gzip non valido o guida decompressa oltre 128 MB") }
            } else { errors.append(sourceLabel + ": " + (failure ?? "Dati non disponibili")) }
            let result = next, count = n, messages = errors
            DispatchQueue.main.async { self.load(urls, index: index+1, merged: result, successes: count, failures: messages, playlist: playlist, token: token, cache: cache) }
        }
        if url.isFileURL {
            DispatchQueue.global(qos: .utility).async {
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size <= 128*1024*1024 else { complete(nil, "File oltre 128 MB"); return }
                    complete(try Data(contentsOf: url), nil)
                } catch { complete(nil, "File locale non leggibile") }
            }; return
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { complete(nil, "Protocollo della sorgente non supportato"); return }
        var request = URLRequest(url: url); request.timeoutInterval = 45
        let task = URLSession.shared.downloadTask(with: request) { file, response, error in
            if let error = error { complete(nil, Self.networkMessage(error)); return }
            guard let response = response as? HTTPURLResponse else { complete(nil, "Risposta del server non valida"); return }
            guard (200..<300).contains(response.statusCode) else { complete(nil, "Errore HTTP \(response.statusCode)"); return }
            guard let file = file else { complete(nil, "Download vuoto"); return }
            do {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 128*1024*1024 else { complete(nil, "Download oltre 128 MB"); return }
                complete(try Data(contentsOf: file), nil)
            } catch { complete(nil, "Impossibile leggere il download") }
        }
        tasks[id] = task; task.resume()
    }
    static func unpack(_ data: Data) -> Data? {
        guard data.starts(with: [0x1f, 0x8b]) else { return data }
        var length = 0
        let result = data.withUnsafeBytes { bytes in maciptv_gunzip(bytes.bindMemory(to: UInt8.self).baseAddress, data.count, &length) }
        guard let result = result else { return nil }
        defer { free(result) }; return Data(bytes: result, count: length)
    }
}
