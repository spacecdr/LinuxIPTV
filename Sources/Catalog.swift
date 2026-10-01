import Foundation
import CryptoKit

struct Channel: Codable, Equatable {
    let id: String
    let name: String
    let group: String
    let url: String
    let logo: String
    let headers: [String: String]
    var tvgID: String? = nil
    var tvgName: String? = nil
}
struct Catalog: Codable {
    var raw: String
    var source: String
    var base: String
    var channels: [Channel]
}
enum PlaylistError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}
enum M3U {
    static let limit = 20 * 1024 * 1024
    static func parse(_ data: Data, base: URL? = nil) throws -> [Channel] {
        guard data.count <= limit else { throw PlaylistError.invalid("La lista supera 20 MB.") }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw PlaylistError.invalid("Codifica della lista non riconosciuta.") }
        let attr = try NSRegularExpression(pattern: "([\\w-]+)\\s*=\\s*\"([^\"]*)\"")
        var result: [Channel] = [], seen = Set<String>()
        var tvgID = "", tvgName = ""
        var name = "", group = "", logo = "", headers: [String: String] = [:]
        func resolve(_ raw: String) -> String {
            guard !raw.isEmpty, let u = URL(string: raw, relativeTo: base)?.absoluteURL,
                  ["http", "https", "rtsp", "rtmp", "udp", "rtp", "file"].contains(u.scheme?.lowercased() ?? "") else { return "" }
            return u.absoluteString
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{FEFF}", with: "")
            if line.hasPrefix("#EXTINF:") {
                var quoted = false, split: String.Index?
                for i in line.indices { if line[i] == "\"" { quoted.toggle() }; if line[i] == "," && !quoted { split = i; break } }
                let metadata = split.map { String(line[..<$0]) } ?? line
                let ns = metadata as NSString
                var attrs: [String: String] = [:]
                for match in attr.matches(in: metadata, range: NSRange(location: 0, length: ns.length)) {
                    attrs[ns.substring(with: match.range(at: 1)).lowercased()] = ns.substring(with: match.range(at: 2))
                }
                name = split.map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
                if name.isEmpty { name = attrs["tvg-name"] ?? "" }
                tvgID = attrs["tvg-id"] ?? ""; tvgName = attrs["tvg-name"] ?? ""
                group = attrs["group-title"] ?? ""
                logo = resolve(attrs["tvg-logo"] ?? "")
                headers = [:]
            } else if line.hasPrefix("#EXTGRP:") { group = String(line.dropFirst(8))
            } else if line.hasPrefix("#EXTVLCOPT:") {
                let pair = line.dropFirst(11).split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2, ["http-user-agent", "http-referrer"].contains(pair[0]) { headers[pair[0]] = pair[1] }
            } else if !line.isEmpty && !line.hasPrefix("#") {
                let pieces = line.split(separator: "|", maxSplits: 1).map(String.init)
                let address = resolve(pieces[0])
                if pieces.count == 2 {
                    for pair in pieces[1].split(separator: "&") {
                        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            let key = parts[0].lowercased()
                            if key == "user-agent" { headers["http-user-agent"] = parts[1].removingPercentEncoding ?? parts[1] }
                            if key == "referer" || key == "referrer" { headers["http-referrer"] = parts[1].removingPercentEncoding ?? parts[1] }
                        }
                    }
                }
                if !address.isEmpty {
                    let title = name.isEmpty ? (URL(string: address)?.lastPathComponent ?? "Canale") : name
                    let category = group.isEmpty ? "Senza gruppo" : group
                    let id = SHA256.hash(data: Data((address + "\n" + category + "\n" + title).utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
                    if seen.insert(String(id)).inserted { result.append(Channel(id: String(id), name: title, group: category, url: address, logo: logo, headers: headers, tvgID: tvgID, tvgName: tvgName)) }
                }
                name = ""; group = ""; logo = ""; headers = [:]; tvgID = ""; tvgName = ""
            }
        }
        guard !result.isEmpty else { throw PlaylistError.invalid("Nessun canale valido nella lista. La lista precedente è stata conservata.") }
        return result
    }
}
final class Store {
    let directory: URL
    init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IPTVMac")
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func save<T: Encodable>(_ value: T, as name: String) throws {
        let target = directory.appendingPathComponent(name)
        try JSONEncoder().encode(value).write(to: target, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}
