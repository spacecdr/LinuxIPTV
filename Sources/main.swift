import Cocoa
import WebKit
import UniformTypeIdentifiers

final class TVWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
final class VideoSurface: NSView {
    var onClick: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        if event.clickCount == 2 { onClick?(); return }
        if !window.styleMask.contains(.titled) && !window.styleMask.contains(.fullScreen) {
            let p = convert(event.locationInWindow, from: nil)
            if p.x > bounds.width - 28 && p.y < 28 {
                let initial = window.frame, origin = NSEvent.mouseLocation
                while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                    if next.type == .leftMouseUp { break }
                    let current = NSEvent.mouseLocation
                    let w = max(420, initial.width + current.x - origin.x)
                    let h = max(236, initial.height - current.y + origin.y)
                    window.setFrame(NSRect(x: initial.minX, y: initial.maxY-h, width: w, height: h), display: true)
                }
            } else { window.performDrag(with: event) }
        } else { onClick?() }
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
    var catalog: Catalog?
    var favorites = Set<String>()
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
            catalog = try store.load("catalog.json", as: Catalog.self)
            favorites = Set(try store.load("favorites.json", as: [String].self) ?? [])
        } catch { startError = "Impossibile leggere i dati salvati: \(error.localizedDescription)" }
        setupMenu()
        window = TVWindow(contentRect: savedFrame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MacIPTV"
        window.minSize = NSSize(width: 420, height: 236)
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = .black
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        surface = VideoSurface(frame: root.bounds)
        surface.autoresizingMask = [.width, .height]
        surface.onClick = { [weak self] in self?.showMenu() }
        root.addSubview(surface)
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "native")
        web = WKWebView(frame: root.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        root.addSubview(web)
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
            case 36, 76, 53, 51: self.showMenu()
            case 49: self.pause()
            case 126: self.step(1)
            case 125: self.step(-1)
            case 123: self.setVolume(self.volume - 5)
            case 124: self.setVolume(self.volume + 5)
            default:
                switch e.charactersIgnoringModifiers?.lowercased() {
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
        if !smoke && !ProcessInfo.processInfo.arguments.contains("--windowed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.window.toggleFullScreen(nil) }
        }
    }
    func setupMenu() {
        let bar = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "Apri lista M3U…", action: #selector(openFile), keyEquivalent: "o").target = self
        appMenu.addItem(withTitle: "Catalogo", action: #selector(showMenu), keyEquivalent: "l").target = self
        appMenu.addItem(withTitle: "Schermo intero / Finestra", action: #selector(toggleFullscreen), keyEquivalent: "f").target = self
        appMenu.addItem(withTitle: "Video senza bordi in primo piano", action: #selector(toggleBorderless), keyEquivalent: "b").target = self
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
        sendCatalog(); sendState()
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
        emit("receiveCatalog", ["channels": objects, "favorites": Array(favorites), "source": catalog?.source ?? ""])
    }
    func sendState() {
        emit("receiveState", ["current": current?.id ?? "", "name": current?.name ?? "Nessun canale in riproduzione", "status": status, "active": current != nil, "volume": volume, "muted": muted, "floating": floating, "fullscreen": window.styleMask.contains(.fullScreen)])
    }
    func report(_ message: String) { showMenu(); emit("showError", ["message": message]) }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
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
                do { try store.save(Array(updated), as: "favorites.json"); favorites = updated; emit("receiveFavorites", Array(favorites)) } catch { report(error.localizedDescription) }
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
    @objc func openFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "m3u"), UTType(filenameExtension: "m3u8"), .plainText].compactMap { $0 }; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { result in
            if result == .OK, let url = panel.url { self.loadTask?.cancel(); self.generation += 1; self.readPlaylist(url, source: "", base: url) }
        }
    }
    func readPlaylist(_ url: URL, source: String, base: URL) {
        let token = generation
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= M3U.limit else { throw PlaylistError.invalid("La lista supera 20 MB.") }
                let data = try Data(contentsOf: url)
                let channels = try M3U.parse(data, base: base)
                let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                let value = Catalog(raw: raw, source: source, base: base.absoluteString, channels: channels)
                DispatchQueue.main.async {
                    guard token == self.generation else { return }
                    do {
                        try self.store.save(value, as: "catalog.json"); self.catalog = value; self.status = "\(channels.count) canali caricati"; self.sendCatalog(); self.sendState()
                    } catch { self.report("Salvataggio non riuscito: \(error.localizedDescription)") }
                }
            } catch { DispatchQueue.main.async { if token == self.generation { self.report(error.localizedDescription) } } }
        }
    }
    func importURL(_ text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { report("Inserisci un URL HTTP o HTTPS valido."); return }
        loadTask?.cancel(); generation += 1; let token = generation
        status = "Scaricamento lista…"; sendState()
        var request = URLRequest(url: url); request.timeoutInterval = 45
        loadTask = URLSession.shared.downloadTask(with: request) { temp, response, error in
            if let error = error as NSError?, error.code == NSURLErrorCancelled { return }
            guard let temp = temp, error == nil, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                DispatchQueue.main.async { if token == self.generation { self.report("Download non riuscito. La lista precedente è stata conservata.") } }; return
            }
            // The URLSession temporary file disappears when this completion handler returns.
            do {
                let size = try temp.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= M3U.limit else { throw PlaylistError.invalid("La lista supera 20 MB.") }
                let data = try Data(contentsOf: temp)
                let channels = try M3U.parse(data, base: http.url ?? url)
                let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                let value = Catalog(raw: raw, source: url.absoluteString, base: (http.url ?? url).absoluteString, channels: channels)
                DispatchQueue.main.async {
                    guard token == self.generation else { return }
                    do { try self.store.save(value, as: "catalog.json"); self.catalog = value; self.status = "\(channels.count) canali caricati"; self.sendCatalog(); self.sendState() }
                    catch { self.report(error.localizedDescription) }
                }
            } catch { DispatchQueue.main.async { if token == self.generation { self.report(error.localizedDescription) } } }
        }; loadTask?.resume()
    }
    func exportFile() {
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
    func stop() { playbackGeneration += 1; engineReady = false; current = nil; status = "Riproduzione arrestata"; if player != nil { engine.async { libvlc_media_player_stop(self.player) } }; showMenu(); sendState() }
    func pause() { if player != nil { engine.async { libvlc_media_player_pause(self.player) } } }
    func setVolume(_ value: Int32) { volume = min(100, max(0, value)); if player != nil { let v = volume; engine.async { libvlc_audio_set_volume(self.player, v) } }; sendState() }
    func toggleMute() { muted.toggle(); if player != nil { let m = muted; engine.async { libvlc_audio_set_mute(self.player, m ? 1 : 0) } }; sendState() }
    func step(_ direction: Int) { web.evaluateJavaScript("stepChannel(\(direction))", completionHandler: nil) }
    @objc func showMenu() { visible = true; web?.isHidden = false; window?.makeFirstResponder(web); web?.evaluateJavaScript("restoreFocus()", completionHandler: nil) }
    func hideMenu() { visible = false; web.isHidden = true; window.makeFirstResponder(surface) }
    @objc func toggleFullscreen() {
        if floating { restoreBorders() }
        window.toggleFullScreen(nil)
    }
    @objc func toggleBorderless() {
        if window.styleMask.contains(.fullScreen) { pendingBorderless = true; window.toggleFullScreen(nil); return }
        if floating { restoreBorders() } else {
            savedFrame = window.frame
            floating = true
            window.styleMask = [.borderless, .resizable]
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.setFrame(NSRect(x: savedFrame.minX, y: savedFrame.minY, width: 640, height: 360), display: true)
            window.makeKeyAndOrderFront(nil)
            if current != nil { hideMenu() }
        }
        sendState()
    }
    func restoreBorders() {
        floating = false; window.level = .normal
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior = [.fullScreenPrimary]
        window.setFrame(savedFrame, display: true); window.makeKeyAndOrderFront(nil)
    }
    func windowDidExitFullScreen(_ notification: Notification) { if pendingBorderless { pendingBorderless = false; toggleBorderless() }; sendState() }
    func windowDidEnterFullScreen(_ notification: Notification) { sendState() }
    func tick() {
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
        if visible { sendState() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        timer?.invalidate(); loadTask?.cancel()
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
            self.showMenu(); self.sendState()
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
