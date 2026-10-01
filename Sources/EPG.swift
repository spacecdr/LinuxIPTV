import Foundation
import CryptoKit

struct Programme: Codable {
    var title: String
    var description: String
    var start: Date
    var end: Date?
}
struct Guide: Codable {
    var programmes: [String: [Programme]]
    var names: [String: [String]]
    var fetched = Date()
    func channelID(_ channel: Channel) -> String? {
        if let id = channel.tvgID, !id.isEmpty, programmes[id] != nil { return id }
        // Only unambiguous exact display-name matching; no fuzzy country/HD stripping.
        for name in [channel.tvgName ?? "", channel.name] where !name.isEmpty {
            let ids = Set(names[name.lowercased()] ?? [])
            if ids.count == 1 { return ids.first }
        }
        return nil
    }
    func schedule(_ channel: Channel, now: Date = Date()) -> (Programme?, Programme?) {
        guard let id = channelID(channel), let list = programmes[id] else { return (nil, nil) }
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

// All public entry points and published state are used on the main thread.
final class EPGService {
    let store: Store
    var guides: [String: Guide] = [:]
    var states: [String: String] = [:]
    var tasks: [String: URLSessionDownloadTask] = [:]
    var revisions: [String: UUID] = [:]
    var lastAttempt: [String: Date] = [:]
    var fingerprints: [String: String] = [:]
    var onChange: (() -> Void)?
    init(store: Store) { self.store = store }
    func cancel(_ id: String) { tasks[id]?.cancel(); tasks[id] = nil; revisions[id] = UUID(); guides[id] = nil; fingerprints[id] = nil; lastAttempt[id] = nil }
    func refresh(_ playlist: Playlist, force: Bool = false) {
        let urls = playlist.epgURLs, id = playlist.id
        let fingerprint = SHA256.hash(data: Data(urls.map(\.absoluteString).joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        if fingerprints[id] != fingerprint { cancel(id); fingerprints[id] = fingerprint }
        guard !urls.isEmpty else { states[id] = "Nessuna guida EPG nella lista"; return }
        guard force || (tasks[id] == nil && Date().timeIntervalSince(lastAttempt[id] ?? .distantPast) > 3600) else { return }
        tasks[id]?.cancel(); let token = UUID(); revisions[id] = token; lastAttempt[id] = Date()
        let cache = "epg-\(id)-\(fingerprint.prefix(16)).json"
        states[id] = "Guida in aggiornamento…"
        DispatchQueue.global(qos: .utility).async {
            if let saved = try? self.store.load(cache, as: Guide.self) {
                DispatchQueue.main.async { if self.revisions[id] == token && self.guides[id] == nil { self.guides[id] = saved; self.onChange?() } }
            }
        }
        load(urls, index: 0, merged: Guide(programmes: [:], names: [:]), successes: 0, playlist: playlist, token: token, cache: cache)
    }
    private func load(_ urls: [URL], index: Int, merged: Guide, successes: Int, playlist: Playlist, token: UUID, cache: String) {
        let id = playlist.id
        guard revisions[id] == token else { return }
        guard index < urls.count else {
            tasks[id] = nil
            if successes > 0 {
                guides[id] = merged; states[id] = "Guida aggiornata"
                DispatchQueue.global(qos: .utility).async { try? self.store.save(merged, as: cache) }
            } else { states[id] = guides[id] == nil ? "Guida non disponibile" : "Guida salvata · aggiornamento non riuscito" }
            onChange?(); return
        }
        let url = urls[index]
        let complete: (Data?) -> Void = { data in
            var next = merged, n = successes
            if let data = data, let unpacked = Self.unpack(data), let parsed = try? XMLTV.parse(unpacked, channels: playlist.catalog.channels) {
                next.programmes.merge(parsed.programmes) { old, _ in old }; next.names.merge(parsed.names) { Array(Set($0 + $1)) }; n += 1
            }
            let result = next, count = n
            DispatchQueue.main.async { self.load(urls, index: index+1, merged: result, successes: count, playlist: playlist, token: token, cache: cache) }
        }
        if url.isFileURL {
            DispatchQueue.global(qos: .utility).async {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
                complete(size <= 128*1024*1024 ? try? Data(contentsOf: url) : nil)
            }; return
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { complete(nil); return }
        var request = URLRequest(url: url); request.timeoutInterval = 45
        let task = URLSession.shared.downloadTask(with: request) { file, response, error in
            guard error == nil, let file = file, let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 128*1024*1024 else { complete(nil); return }
            complete(try? Data(contentsOf: file))
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
