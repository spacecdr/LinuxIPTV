import Foundation
func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
let input = """
\u{FEFF}#EXTM3U
#EXTINF:-1 tvg-name="Fallback" tvg-logo="logos/one.png" group-title="News, Italia",Rai, Uno
#EXTVLCOPT:http-user-agent=Test TV
#EXTVLCOPT:http-referrer=https://example.org/
streams/one.ts
#EXTINF:-1 group-title="Sport",Secondo
https://example.org/two.ts|User-Agent=Hello%20World&Referer=https%3A%2F%2Fexample.org
#EXTINF:-1 group-title="Sport",Secondo
https://example.org/two.ts
#EXTINF:-1,Terzo
#EXTGRP:Documentari
https://example.org/three.m3u8
#EXTINF:-1,Invalid
javascript:alert(1)
"""
let channels = try M3U.parse(Data(input.utf8), base: URL(string: "https://example.org/lists/main.m3u")!)
check(channels.count == 3, "Duplicates / invalid protocols")
check(channels[0].name == "Rai, Uno", "Quoted comma")
check(channels[0].group == "News, Italia", "Group with comma")
check(channels[0].url == "https://example.org/lists/streams/one.ts", "Relative stream")
check(channels[0].logo == "https://example.org/lists/logos/one.png", "Relative logo")
check(channels[0].headers["http-user-agent"] == "Test TV", "VLC headers")
check(channels[1].headers["http-user-agent"] == "Hello World", "URL headers")
check(channels[2].group == "Documentari" && channels[2].headers.isEmpty, "No leaked metadata")
let reload = try M3U.parse(Data(input.utf8), base: URL(string: "https://example.org/lists/main.m3u")!)
check(channels == reload, "Stable IDs")
for invalid in [Data("<html>error</html>".utf8), Data(repeating: 0, count: M3U.limit+1)] {
    do { _ = try M3U.parse(invalid); fatalError("Expected invalid input") } catch { }
}
let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: dir) }
let store = try Store(directory: dir)
let catalog = Catalog(raw: input, source: "https://example.org/list.m3u", base: "", channels: channels)
try store.save(catalog, as: "catalog.json")
try store.save([channels[0].id], as: "favorites.json")
let loaded = try store.load("catalog.json", as: Catalog.self)!
check(loaded.channels == channels, "Catalog persistence")
let favorites = try store.load("favorites.json", as: [String].self)!
check(favorites == [channels[0].id], "Favorite persistence")
let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("catalog.json").path)
check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Private catalog")
let large = "#EXTM3U\n" + (0..<10000).map { "#EXTINF:-1 group-title=\"Group \($0 % 160)\",Channel \($0)\nhttps://example.org/\($0).ts" }.joined(separator: "\n")
let start = Date()
let big = try M3U.parse(Data(large.utf8))
check(big.count == 10000, "Large catalog")
print("PASS parser, metadata, relative URLs, headers, deduplication, errors, stable IDs, private atomic persistence, favorites, 10000 channels (\(Date().timeIntervalSince(start))s)")
