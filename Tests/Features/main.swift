import Foundation
func check(_ value: @autoclosure ()->Bool,_ message:String){precondition(value(),message)}
let raw="#EXTM3U x-tvg-url=\"guide.xml\"\n#EXTINF:-1 tvg-id=\"one\" tvg-name=\"One\" group-title=\"News\",Uno\nhttps://example.org/one"
let channels=try M3U.parse(Data(raw.utf8))
check(channels[0].tvgID=="one","tvg-id")
check(M3U.guideURLs(raw,base:URL(string:"https://example.org/list.m3u"))[0].absoluteString=="https://example.org/guide.xml","guide discovery")
let now=XMLTV.date("20261001190000 +0200")!
let xml="""
<tv><channel id="one"><display-name>One</display-name></channel><programme channel="one" start="20261001180000 +0200"><title>Ora</title><desc>Dettagli</desc></programme><programme channel="one" start="20261001200000 +0200" stop="20261001210000 +0200"><title>Dopo</title></programme></tv>
"""
let guide=try XMLTV.parse(Data(xml.utf8),channels:channels,now:now)
let pair=guide.schedule(channels[0],now:now)
check(pair.0?.title=="Ora" && pair.1?.title=="Dopo","now/next")
check(pair.0?.end==pair.1?.start,"infer end from next programme")
check(pair.0?.description=="Dettagli","description")
check(guide.schedule(channels[0],now:now.addingTimeInterval(86400)).0==nil,"expired guide")
let dir=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
defer{try? FileManager.default.removeItem(at:dir)}
let store=try Store(directory:dir),catalog=Catalog(raw:raw,source:"",base:"",channels:channels)
try store.save(catalog,as:"catalog.json");try store.save([channels[0].id],as:"favorites.json")
var library=try PlaylistLibrary.restore(store)
check(library.playlists[0].favorites.contains(channels[0].id),"migration favorites")
library.playlists.append(Playlist(name:"Seconda",catalog:catalog))
check(library.playlists[1].favorites.isEmpty,"favorites isolated")
try store.save(library,as:"library.json")
let restored=try PlaylistLibrary.restore(store);check(restored.playlists.count==2,"multiple lists persist")
print("PASS EPG discovery, tvg-id, timezone, current/next, inferred end, expiry, legacy migration, isolated favorites, multiple playlists")
let item=Playlist(name:"Test",catalog:catalog)
let diagnostic=EPGService.diagnostics(item,guide:guide,now:now)
check(diagnostic["matched"] as? Int == 1,"diagnostic association")
check(diagnostic["current"] as? Int == 1,"diagnostic current")
let expired=EPGService.diagnostics(item,guide:guide,now:now.addingTimeInterval(86400))
check(expired["matched"] as? Int == 1 && expired["current"] as? Int == 0,"associated vs expired")
let unmatched=Channel(id:"other",name:"Other",group:"Test",url:"https://example.org/other",logo:"",headers:[:],tvgID:"absent")
let absentItem=Playlist(name:"Other",catalog:Catalog(raw:"",source:"",base:"",channels:[unmatched]))
check(EPGService.diagnostics(absentItem,guide:guide,now:now)["matched"] as? Int == 0,"unmatched feedback")
let secretError=NSError(domain:NSURLErrorDomain,code:NSURLErrorTimedOut,userInfo:[NSLocalizedDescriptionKey:"https://private.example/credential"])
check(!EPGService.networkMessage(secretError).contains("credential"),"network error privacy")
print("PASS EPG diagnostics: associations, current/missing programmes, unmatched IDs, error privacy")
func testChannel(_ id: String?, _ name: String, tvgName: String? = nil) -> Channel {
    Channel(id: UUID().uuidString, name: name, group: "Test", url: "https://example.org/test", logo: "", headers: [:], tvgID: id, tvgName: tvgName)
}
let tennis = Guide(programmes: ["Sky Sport Tennis.it": [pair.0!], "SuperTennis.it": [pair.0!]], names: ["sky sport tennis": ["Sky Sport Tennis.it"], "supertennis hd": ["SuperTennis.it"]])
let matcher = EPGMatcher(tennis)
for id in ["skysporttennis.it", "SkySportTennis.it", "Sky.Sport.Tennis.it", "SKY_SPORT-TENNIS.IT"] {
    let c = testChannel(id, "IT- Sky Sport Tennis H265")
    check(matcher.match(c).kind == .normalizedID, "ID normalization")
    check(tennis.schedule(c, now: now, matcher: matcher).0?.title == "Ora", "normalized ID playback schedule")
}
check(matcher.match(testChannel("Sky Sport Tennis.it", "different")).kind == .exactID, "exact ID priority")
check(matcher.match(testChannel("supertennis.it", "IT- Super Tennis FHD")).id == "SuperTennis.it", "SuperTennis ID")
check(matcher.match(testChannel(nil, "IT- Super Tennis FHD")).kind == .name, "quality/name fallback")
check(matcher.match(testChannel("unknown", "IT- Sky Sport Tennis HD H265")).kind == .name, "multiple quality suffixes")
for name in ["IT- Sky Sport Tennis +1 HD", "IT- Sky Sport Tennis +24", "IT- Sky Sport Tennis 2 HD"] {
    check(matcher.match(testChannel(nil, name)).kind == .missing, "preserve timeshift and numbers")
}
check(matcher.match(testChannel("SkySportTennis+1.it", "Tennis +1")).kind == .missing, "preserve plus in IDs")
var collision = tennis
collision.names["other"] = ["Sky.Sport.Tennis.it"] // Include IDs with no current programmes.
let colliding = EPGMatcher(collision)
check(colliding.match(testChannel("skysporttennis.it", "Sky Sport Tennis")).kind == .ambiguous, "ambiguous ID must not fall through to name")
check(colliding.match(testChannel("Sky Sport Tennis.it", "anything")).kind == .exactID, "exact wins despite normalized collision")
collision.names["sky sport tennis hd"] = ["different"]
check(EPGMatcher(collision).match(testChannel(nil, "IT- Sky Sport Tennis HD")).kind == .ambiguous, "ambiguous cleaned names")
check(matcher.match(testChannel(nil, "SuperTennis", tvgName: "Sky Sport Tennis")).kind == .ambiguous, "conflicting channel names")
let cached = try JSONDecoder().decode(Guide.self, from: JSONEncoder().encode(tennis))
check(cached.channelID(testChannel("skysporttennis.it", "Test")) == "Sky Sport Tennis.it", "cache compatibility")
let diagnosticChannels = [testChannel("Sky Sport Tennis.it", "Test"), testChannel("skysporttennis.it", "Test"), testChannel(nil, "Super Tennis FHD"), testChannel(nil, "Absent"), testChannel(nil, "SuperTennis", tvgName: "Sky Sport Tennis")]
let diag = EPGService.diagnostics(Playlist(name: "Matches", catalog: Catalog(raw: "", source: "", base: "", channels: diagnosticChannels)), guide: tennis, now: now)
for key in ["exactID", "normalizedID", "name", "missing", "ambiguous"] { check(diag[key] as? Int == 1, "diagnostic match method: " + key) }
print("PASS EPG matching: exact/normalized IDs, names/quality, timeshift, collisions, conflicts, cache, diagnostics")
