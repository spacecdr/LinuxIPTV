import Cocoa
import WebKit
import UniformTypeIdentifiers

final class TVWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
final class VideoSurface: NSView {
    var onDoubleClick: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point:NSPoint)->NSView? {bounds.contains(convert(point,from:superview)) ? self : nil}
    override func mouseDown(with event:NSEvent){
        guard let window=window else{return}
        if event.clickCount==2 {onDoubleClick?();return}
        guard !window.styleMask.contains(.fullScreen) else{return}
        let p=convert(event.locationInWindow,from:nil)
        if !window.styleMask.contains(.titled) && p.x>bounds.width-28 && p.y<28 {
            let frame=window.frame,origin=NSEvent.mouseLocation,ratio=window.contentAspectRatio
            while let e=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]){
                if e.type == .leftMouseUp{break};let mouse=NSEvent.mouseLocation
                var w=max(420,frame.width+mouse.x-origin.x),h=max(236,frame.height-mouse.y+origin.y)
                if ratio.width>0 {let r=ratio.width/ratio.height;if abs(mouse.x-origin.x)>abs(mouse.y-origin.y)*r{h=max(236,w/r);w=h*r}else{w=max(420,h*r);h=w/r}}
                window.setFrame(NSRect(x:frame.minX,y:frame.maxY-h,width:w,height:h),display:true)
            }
        }else{window.performDrag(with:event)}
    }
}
final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: TVWindow!
    var web: WKWebView!
    var surface: VideoSurface!
    var instance: OpaquePointer!
    var player: OpaquePointer!
    let engine = DispatchQueue(label: "IPTVMac.VLC")
    var store: Store!
    var library = PlaylistLibrary()
    var catalog: Catalog? {
        get { selectedPlaylist?.catalog }
        set { if let value=newValue { if let i=library.selectedIndex {library.playlists[i].catalog=value} else {let item=Playlist(name:"Lista",catalog:value);library.playlists.append(item);library.selectedID=item.id} } }
    }
    var favorites: Set<String> {
        get { selectedPlaylist?.favorites ?? [] }
        set { if let i=library.selectedIndex {library.playlists[i].favorites=newValue} }
    }
    var session = WindowSession()
    var epg: EPGService!
    var playingPlaylistID = ""
    var transitioning = false
    var borderReturnFullscreen = false
    var fullReturnFloating = false
    var videoRatio = 0.0
    var infoWeb: InfoWebView!
    var infoVisible = false
    var infoTimer: Timer?
    var browseSave: DispatchWorkItem?
    var lastGuideTick = Date.distantPast
    var current: Channel?
    var visible = true
    var floating = false
    var pendingBorderless = false
    var savedFrame = NSRect(x: 100, y: 100, width: 1120, height: 700)
    var volume: Int32 = 70
    var muted = false
    var buffer = 3
    var timer: Timer?
    var monitor: Any?
    var loadTask: URLSessionDownloadTask?
    var generation = 0
    var playbackStart = Date()
    var status = "Carica una lista M3U per iniziare"
    var startError: String?
    var smoke = ProcessInfo.processInfo.arguments.contains("--smoke-test")
    var smokeTime: Int64 = -1
    var playbackGeneration = 0
    var engineReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        do {
            let override = smoke ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("IPTVMac-smoke-\(ProcessInfo.processInfo.processIdentifier)") : nil
            store = try Store(directory: override)
            library = try PlaylistLibrary.restore(store)
            session = try store.load("session.json",as:WindowSession.self) ?? WindowSession()
            epg = EPGService(store:store);epg.onChange = { [weak self] in self?.sendEPG() }
        } catch { startError = "Impossibile leggere i dati salvati: \(error.localizedDescription)" }
        let launchFull = session.mode == "fullscreen"
        transitioning = true
        setupMenu()
        window = TVWindow(contentRect: savedFrame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MacIPTV"
        window.minSize = NSSize(width: 420, height: 236)
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = .black
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrame(fitOnScreen(NSRectFromString(session.normal)),display:true)
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        surface = VideoSurface(frame: root.bounds)
        surface.autoresizingMask = [.width, .height]
        surface.onDoubleClick = { [weak self] in self?.toggleFullscreen() }
        root.addSubview(surface)
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "native")
        web = WKWebView(frame: root.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        root.addSubview(web)
        setupInfo(root)
        window.contentView = root
        let plugins = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/VLC/plugins").path
        setenv("VLC_PLUGIN_PATH", plugins, 1)
        let args = ["--ignore-config", "--no-video-title-show", "--no-osd", "--no-snapshot-preview", "--no-media-library", "--no-stats", "--quiet", "--vout=macosx"]
        let strings = args.map { strdup($0) }
        let pointers = strings.map { UnsafePointer<CChar>($0) }
        instance = pointers.withUnsafeBufferPointer { libvlc_new(Int32(args.count), $0.baseAddress) }
        strings.forEach { free($0) }
        if let instance = instance {
            player = libvlc_media_player_new(instance)
            libvlc_media_player_set_nsobject(player, Unmanaged.passUnretained(surface).toOpaque())
            libvlc_video_set_key_input(player, 0)
            libvlc_video_set_mouse_input(player, 0)
        } else { startError = "Il motore VLC incorporato non è disponibile." }
        web.loadFileURL(Bundle.main.url(forResource: "index", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, NSApp.keyWindow === self.window, !self.visible else { return e }
            if e.modifierFlags.contains(.command) { return e }
            switch e.keyCode {
            case 53: self.escape()
            case 36, 76, 51: self.showMenu()
            case 49: self.pause()
            case 126: self.step(1)
            case 125: self.step(-1)
            case 123: self.setVolume(self.volume - 5)
            case 124: self.setVolume(self.volume + 5)
            default:
                switch e.charactersIgnoringModifiers?.lowercased() {
                case "i": self.toggleInfo()
                case "f": self.toggleFullscreen()
                case "b": self.toggleBorderless()
                case "m": self.toggleMute()
                case "s": self.stop()
                default: return e
                }
            }
            return nil
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        transitioning = false
        if !smoke && launchFull && !ProcessInfo.processInfo.arguments.contains("--windowed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.window.toggleFullScreen(nil) }
        }
    }
    func setupMenu() {
        let bar = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "Apri lista M3U…", action: #selector(openFile), keyEquivalent: "o").target = self
        appMenu.addItem(withTitle: "Catalogo", action: #selector(showMenu), keyEquivalent: "l").target = self
        appMenu.addItem(withTitle: "Schermo intero / Finestra", action: #selector(toggleFullscreen), keyEquivalent: "f").target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Esci da MacIPTV", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; bar.addItem(item)
        let editItem = NSMenuItem(), edit = NSMenu(title: "Modifica")
        for (title, sel, key) in [("Taglia", "cut:", "x"), ("Copia", "copy:", "c"), ("Incolla", "paste:", "v"), ("Seleziona tutto", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(sel), keyEquivalent: key)
        }
        editItem.submenu = edit; bar.addItem(editItem); NSApp.mainMenu = bar
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sendLibrary(); sendCatalog(); sendState()
        if let item=selectedPlaylist {epg?.refresh(item)}
        if let error = startError { report(error) }
        if smoke { runSmoke() }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel)
    }
    func emit(_ method: String, _ value: Any) {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.\(method)(\(json))", completionHandler: nil)
    }
    func sendCatalog() {
        let channels = catalog?.channels ?? []
        let data = (try? JSONEncoder().encode(channels)) ?? Data("[]".utf8)
        let objects = (try? JSONSerialization.jsonObject(with: data)) ?? []
        var payload:[String:Any] = ["channels":objects,"favorites":Array(favorites),"source":catalog?.source ?? ""]
        if let browse=selectedPlaylist?.browse,let data=try? JSONEncoder().encode(browse),let object=try? JSONSerialization.jsonObject(with:data){payload["browse"]=object}
        emit("receiveCatalog",payload);sendEPG()
    }
    func sendState() {
        emit("receiveState", ["current": playingPlaylistID == library.selectedID ? current?.id ?? "" : "", "name": current?.name ?? "Nessun canale in riproduzione", "status": status, "active": current != nil, "volume": volume, "muted": muted, "floating": floating, "fullscreen": window.styleMask.contains(.fullScreen)])
    }
    func report(_ message: String) { showMenu(); emit("showError", ["message": message]) }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "selectPlaylist": selectPlaylist(body["id"] as? String ?? "")
        case "savePlaylist": editPlaylist(body)
        case "removePlaylist": removePlaylist()
        case "browse": rememberBrowse(body)
        case "info": toggleInfo()
        case "escape": escape()
        case "open": openFile()
        case "import": importURL(body["url"] as? String ?? "")
        case "refresh": importURL(catalog?.source ?? "")
        case "export": exportFile()
        case "play", "external":
            if let id = body["id"] as? String, let channel = catalog?.channels.first(where: { $0.id == id }) {
                if action == "external" { external(channel) } else { play(channel) }
            }
        case "favorite":
            if let id = body["id"] as? String, catalog?.channels.contains(where: { $0.id == id }) == true {
                var updated = favorites
                if !updated.insert(id).inserted { updated.remove(id) }
                do { let old=favorites;favorites=updated;do{try saveLibrary()}catch{favorites=old;throw error}; emit("receiveFavorites", Array(favorites)) } catch { report(error.localizedDescription) }
            }
        case "hide": if current != nil { hideMenu() }
        case "stop": stop()
        case "pause": pause()
        case "full": toggleFullscreen()
        case "border": toggleBorderless()
        case "volume": setVolume(Int32(body["value"] as? Int ?? 70))
        case "mute": toggleMute()
        case "buffer": buffer = min(10, max(1, body["value"] as? Int ?? 3))
        default: break
        }
    }
    func exportFile() {
        guard current == nil else{return}
        guard let catalog = catalog else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "playlist.m3u"
        panel.beginSheetModal(for: window) { result in
            if result == .OK, let url = panel.url {
                do { try catalog.raw.write(to: url, atomically: true, encoding: .utf8) } catch { self.report(error.localizedDescription) }
            }
        }
    }
    func play(_ channel: Channel) {
        guard player != nil else { report("Motore VLC non disponibile."); return }
        playbackGeneration += 1; let playToken = playbackGeneration; engineReady = false
        playingPlaylistID = library.selectedID ?? "";videoRatio=0;window.contentAspectRatio = .zero;hideInfo()
        current = channel; playbackStart = Date(); status = "Connessione…"; hideMenu(); sendState()
        let cache = buffer, volume = self.volume, muted = self.muted
        engine.async {
            libvlc_media_player_stop(self.player)
            guard let media = libvlc_media_new_location(self.instance, channel.url) else { DispatchQueue.main.async { self.report("Indirizzo del canale non valido.") }; return }
            libvlc_media_add_option(media, ":network-caching=\(cache * 1000)")
            for (key, value) in channel.headers where !value.contains("\n") && !value.contains("\r") { libvlc_media_add_option(media, ":\(key)=\(value)") }
            libvlc_media_player_set_media(self.player, media); libvlc_media_release(media)
            libvlc_audio_set_volume(self.player, volume); libvlc_audio_set_mute(self.player, muted ? 1 : 0)
            _ = libvlc_media_player_play(self.player)
            DispatchQueue.main.async { if self.playbackGeneration == playToken { self.engineReady = true; self.playbackStart = Date() } }
        }
    }
    func external(_ channel: Channel) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.videolan.vlc") else { report("VLC esterno non è installato. Puoi usare il player incorporato."); return }
        // Pass provider headers through a private M3U file rather than command arguments.
        let file = store.directory.appendingPathComponent("external.m3u")
        let options = channel.headers.filter { !$0.value.contains("\n") && !$0.value.contains("\r") }.map { "#EXTVLCOPT:\($0.key)=\($0.value)" }.joined(separator: "\n")
        let raw = "#EXTM3U\n#EXTINF:-1,\(channel.name.replacingOccurrences(of: "\n", with: " "))\n\(options)\n\(channel.url)\n"
        do {
            try raw.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            stop()
            let configuration = NSWorkspace.OpenConfiguration(); configuration.arguments = ["--fullscreen"]
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: configuration) { _, error in
                DispatchQueue.main.async { if error != nil { self.report("Impossibile aprire VLC esterno.") } }
            }
            status = "Riproduzione affidata a VLC esterno"; sendState()
        } catch { report(error.localizedDescription) }
    }
    func stop() { hideInfo();fullReturnFloating=false;pendingBorderless=false;if floating{leaveFloating()};videoRatio=0;window.contentAspectRatio = .zero;playbackGeneration += 1; engineReady = false; current = nil; status = "Riproduzione arrestata"; if player != nil { engine.async { libvlc_media_player_stop(self.player) } }; showMenu(); sendState() }
    func pause() { if player != nil { engine.async { libvlc_media_player_pause(self.player) } } }
    func setVolume(_ value: Int32) { volume = min(100, max(0, value)); if player != nil { let v = volume; engine.async { libvlc_audio_set_volume(self.player, v) } }; sendState() }
    func toggleMute() { muted.toggle(); if player != nil { let m = muted; engine.async { libvlc_audio_set_mute(self.player, m ? 1 : 0) } }; sendState() }
    func step(_ direction: Int) { web.evaluateJavaScript("stepChannel(\(direction))", completionHandler: nil) }
    @objc func showMenu() { hideInfo();visible = true; web?.isHidden = false; window?.makeFirstResponder(web); web?.evaluateJavaScript("restoreFocus()", completionHandler: nil) }
    func hideMenu() { visible = false; web.isHidden = true; window.makeFirstResponder(surface) }
    func tick() {
        if Date().timeIntervalSince(lastGuideTick)>30 {lastGuideTick=Date();if let item=selectedPlaylist{epg?.refresh(item)};sendEPG()}
        guard player != nil, current != nil, engineReady else { return }
        let state = libvlc_media_player_get_state(player)
        let elapsed = Date().timeIntervalSince(playbackStart)
        switch state {
        case 3: status = "In riproduzione"
        case 4: status = "In pausa"
        case 2: status = "Buffering…"
        case 6 where elapsed > 2, 7 where elapsed > 2:
            stop(); report(state == 7 ? "Il canale non è raggiungibile o il formato non è riproducibile. Seleziona un altro canale o riprova." : "Riproduzione terminata."); return
        default: break
        }
        if elapsed > 45 && (state == 0 || state == 1 || state == 2) { stop(); report("Tempo di connessione scaduto. Verifica la lista o riprova il canale."); return }
        if state==3 {let ratio=maciptv_ratio(player);if ratio>0 && abs(ratio-videoRatio)>0.01 {videoRatio=ratio;applyRatio()}}
        if infoVisible {updateInfo()}
        if visible { sendState() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        saveWindow();try? saveLibrary();browseSave?.cancel();infoTimer?.invalidate();timer?.invalidate(); loadTask?.cancel()
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        guard player != nil else { return .terminateNow }
        engine.async {
            libvlc_media_player_stop(self.player); libvlc_media_player_release(self.player); libvlc_release(self.instance)
            self.perform(#selector(self.finishTermination), on: .main, with: nil, waitUntilDone: false)
        }
        return .terminateLater
    }
    @objc func finishTermination() { NSApp.reply(toApplicationShouldTerminate: true) }
    func runSmoke() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--fixture"), i + 1 < args.count else { return }
        let url = args[i + 1].hasPrefix("http") ? URL(string: args[i + 1])! : URL(fileURLWithPath: args[i + 1])
        let channel: Channel
        if url.isFileURL && ["m3u", "m3u8"].contains(url.pathExtension.lowercased()),
           let data = try? Data(contentsOf: url), let parsed = try? M3U.parse(data, base: url), let first = parsed.first { channel = first }
        else { channel = Channel(id: "fixture", name: "Test locale", group: "Test", url: url.absoluteString, logo: "", headers: [:]) }
        catalog = Catalog(raw: "", source: "", base: "", channels: [channel]); volume = 0; sendCatalog(); play(channel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.smokeTime = libvlc_media_player_get_time(self.player)
            self.showMenu(); self.sendState();self.toggleInfo()
            self.web.evaluateJavaScript("document.querySelectorAll('.channel').length") { result, error in
                print("SMOKE catalogRows=\(result ?? "nil") jsError=\(String(describing: error)) time=\(self.smokeTime)")
            }
            self.toggleBorderless()
            print("SMOKE floating=\(self.window.level == .floating) borderless=\(!self.window.styleMask.contains(.titled))")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            let time = libvlc_media_player_get_time(self.player)
            var width: UInt32 = 0, height: UInt32 = 0
            _ = libvlc_video_get_size(self.player, 0, &width, &height)
            print("SMOKE videoOutputs=\(libvlc_media_player_has_vout(self.player)) size=\(width)x\(height)")
            print("SMOKE playbackAdvanced=\(time > self.smokeTime && self.smokeTime > 0) state=\(libvlc_media_player_get_state(self.player)) time=\(time)")
            self.restoreBorders(); self.showMenu()
            print("SMOKE restored=\(self.window.styleMask.contains(.titled) && self.window.level == .normal) overlay=\(!self.web.isHidden)")
            self.toggleFullscreen()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
            print("SMOKE fullscreen=\(self.window.styleMask.contains(.fullScreen))")
            self.toggleBorderless()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) {
            print("SMOKE fullscreenToFloating=\(self.floating && !self.window.styleMask.contains(.fullScreen))")
            self.restoreBorders(); self.showMenu()
            NSApp.terminate(nil)
        }
    }
}
setbuf(stdout, nil)
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
