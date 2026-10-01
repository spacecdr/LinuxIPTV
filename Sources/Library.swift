import Foundation

struct BrowseState: Codable {
    var group = "@all"
    var search = ""
    var groupSearch = ""
    var page = 0
    var selected = ""
    var mode = "grid"
}
struct Playlist: Codable {
    var id = UUID().uuidString
    var name: String
    var catalog: Catalog
    var favorites: Set<String> = []
    var epgOverride = ""
    var updated = Date()
    var browse = BrowseState()
    var epgURLs: [URL] {
        let raw = epgOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return URL(string: raw).map { [$0] } ?? [] }
        return M3U.guideURLs(catalog.raw, base: URL(string: catalog.base))
    }
}
struct PlaylistLibrary: Codable {
    var playlists: [Playlist] = []
    var selectedID: String?
    var selectedIndex: Int? { playlists.firstIndex { $0.id == selectedID } }
    static func restore(_ store: Store) throws -> PlaylistLibrary {
        if let existing = try store.load("library.json", as: PlaylistLibrary.self) { return existing }
        var library = PlaylistLibrary()
        if var old = try store.load("catalog.json", as: Catalog.self) {
            // Reparse to recover tvg-id from pre-EPG installations without changing channel IDs.
            if let parsed = try? M3U.parse(Data(old.raw.utf8), base: URL(string: old.base)) { old.channels = parsed }
            let favorites = Set(try store.load("favorites.json", as: [String].self) ?? [])
            let item = Playlist(name: "La mia lista", catalog: old, favorites: favorites)
            library.playlists = [item]; library.selectedID = item.id
            try store.save(library, as: "library.json")
        }
        return library
    }
}
extension M3U {
    static func guideURLs(_ raw: String, base: URL?) -> [URL] {
        let header = raw.components(separatedBy: .newlines).first { $0.replacingOccurrences(of: "\u{FEFF}", with: "").hasPrefix("#EXTM3U") } ?? ""
        let regex = try! NSRegularExpression(pattern: "(?i)(?:x-tvg-url|url-tvg|tvg-url)\\s*=\\s*[\"']([^\"']+)[\"']")
        let ns = header as NSString
        var urls: [URL] = []
        for match in regex.matches(in: header, range: NSRange(location: 0, length: ns.length)) {
            for rawURL in ns.substring(with: match.range(at: 1)).split(separator: ",") {
                if let url = URL(string: rawURL.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL,
                   ["http", "https", "file"].contains(url.scheme?.lowercased() ?? ""), !urls.contains(url) { urls.append(url) }
            }
        }
        return Array(urls.prefix(4))
    }
}
