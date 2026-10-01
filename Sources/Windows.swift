import Cocoa
struct WindowSession: Codable {
    var normal = "{{100, 100}, {1120, 700}}"
    var floating = "{{140, 140}, {640, 360}}"
    var mode = "fullscreen"
}
extension App {
    func fitOnScreen(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.max { a,b in a.visibleFrame.intersection(frame).width*a.visibleFrame.intersection(frame).height < b.visibleFrame.intersection(frame).width*b.visibleFrame.intersection(frame).height } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return frame }
        var f = frame; f.size.width = min(max(420,f.width),bounds.width); f.size.height = min(max(236,f.height),bounds.height)
        f.origin.x = min(max(f.minX,bounds.minX),bounds.maxX-f.width); f.origin.y = min(max(f.minY,bounds.minY),bounds.maxY-f.height); return f
    }
    func saveWindow() {
        guard window != nil, !transitioning else { return }
        if floating { session.floating = NSStringFromRect(window.frame); session.mode = "window" }
        else if window.styleMask.contains(.fullScreen) { session.mode = "fullscreen" }
        else { session.normal = NSStringFromRect(window.frame); session.mode = "window" }
        try? store?.save(session, as: "session.json")
    }
    func windowDidMove(_ notification: Notification) { saveWindow() }
    func windowDidResize(_ notification: Notification) { saveWindow() }
    func windowWillEnterFullScreen(_ notification: Notification) { transitioning = true }
    func windowWillExitFullScreen(_ notification: Notification) { transitioning = true }
    func enterFloating() {
        guard current != nil else { return }
        transitioning = true
        floating = true; window.styleMask = [.borderless,.resizable]; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        window.setFrame(fitOnScreen(NSRectFromString(session.floating)), display: true); transitioning = false; applyRatio(); hideMenu(); saveWindow()
    }
    func leaveFloating() {
        transitioning = true
        session.floating = NSStringFromRect(window.frame); floating = false
        window.level = .normal; window.styleMask = [.titled,.closable,.miniaturizable,.resizable]; window.collectionBehavior = [.fullScreenPrimary]
        window.setFrame(fitOnScreen(NSRectFromString(session.normal)), display: true); transitioning = false; applyRatio()
    }
    @objc func toggleFullscreen() {
        guard !transitioning else { return }
        hideInfo()
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil); return }
        fullReturnFloating = floating
        if floating { leaveFloating() } else { session.normal = NSStringFromRect(window.frame) }
        window.toggleFullScreen(nil)
    }
    @objc func toggleBorderless() {
        guard current != nil, !transitioning else { return }
        if floating {
            let full = borderReturnFullscreen; leaveFloating()
            if full { fullReturnFloating = false; window.toggleFullScreen(nil) }
            saveWindow(); return
        }
        borderReturnFullscreen = window.styleMask.contains(.fullScreen)
        if borderReturnFullscreen { pendingBorderless = true; fullReturnFloating = false; window.toggleFullScreen(nil) }
        else { session.normal = NSStringFromRect(window.frame); enterFloating() }
    }
    func escape() { if floating { toggleBorderless() } else if infoVisible { hideInfo() } else { showMenu() } }
    func restoreBorders() { if floating { leaveFloating() }; saveWindow() }
    func windowDidExitFullScreen(_ notification: Notification) {
        transitioning = false
        if (pendingBorderless || fullReturnFloating) && current != nil { pendingBorderless = false; fullReturnFloating = false; enterFloating() }
        else { pendingBorderless = false; fullReturnFloating = false; applyRatio(); saveWindow() }
        sendState()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { transitioning = false; session.mode = "fullscreen"; saveWindow(); sendState() }
    func applyRatio() {
        guard current != nil, videoRatio > 0 else { window.contentAspectRatio = .zero; return }
        window.contentAspectRatio = NSSize(width: videoRatio, height: 1)
        guard !window.styleMask.contains(.fullScreen), !transitioning else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        var size = NSSize(width: content.width, height: content.width/videoRatio)
        if let screen = window.screen, size.height > screen.visibleFrame.height-40 { size.height = screen.visibleFrame.height-40; size.width = size.height*videoRatio }
        window.setContentSize(size)
    }
}
