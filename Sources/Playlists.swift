import Cocoa
import UniformTypeIdentifiers
extension App {
    var selectedPlaylist: Playlist? { library.selectedIndex.map {library.playlists[$0]} }
    func saveLibrary() throws { try store.save(library,as:"library.json") }
    func sendLibrary() {
        emit("receiveLibrary",["selected":library.selectedID ?? "","lists":library.playlists.map { ["id":$0.id,"name":$0.name,"source":$0.catalog.source,"epg":$0.epgOverride,"updated":$0.updated.timeIntervalSince1970,"count":$0.catalog.channels.count] as [String:Any] }])
    }
    func selectPlaylist(_ id:String) {
        guard library.playlists.contains(where:{$0.id==id}) else{return}
        library.selectedID=id;try? saveLibrary();sendLibrary();sendCatalog();sendState();if let item=selectedPlaylist {epg.refresh(item)}
    }
    func rememberBrowse(_ d:[String:Any]) {
        guard let i=library.selectedIndex else{return}
        library.playlists[i].browse=BrowseState(group:d["group"] as? String ?? "@all",search:d["search"] as? String ?? "",groupSearch:d["groupSearch"] as? String ?? "",page:d["page"] as? Int ?? 0,selected:d["selected"] as? String ?? "",mode:d["mode"] as? String ?? "grid")
        browseSave?.cancel();let task=DispatchWorkItem{try? self.saveLibrary()};browseSave=task;DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:task)
    }
    func removePlaylist() {
        guard current==nil,let item=selectedPlaylist else{return}
        let alert=NSAlert();alert.messageText="Rimuovere \(item.name)?";alert.informativeText="Verranno rimossi la copia locale della lista e i suoi preferiti. Il file o la sorgente originale non vengono modificati.";alert.addButton(withTitle:"Rimuovi");alert.addButton(withTitle:"Annulla")
        alert.beginSheetModal(for:window){answer in
            guard answer == .alertFirstButtonReturn else{return}
            var next=self.library;next.playlists.removeAll{$0.id==item.id};next.selectedID=next.playlists.first?.id
            do{try self.store.save(next,as:"library.json");self.library=next;self.epg.cancel(item.id);self.sendLibrary();self.sendCatalog();self.sendState()}catch{self.report("Impossibile salvare la modifica.")}
        }
    }
    func editPlaylist(_ body:[String:Any]) {
        guard current==nil else{return}
        let id=body["id"] as? String ?? "",name=(body["name"] as? String ?? "Lista").trimmingCharacters(in:.whitespacesAndNewlines)
        let source=(body["source"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines),guide=(body["epg"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        if !guide.isEmpty && !validHTTP(guide) {report("URL XMLTV non valido.");return}
        if let i=library.playlists.firstIndex(where:{$0.id==id}),source==library.playlists[i].catalog.source {
            var next=library;next.playlists[i].name=name.isEmpty ? "Lista" : name;next.playlists[i].epgOverride=guide
            do{try store.save(next,as:"library.json");library=next;sendLibrary();epg.refresh(next.playlists[i],force:true)}catch{report("Salvataggio non riuscito.")};return
        }
        if !source.isEmpty {importURL(source,target:id,name:name,guide:guide)}else{openPlaylistFile(target:id,name:name,guide:guide)}
    }
    func validHTTP(_ text:String)->Bool {guard let u=URL(string:text) else{return false};return ["http","https"].contains(u.scheme?.lowercased() ?? "") && u.host != nil}
    @objc func openFile(){openPlaylistFile(target:library.selectedID ?? "",name:selectedPlaylist?.name ?? "Lista",guide:selectedPlaylist?.epgOverride ?? "")}
    func openPlaylistFile(target:String,name:String,guide:String) {
        guard current==nil else{return}
        let panel=NSOpenPanel();panel.allowedContentTypes=[UTType(filenameExtension:"m3u"),UTType(filenameExtension:"m3u8"),.plainText].compactMap{$0}
        panel.beginSheetModal(for:window){result in
            guard result == .OK,let url=panel.url else{return}
            self.loadTask?.cancel();self.generation += 1;let token=self.generation
            DispatchQueue.global(qos:.userInitiated).async{
                do{let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0;guard size<=M3U.limit else{throw PlaylistError.invalid("La lista supera 20 MB.")};let data=try Data(contentsOf:url);self.completeImport(data,source:"",base:url,target:target,name:name,guide:guide,token:token)}catch{DispatchQueue.main.async{self.report("Lettura della lista non riuscita.")}}
            }
        }
    }
    func importURL(_ text:String,target:String?=nil,name:String?=nil,guide:String?=nil){
        guard current==nil else{return}
        guard validHTTP(text),let url=URL(string:text) else{report("Inserisci un URL HTTP/HTTPS valido.");return}
        let id=target ?? library.selectedID ?? "",label=name ?? selectedPlaylist?.name ?? "Lista",epgURL=guide ?? selectedPlaylist?.epgOverride ?? ""
        loadTask?.cancel();generation += 1;let token=generation;status="Scaricamento lista…";sendState()
        var request=URLRequest(url:url);request.timeoutInterval=45
        loadTask=URLSession.shared.downloadTask(with:request){file,response,error in
            if (error as NSError?)?.code == NSURLErrorCancelled{return}
            guard let file=file,error==nil,let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode),let size=try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=M3U.limit,let data=try? Data(contentsOf:file) else{DispatchQueue.main.async{if token==self.generation{self.report("Download non riuscito o lista oltre 20 MB. La copia precedente è conservata.")}};return}
            self.completeImport(data,source:text,base:http.url ?? url,target:id,name:label,guide:epgURL,token:token)
        };loadTask?.resume()
    }
    func completeImport(_ data:Data,source:String,base:URL,target:String,name:String,guide:String,token:Int){
        do{let channels=try M3U.parse(data,base:base);let raw=String(data:data,encoding:.utf8) ?? String(data:data,encoding:.isoLatin1) ?? "";let value=Catalog(raw:raw,source:source,base:base.absoluteString,channels:channels)
            DispatchQueue.main.async{
                guard token==self.generation else{return}
                var next=self.library
                if let i=next.playlists.firstIndex(where:{$0.id==target}){next.playlists[i].catalog=value;next.playlists[i].name=name;next.playlists[i].epgOverride=guide;next.playlists[i].updated=Date();next.selectedID=target}
                else{var item=Playlist(name:name.isEmpty ? "Lista" : name,catalog:value);item.epgOverride=guide;next.playlists.append(item);next.selectedID=item.id}
                do{try self.store.save(next,as:"library.json");self.library=next;self.status="\(channels.count) canali caricati";self.sendLibrary();self.sendCatalog();self.sendState();if let item=self.selectedPlaylist{self.epg.refresh(item,force:true)}}catch{self.report("Salvataggio non riuscito: lista precedente conservata.")}
            }
        }catch{DispatchQueue.main.async{if token==self.generation{self.report(error.localizedDescription)}}}
    }
}
