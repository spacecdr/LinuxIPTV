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
