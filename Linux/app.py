#!/usr/bin/env python3
"""LinuxIPTV: original MacIPTV web UI hosted in GTK, with native LibVLC playback."""
from __future__ import annotations

import argparse
import copy
import ctypes
import ctypes.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

# LibVLC 3 embeds into X11. On Wayland desktops use XWayland deliberately.
os.environ['GDK_BACKEND'] = 'x11'
x11 = ctypes.CDLL(ctypes.util.find_library('X11') or 'libX11.so.6')
x11.XInitThreads()
import gi
gi.require_foreign('cairo')
gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
gi.require_version('GdkX11', '3.0')
gi.require_version('WebKit2', '4.1')
from gi.repository import Gdk, GdkX11, GLib, Gtk, WebKit2
import cairo

from core import BROWSE, Library, Matcher, M3U_LIMIT, Store, epg_payload, fetch, valid_http
from epg import EPGService
from player import Player

ROOT = Path(__file__).resolve().parent.parent


class App:
    def __init__(self, args):
        self.args, self.closed, self.ready = args, False, False
        self.smoke_directory = tempfile.TemporaryDirectory(prefix='linuxiptv-smoke-') if args.smoke_test else None
        self.store = Store(self.smoke_directory.name if self.smoke_directory else args.data_dir)
        self.library = Library(self.store)
        self.session = self.store.load('session.json', dict(normal=[100, 100, 1120, 700], floating=[140, 140, 640, 360], mode='fullscreen'))
        self.current, self.playing_id, self.visible, self.info_visible = None, '', True, False
        self.fullscreen, self.floating = False, False
        self.geometry_settle = 0
        self.border_return_full, self.full_return_float = False, False
        self.pending_float = False
        self.volume, self.muted, self.buffer = 70, args.smoke_test, 3
        self.status = 'Carica una lista M3U per iniziare'
        self.import_generation, self.play_generation = 0, 0
        self.last_epg, self.info_deadline, self.browse_timer = 0, 0, None
        self.info_bounds = (0, 0, 0, 0)
        self.ratio = 0
        self.click_timer = None
        self.engine_ready = False
        self.epg = EPGService(self.store, self.work, self.send_epg)
        self.window = Gtk.Window(title='LinuxIPTV')
        GLib.set_prgname('linuxiptv')
        GLib.set_application_name('LinuxIPTV')
        self.window.set_icon_from_file(str(ROOT / 'docs/assets/icon.svg'))
        self.window.set_default_size(1120, 700)
        self.window.set_size_request(420, 236)
        self.window.connect('delete-event', self.close)
        self.window.connect('key-press-event', self.key)
        self.window.connect('window-state-event', self.window_state)
        self.window.connect('configure-event', self.configure)
        self.restore_geometry('normal')
        self.overlay = Gtk.Overlay()
        self.window.add(self.overlay)
        self.surface = Gtk.DrawingArea()
        self.surface.set_can_focus(True)
        self.surface.connect('draw', self.draw_background)
        self.surface.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.POINTER_MOTION_MASK)
        self.surface.connect('button-press-event', self.mouse_press)
        self.surface.connect('button-release-event', self.mouse_release)
        self.surface.connect('motion-notify-event', self.mouse_motion)
        self.overlay.add(self.surface)
        self.web = self.create_web('index')
        self.info = self.create_web('info')
        self.overlay.add_overlay(self.web)
        self.overlay.add_overlay(self.info)
        self.info.set_no_show_all(True)
        self.window.show_all()
        self.redraw_pending = False
        self.player = Player(self.queue_video_draw, silent=args.smoke_test)
        self.web.load_uri((ROOT / 'Resources/index.html').as_uri())
        self.info.load_uri((ROOT / 'Resources/info.html').as_uri())
        self.info.hide()
        GLib.timeout_add(250, self.tick)
        if not args.windowed and not args.smoke_test and self.session.get('mode') == 'fullscreen':
            self.window.fullscreen()
        if args.smoke_test:
            self.smoke_started = time.monotonic()
            GLib.timeout_add_seconds(50, self.smoke_timeout)

    def create_web(self, name):
        manager = WebKit2.UserContentManager()
        manager.connect('script-message-received::native', self.message, name)
        manager.register_script_message_handler('native')
        context = WebKit2.WebContext.new_ephemeral()
        if name == 'info':
            manager.add_style_sheet(WebKit2.UserStyleSheet.new(':root{color-scheme:dark}.remote select{appearance:none;background:#224158;color:#edf6ff}', WebKit2.UserContentInjectedFrames.TOP_FRAME, WebKit2.UserStyleLevel.USER, None, None))
        web = WebKit2.WebView(web_context=context, user_content_manager=manager)
        web.set_background_color(Gdk.RGBA(0, 0, 0, 0))
        web.get_settings().set_enable_write_console_messages_to_stdout(self.args.smoke_test)
        web.connect('decide-policy', self.policy, name)
        web.connect('load-changed', self.loaded, name)
        web.connect('context-menu', lambda *args: True)
        return web

    def policy(self, web, decision, kind, name):
        if kind in (WebKit2.PolicyDecisionType.NAVIGATION_ACTION, WebKit2.PolicyDecisionType.NEW_WINDOW_ACTION):
            uri = decision.get_navigation_action().get_request().get_uri()
            if uri != (ROOT / f'Resources/{name}.html').as_uri() or kind == WebKit2.PolicyDecisionType.NEW_WINDOW_ACTION:
                decision.ignore()
                return True
        return False

    def loaded(self, web, event, name):
        if event != WebKit2.LoadEvent.FINISHED:
            return
        if name == 'index':
            self.ready = True
            self.js("document.title='LinuxIPTV';document.querySelector('h1').firstChild.textContent='Linux';document.querySelector('.brand small').textContent='La tua televisione, su Linux.'")
            self.send_all()
            if self.library.selected:
                self.epg.refresh(self.library.selected)
            if self.args.smoke_test:
                self.smoke_begin()
            elif self.args.playlist:
                self.import_list(Path(self.args.playlist).resolve().as_uri(), local=True)

    def js(self, code, web=None, callback=None):
        if self.closed:
            return
        target = web or self.web
        def finish(view, result, _):
            try:
                value = view.evaluate_javascript_finish(result)
                if callback:
                    callback(json.loads(value.to_json(0)) if value else None)
            except GLib.Error as error:
                if self.args.smoke_test:
                    self.fail('JavaScript: ' + error.message)
        target.evaluate_javascript(code, -1, None, None, None, finish, None)

    def emit(self, method, data, web=None):
        if self.ready:
            self.js(f'{method}({json.dumps(data, ensure_ascii=False)})', web)

    def work(self, function, callback):
        def worker():
            try:
                result, error = function(), None
            except Exception as failure:
                result, error = None, failure
            def deliver():
                if not self.closed:
                    callback(result, error)
                return False
            GLib.idle_add(deliver)
        threading.Thread(target=worker, daemon=True).start()

    def send_all(self):
        self.send_library()
        self.send_catalog()
        self.send_state()

    def send_library(self):
        self.emit('receiveLibrary', dict(selected=self.library.data['selectedID'] or '', lists=[
            dict(id=p['id'], name=p['name'], source=p['catalog']['source'], epg=p.get('epgOverride', ''),
                 updated=p['updated'], count=len(p['catalog']['channels'])) for p in self.library.data['playlists']]))

    def send_catalog(self):
        item = self.library.selected
        self.emit('receiveCatalog', dict(channels=item['catalog']['channels'] if item else [],
                  favorites=item['favorites'] if item else [], source=item['catalog']['source'] if item else '',
                  browse=item.get('browse', BROWSE) if item else BROWSE))
        self.send_epg()

    def send_state(self):
        self.emit('receiveState', dict(current=self.current['id'] if self.current and self.playing_id == self.library.data['selectedID'] else '',
                  name=self.current['name'] if self.current else '', status=self.status, active=bool(self.current),
                  volume=self.volume, muted=self.muted, floating=self.floating, fullscreen=self.fullscreen))

    def send_epg(self):
        item = self.library.selected
        payload = epg_payload(item, self.epg.guides.get(item['id']), self.epg.states.get(item['id'], 'Guida non ancora caricata'), item['id'] in self.epg.busy) if item else dict(programmes={}, diagnostics={}, status='Nessuna lista caricata', busy=False)
        self.emit('receiveEPG', payload)
        if self.info_visible:
            self.update_info()

    def report(self, message):
        self.show_menu()
        self.emit('showError', dict(message=message))

    def message(self, manager, result, source):
        try:
            body = json.loads(result.get_js_value().to_json(0))
            if isinstance(body, dict):
                self.action(body, source)
        except (ValueError, TypeError, KeyError, OSError):
            self.report('Operazione non riuscita. I dati precedenti sono conservati.')

    def action(self, body, source='index'):
        action, item = body.get('action'), self.library.selected
        if self.args.smoke_test and action not in ('browse','infoBounds'):
            print('ACTION', action, flush=True)
        if action == 'infoBounds' and source == 'info':
            self.info_bounds = tuple(float(body[k]) for k in ('x', 'y', 'width', 'height'))
            self.info_input_region()
        elif action == 'browse' and item:
            item['browse'] = {key: body.get(key, value) for key, value in BROWSE.items()}
            if self.browse_timer:
                GLib.source_remove(self.browse_timer)
            self.browse_timer = GLib.timeout_add(400, self.save_browse)
        elif action == 'selectPlaylist':
            if any(p['id'] == body.get('id') for p in self.library.data['playlists']):
                data = copy.deepcopy(self.library.data)
                data['selectedID'] = body['id']
                self.library.commit(data)
                self.send_all()
                self.epg.refresh(self.library.selected)
        elif action == 'savePlaylist' and not self.current:
            self.edit_playlist(body)
        elif action == 'removePlaylist' and item and not self.current:
            self.remove_playlist(item)
        elif action == 'open' and not self.current:
            self.open_file()
        elif action in ('import', 'refresh') and not self.current:
            self.import_list(body.get('url', '') if action == 'import' else item['catalog']['source'] if item else '')
        elif action == 'export' and not self.current:
            self.export_file()
        elif action == 'refreshEPG' and item:
            self.epg.refresh(item, True)
        elif action == 'favorite' and item:
            identity = body.get('id')
            if any(c['id'] == identity for c in item['catalog']['channels']):
                def change(p):
                    values = set(p['favorites'])
                    values.symmetric_difference_update([identity])
                    p['favorites'] = sorted(values)
                self.library.update(item['id'], change)
                self.emit('receiveFavorites', self.library.selected['favorites'])
        elif action in ('play', 'external') and item:
            channel = next((c for c in item['catalog']['channels'] if c['id'] == body.get('id')), None)
            if channel:
                self.play(channel) if action == 'play' else self.external(channel)
        elif action == 'hide' and self.current:
            self.hide_menu()
        elif action == 'stop':
            self.stop()
        elif action == 'pause':
            self.player.submit(self.player.media_player_pause, self.player.handle)
        elif action == 'volume':
            self.volume = min(100, max(0, int(body.get('value', 70))))
            self.player.submit(self.player.audio_set_volume, self.player.handle, self.volume)
        elif action == 'mute':
            self.muted = not self.muted
            self.player.submit(self.player.audio_set_mute, self.player.handle, int(self.muted))
        elif action == 'buffer':
            self.buffer = min(10, max(1, int(body.get('value', 3))))
        elif action == 'full':
            self.toggle_fullscreen()
        elif action == 'border':
            self.toggle_borderless()
        elif action == 'info':
            self.toggle_info()
        elif action == 'infoStep':
            self.js(f'stepChannel({1 if int(body.get("delta", 1)) > 0 else -1})')
        elif action == 'escape':
            if self.info_visible:
                self.hide_info()
            elif self.current and self.visible:
                self.stop()
            else:
                self.show_menu()
        elif action == 'back':
            self.toggle_borderless() if self.floating else self.show_menu()
        self.send_state()

    def save_browse(self):
        self.browse_timer = None
        try:
            self.library.commit(self.library.data)
        except OSError:
            self.report('Impossibile salvare la posizione nel catalogo.')
        return False

    def import_list(self, address, local=False, target=None, name=None, guide=None):
        if self.current:
            return
        if not local and not valid_http(address):
            self.report('Inserisci un URL HTTP/HTTPS valido. Le liste locali vanno ricaricate con Apri file M3U.')
            return
        item = self.library.selected or {}
        target = item.get('id', '') if target is None else target
        name = item.get('name', 'Lista') if name is None else name
        guide = item.get('epgOverride', '') if guide is None else guide
        self.import_generation += 1
        token = self.import_generation
        self.status = 'Caricamento lista…'
        def done(result, error):
            if token != self.import_generation:
                return
            if error:
                self.report('Download o lettura non riuscita. La lista precedente è conservata.')
                return
            data, base = result
            try:
                self.library.install(data, '' if local else address, base, target, name, guide)
                self.status = f"{len(self.library.selected['catalog']['channels'])} canali caricati"
                self.send_all()
                self.epg.refresh(self.library.selected, True)
            except (ValueError, OSError) as failure:
                self.report(str(failure) if isinstance(failure, ValueError) else 'Salvataggio non riuscito: lista precedente conservata.')
        self.work(lambda: fetch(address, M3U_LIMIT), done)

    def open_file(self, target=None, name=None, guide=None):
        if self.current:
            return
        dialog = Gtk.FileChooserDialog(title='Apri lista M3U', transient_for=self.window, action=Gtk.FileChooserAction.OPEN)
        dialog.add_buttons('Annulla', Gtk.ResponseType.CANCEL, 'Apri', Gtk.ResponseType.OK)
        file_filter = Gtk.FileFilter()
        file_filter.set_name('Playlist M3U / M3U8')
        for pattern in ('*.m3u', '*.m3u8', '*.M3U', '*.txt'):
            file_filter.add_pattern(pattern)
        dialog.add_filter(file_filter)
        if dialog.run() == Gtk.ResponseType.OK:
            self.import_list(Path(dialog.get_filename()).as_uri(), True, target, name, guide)
        dialog.destroy()

    def export_file(self):
        if not self.library.selected:
            return
        dialog = Gtk.FileChooserDialog(title='Esporta lista', transient_for=self.window, action=Gtk.FileChooserAction.SAVE)
        dialog.add_buttons('Annulla', Gtk.ResponseType.CANCEL, 'Salva', Gtk.ResponseType.OK)
        dialog.set_current_name('playlist.m3u')
        dialog.set_do_overwrite_confirmation(True)
        if dialog.run() == Gtk.ResponseType.OK:
            path = Path(dialog.get_filename())
            fd, temporary = tempfile.mkstemp(prefix='.linuxiptv-', dir=path.parent)
            try:
                with os.fdopen(fd, 'w') as stream:
                    stream.write(self.library.selected['catalog']['raw'])
                os.replace(temporary, path)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
        dialog.destroy()

    def edit_playlist(self, body):
        identity, name = body.get('id', ''), body.get('name', 'Lista').strip() or 'Lista'
        source, guide = body.get('source', '').strip(), body.get('epg', '').strip()
        if guide and not valid_http(guide):
            self.report('URL XMLTV non valido.')
            return
        old = next((p for p in self.library.data['playlists'] if p['id'] == identity), None)
        if old and source == old['catalog']['source']:
            self.library.update(identity, lambda p: p.update(name=name, epgOverride=guide))
            self.send_library()
            self.epg.refresh(next(p for p in self.library.data['playlists'] if p['id'] == identity), True)
        elif source:
            self.import_list(source, target=identity, name=name, guide=guide)
        else:
            self.open_file(identity, name, guide)

    def remove_playlist(self, item):
        dialog = Gtk.MessageDialog(transient_for=self.window, modal=True, message_type=Gtk.MessageType.QUESTION,
                                   buttons=Gtk.ButtonsType.NONE, text=f"Rimuovere {item['name']}?")
        dialog.format_secondary_text('Verranno rimossi la copia locale e i preferiti. La sorgente originale non viene modificata.')
        dialog.add_buttons('Annulla', Gtk.ResponseType.CANCEL, 'Rimuovi', Gtk.ResponseType.OK)
        response = dialog.run()
        dialog.destroy()
        if response == Gtk.ResponseType.OK:
            data = copy.deepcopy(self.library.data)
            data['playlists'] = [p for p in data['playlists'] if p['id'] != item['id']]
            data['selectedID'] = data['playlists'][0]['id'] if data['playlists'] else None
            self.library.commit(data)
            self.epg.cancel(item['id'])
            self.send_all()

    def play(self, channel):
        keep_info = self.info_visible
        self.hide_info()
        self.current, self.playing_id = channel, self.library.data['selectedID']
        self.play_generation += 1
        token = self.play_generation
        self.engine_ready = False
        self.play_started = time.monotonic()
        self.status, self.ratio = 'Connessione…', 0
        self.clear_ratio()
        self.hide_menu()
        self.send_state()
        future = self.player.play(channel, self.buffer, self.volume, self.muted)
        def done(future):
            def complete():
                if self.closed or token != self.play_generation:
                    return False
                if future.exception():
                    self.stop()
                    self.report('Impossibile avviare il canale.')
                else:
                    self.engine_ready = True
                    self.play_started = time.monotonic()
                return False
            GLib.idle_add(complete)
        future.add_done_callback(done)
        if keep_info:
            self.toggle_info()

    def stop(self):
        self.hide_info()
        self.play_generation += 1
        self.engine_ready = False
        self.current = None
        self.full_return_float = self.pending_float = False
        if self.floating:
            self.leave_float()
        self.ratio = 0
        self.clear_ratio()
        self.player.submit(self.player.media_player_stop, self.player.handle)
        self.status = 'Riproduzione arrestata'
        self.show_menu()
        self.send_state()

    def external(self, channel):
        safe = lambda text: text.replace('\r', ' ').replace('\n', ' ')
        options = '\n'.join(f'#EXTVLCOPT:{k}={v}' for k, v in channel['headers'].items() if '\n' not in v and '\r' not in v)
        self.store.write('external.m3u', f"#EXTM3U\n#EXTINF:-1,{safe(channel['name'])}\n{options}\n{safe(channel['url'])}\n".encode())
        try:
            subprocess.Popen(['vlc', '--fullscreen', str(self.store.directory / 'external.m3u')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.stop()
        except OSError:
            self.report('VLC esterno non è installato.')

    def show_menu(self):
        self.hide_info()
        self.visible = True
        self.web.show()
        self.web.grab_focus()
        self.js('restoreFocus()')

    def hide_menu(self):
        self.visible = False
        self.web.hide()
        self.surface.grab_focus()

    def toggle_info(self):
        if not self.current:
            return
        if self.info_visible:
            self.hide_info()
            return
        self.info_visible = True
        self.info.show()
        self.update_info()
        self.js("document.body.classList.add('shown');reportBounds()", self.info)
        self.info_deadline = time.monotonic() + 5

    def hide_info(self):
        self.info_visible = False
        self.js("document.body.classList.remove('shown')", self.info)
        def finish():
            if not self.info_visible:
                self.info.hide()
            return False
        GLib.timeout_add(230, finish)
        (self.web if self.visible else self.surface).grab_focus()

    def info_input_region(self):
        if self.info.get_window():
            x, y, width, height = self.info_bounds
            region = cairo.Region(cairo.RectangleInt(int(x), int(y), max(1, int(width)), max(1, int(height))))
            self.info.get_window().input_shape_combine_region(region, 0, 0)

    def update_info(self):
        if not self.current:
            return
        width, height = self.player.size()
        data = dict(name=self.current['name'], logo=self.current['logo'], volume=self.volume, muted=self.muted,
                    buffer=self.buffer, resolution=f'{width}×{height}' if width else 'Risoluzione in rilevamento…')
        guide = self.epg.guides.get(self.playing_id)
        if guide:
            data.update(Matcher(guide).schedule(self.current))
        self.emit('renderInfo', data, self.info)

    def clear_ratio(self):
        geometry = Gdk.Geometry()
        geometry.min_width, geometry.min_height = 420, 236
        self.window.set_geometry_hints(None, geometry, Gdk.WindowHints.MIN_SIZE)

    def apply_ratio(self):
        width, height = self.player.size()
        if not width or not height:
            return
        ratio = self.player.display_ratio()
        if abs(self.ratio - ratio) < .01:
            return
        self.ratio = ratio
        geometry = Gdk.Geometry()
        geometry.min_aspect = geometry.max_aspect = ratio
        self.window.set_geometry_hints(None, geometry, Gdk.WindowHints.ASPECT)
        if not self.fullscreen:
            w, _ = self.window.get_size()
            display = self.window.get_display()
            monitor = display.get_monitor_at_window(self.window.get_window())
            max_height = monitor.get_workarea().height - 50
            h = min(max_height, max(236, int(w / ratio)))
            self.window.resize(max(420, int(h * ratio)), h)

    def geometry(self):
        x, y = self.window.get_position()
        w, h = self.window.get_size()
        return [x, y, w, h]

    def restore_geometry(self, kind):
        self.geometry_settle = time.monotonic() + .7
        x, y, width, height = self.session.get(kind, [100, 100, 1120, 700])
        display = Gdk.Display.get_default()
        monitor = display.get_monitor_at_point(int(x), int(y))
        bounds = monitor.get_workarea()
        width, height = min(max(420, int(width)), bounds.width), min(max(236, int(height)), bounds.height)
        self.window.move(min(max(bounds.x, int(x)), bounds.x + bounds.width - width), min(max(bounds.y, int(y)), bounds.y + bounds.height - height))
        self.window.resize(width, height)

    def configure(self, *args):
        if not self.fullscreen and not self.pending_float and time.monotonic() > self.geometry_settle:
            self.session['floating' if self.floating else 'normal'] = self.geometry()
        return False

    def toggle_fullscreen(self):
        self.hide_info()
        if self.fullscreen:
            self.window.unfullscreen()
        else:
            self.full_return_float = self.floating
            if self.floating:
                self.leave_float()
            else:
                self.session['normal'] = self.geometry()
            self.window.fullscreen()

    def window_state(self, window, event):
        old = self.fullscreen
        self.fullscreen = bool(event.new_window_state & Gdk.WindowState.FULLSCREEN)
        self.session['mode'] = 'fullscreen' if self.fullscreen else 'window'
        if old and not self.fullscreen and (self.pending_float or self.full_return_float):
            self.pending_float = self.full_return_float = False
            if self.current:
                GLib.idle_add(self.enter_float)
        self.send_state()
        return False

    def enter_float(self):
        self.floating = True
        self.window.set_decorated(False)
        self.window.set_keep_above(True)
        self.restore_geometry('floating')
        self.hide_menu()
        self.send_state()
        return False

    def leave_float(self):
        self.session['floating'] = self.geometry()
        self.floating = False
        self.window.set_keep_above(False)
        self.window.set_decorated(True)
        self.restore_geometry('normal')

    def toggle_borderless(self):
        if not self.current:
            return
        if self.floating:
            self.leave_float()
            if self.border_return_full:
                GLib.timeout_add(250, lambda: (self.window.fullscreen(), False)[1])
        else:
            self.border_return_full = self.fullscreen
            if self.fullscreen:
                self.pending_float = True
                self.full_return_float = False
                self.window.unfullscreen()
            else:
                self.session['normal'] = self.geometry()
                self.enter_float()
        self.send_state()

    def key(self, window, event):
        key = Gdk.keyval_name(event.keyval)
        control = bool(event.state & Gdk.ModifierType.CONTROL_MASK)
        if control:
            if key.lower() == 'q':
                self.close()
            elif key.lower() == 'o':
                self.open_file()
            elif key.lower() == 'l':
                self.show_menu()
            elif key.lower() == 'f':
                self.toggle_fullscreen()
            else:
                return False
            return True
        if self.info_visible and key in ('Escape', 'BackSpace'):
            self.hide_info()
            return True
        if self.visible:
            return False
        actions = dict(Escape='escape', Return='menu', KP_Enter='menu', BackSpace='menu', space='pause',
                       f='full', b='border', i='info', m='mute', s='stop')
        if key in ('Up', 'Down'):
            self.action(dict(action='infoStep', delta=1 if key == 'Up' else -1))
        elif key in ('Left', 'Right'):
            self.action(dict(action='volume', value=self.volume + (5 if key == 'Right' else -5)))
        elif key.lower() in actions or key in actions:
            action = actions.get(key, actions.get(key.lower()))
            self.show_menu() if action == 'menu' else self.action(dict(action=action))
        else:
            return False
        return True

    def queue_video_draw(self):
        if self.closed or self.redraw_pending:
            return
        self.redraw_pending = True
        def draw():
            self.redraw_pending = False
            if not self.closed:
                self.surface.queue_draw()
            return False
        GLib.idle_add(draw)

    def draw_background(self, widget, context):
        context.set_source_rgb(0, 0, 0)
        context.paint()
        if self.current and hasattr(self, 'player'):
            self.player.draw(context, widget.get_allocated_width(), widget.get_allocated_height())
        return False

    def mouse_press(self, widget, event):
        if event.button != 1:
            return False
        if self.click_timer:
            GLib.source_remove(self.click_timer)
            self.click_timer = None
        self.press = (event.x_root, event.y_root, event.time, event.x, event.y)
        self.dragged = False
        if event.type == Gdk.EventType._2BUTTON_PRESS:
            self.press = None
            self.toggle_fullscreen()
        return True

    def mouse_motion(self, widget, event):
        press = getattr(self, 'press', None)
        if press and not self.fullscreen and abs(event.x_root - press[0]) + abs(event.y_root - press[1]) > 4:
            self.dragged = True
            self.press = None
            width, height = self.window.get_size()
            if self.floating and press[3] > width - 28 and press[4] > height - 28:
                self.window.begin_resize_drag(Gdk.WindowEdge.SOUTH_EAST, 1, int(press[0]), int(press[1]), press[2])
            else:
                self.window.begin_move_drag(1, int(press[0]), int(press[1]), press[2])
        return False

    def mouse_release(self, widget, event):
        if event.button == 1 and getattr(self, 'press', None) and not self.dragged:
            def click():
                self.click_timer = None
                if self.current and not self.visible:
                    self.toggle_info()
                return False
            self.click_timer = GLib.timeout_add(Gtk.Settings.get_default().get_property('gtk-double-click-time'), click)
        self.press = None
        return True

    def tick(self):
        if self.closed:
            return False
        now = time.monotonic()
        if now - self.last_epg > 30:
            self.last_epg = now
            if self.library.selected:
                self.epg.refresh(self.library.selected)
            self.send_epg()
        if self.current and self.engine_ready:
            state = self.player.media_player_get_state(self.player.handle)
            self.status = {3: 'In riproduzione', 4: 'In pausa', 2: 'Buffering…'}.get(state, self.status)
            if state in (6, 7) and now - self.play_started > 2:
                self.stop()
                self.report('Riproduzione terminata.' if state == 6 else 'Il canale non è raggiungibile o il formato non è riproducibile.')
            elif state in (0, 1, 2) and now - self.play_started > 45:
                self.stop()
                self.report('Tempo di connessione scaduto.')
            elif state == 3:
                self.player.sync_audio(self.volume, self.muted)
                self.apply_ratio()
            if self.visible:
                self.send_state()
        if self.info_visible:
            self.update_info()
            pointer = self.window.get_display().get_default_seat().get_pointer()
            _, x, y, _ = self.window.get_window().get_device_position(pointer)
            bx, by, bw, bh = self.info_bounds
            if bx <= x <= bx + bw and by <= y <= by + bh:
                self.info_deadline = now + 5
            elif now >= self.info_deadline:
                self.hide_info()
        return True

    def close(self, *args):
        if self.closed:
            return True
        try:
            self.store.save('session.json', self.session)
            self.library.commit(self.library.data)
        except OSError:
            print('Impossibile salvare la sessione.', file=sys.stderr)
        self.closed = True
        self.window.hide()
        future = self.player.close()
        def finish(_):
            GLib.idle_add(Gtk.main_quit)
        future.add_done_callback(finish)
        return True

    def fail(self, message):
        print('FAIL ' + message, flush=True)
        self.exit_code = 1
        self.close()

    def smoke_timeout(self):
        if not self.closed:
            self.fail('Timeout smoke test')
        return False

    def smoke_begin(self):
        from smoke import run
        run(self)


def main():
    parser = argparse.ArgumentParser(description='LinuxIPTV — playlist M3U, EPG e player VLC integrato')
    parser.add_argument('--windowed', action='store_true')
    parser.add_argument('--data-dir', type=Path, help='Directory dati alternativa')
    parser.add_argument('--playlist', help='Apri una playlist locale')
    parser.add_argument('--smoke-test', action='store_true', help='Test nativo con dati temporanei e audio muto')
    parser.add_argument('--fixture', help='Video locale o URL autorizzato per lo smoke test')
    parser.add_argument('--screenshot-dir', type=Path, help='Immagini dimostrative durante lo smoke test')
    args = parser.parse_args()
    if args.smoke_test and not args.fixture:
        parser.error('--smoke-test richiede --fixture')
    if not Gtk.init_check()[0]:
        parser.exit(1, 'Display X11 non disponibile. Su Wayland occorre XWayland.\n')
    try:
        app = App(args)
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(1, f'Avvio non riuscito: {error}\n')
    Gtk.main()
    if app.smoke_directory:
        app.smoke_directory.cleanup()
    return getattr(app, 'exit_code', 0)


if __name__ == '__main__':
    sys.exit(main())
