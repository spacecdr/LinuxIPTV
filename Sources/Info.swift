import Cocoa
import WebKit
final class InfoWebView: WKWebView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
extension App {
    func setupInfo(_ root: NSView) {
        infoWeb = InfoWebView(frame: root.bounds); infoWeb.autoresizingMask = [.width,.height]; infoWeb.setValue(false, forKey:"drawsBackground")
        infoWeb.isHidden = true; root.addSubview(infoWeb)
        infoWeb.loadFileURL(Bundle.main.url(forResource:"info",withExtension:"html")!, allowingReadAccessTo:Bundle.main.resourceURL!)
    }
    func hideInfo() {
        infoTimer?.invalidate(); infoVisible = false
        infoWeb.evaluateJavaScript("document.body.classList.remove('shown')",completionHandler:nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { if !self.infoVisible { self.infoWeb.isHidden = true } }
    }
    func toggleInfo() {
        guard current != nil else { return }
        if infoVisible { hideInfo(); return }
        infoVisible = true; infoWeb.isHidden = false; updateInfo()
        infoWeb.evaluateJavaScript("requestAnimationFrame(()=>document.body.classList.add('shown'))",completionHandler:nil)
        infoTimer?.invalidate(); infoTimer = Timer.scheduledTimer(withTimeInterval:5,repeats:false) { [weak self] _ in self?.hideInfo() }
    }
    func schedulePayload(_ channel: Channel, playlistID: String, details: Bool, matcher: EPGMatcher? = nil) -> [String:Any] {
        guard let guide = epg?.guides[playlistID] else { return [:] }
        let (now,next) = guide.schedule(channel, matcher: matcher)
        func encode(_ p: Programme) -> [String:Any] {
            var d:[String:Any] = ["title":p.title,"start":p.start.timeIntervalSince1970]
            if let end=p.end { d["end"]=end.timeIntervalSince1970 }
            if details { d["description"]=p.description };return d
        }
        var result:[String:Any]=[:];if let now=now {result["now"]=encode(now)};if let next=next{result["next"]=encode(next)};return result
    }
    func sendEPG() {
        guard let item=selectedPlaylist else {emit("receiveEPG",["programmes":[:],"status":"Nessuna lista caricata","diagnostics":[:],"busy":false]);return}
        let matcher = epg?.guides[item.id].map { EPGMatcher($0) }
        var rows:[String:Any]=[:]
        for c in item.catalog.channels {let p=schedulePayload(c,playlistID:item.id,details:false,matcher:matcher);if !p.isEmpty {rows[c.id]=p}}
        emit("receiveEPG",["programmes":rows,"status":epg?.states[item.id] ?? "Guida non ancora caricata", "busy":epg?.busy.contains(item.id) ?? false, "diagnostics":EPGService.diagnostics(item,guide:epg?.guides[item.id])])
        if infoVisible {updateInfo()}
    }
    func updateInfo() {
        guard let c=current else{return}
        var w:UInt32=0,h:UInt32=0;_ = libvlc_video_get_size(player,0,&w,&h)
        let labels:[UInt32:String]=[480:"SD",576:"SD",720:"HD",1080:"Full HD",2160:"UHD"]
        var resolution = w>0 && h>0 ? "\(w)×\(h)" : "Risoluzione in rilevamento…"
        if let label=labels[h] {resolution += " · \(label)"}
        var data=schedulePayload(c,playlistID:playingPlaylistID,details:true)
        data["name"]=c.name;data["logo"]=c.logo;data["resolution"]=resolution
        if let json=try? JSONSerialization.data(withJSONObject:data),let text=String(data:json,encoding:.utf8) {infoWeb.evaluateJavaScript("renderInfo(\(text))",completionHandler:nil)}
    }
}
