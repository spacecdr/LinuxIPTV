"""Isolated native integration check. Never loads the user's library."""
import datetime as dt
import json
from pathlib import Path
import time
from gi.repository import Gdk, GLib


def run(app):
    fixture = app.args.fixture
    if '://' not in fixture:
        fixture = Path(fixture).resolve().as_uri()
    now = time.time()
    stamp = lambda t: dt.datetime.fromtimestamp(t, dt.timezone.utc).strftime('%Y%m%d%H%M%S +0000')
    guide = app.store.directory / 'guide.xml'
    guide.write_text(f'<tv><channel id="demo"><display-name>Canale demo</display-name></channel><programme channel="demo" start="{stamp(now-600)}" stop="{stamp(now+3600)}"><title lang="it">Programma dimostrativo</title><desc>Guida sintetica per verifica Linux.</desc></programme></tv>')
    playlist = app.store.directory / 'test.m3u'
    playlist.write_text('#EXTM3U x-tvg-url="' + guide.as_uri() + '"\n' + ''.join(
        f'#EXTINF:-1 tvg-id="demo" group-title="Gruppo {i % 5}",Canale demo {i + 1}\n{fixture}\n' for i in range(75)))
    app.import_list(playlist.as_uri(), local=True)
    stage = dict(value=0, since=time.monotonic(), video_time=-1)

    def check(condition, label):
        if not condition:
            raise AssertionError(label)

    def capture(name):
        if not app.args.screenshot_dir:
            return
        app.args.screenshot_dir.mkdir(parents=True, exist_ok=True)
        width, height = app.window.get_size()
        image = Gdk.pixbuf_get_from_window(app.window.get_window(), 0, 0, width, height)
        if image:
            image.savev(str(app.args.screenshot_dir / name), 'png', [], [])

    def advance():
        stage['value'] += 1
        print('SMOKE stage', stage['value'], flush=True)
        stage['since'] = time.monotonic()

    def dom_first(value):
        try:
            check(value == [60, 'LinuxIPTV', 'Programma dimostrativo'], f'Catalogo/EPG DOM: {value}')
            channel = app.library.selected['catalog']['channels'][0]
            app.js(f"document.getElementById('fav-{channel['id']}').click()")
            stage['value'] = 1
            stage['since'] = time.monotonic()
        except Exception as error:
            app.fail(str(error))

    def pulse():
        if app.closed:
            return False
        try:
            elapsed = time.monotonic() - stage['since']
            current = stage['value']
            if current == 0 and app.library.selected and app.epg.guides:
                check(len(app.library.selected['catalog']['channels']) == 75, 'Import M3U')
                stage['value'] = -1
                app.js("[document.querySelectorAll('.channel').length,document.title,document.querySelector('.guide-now>span')?.textContent]", callback=dom_first)
            elif current == 1 and app.library.selected['favorites']:
                item = app.library.selected
                channel = item['catalog']['channels'][0]
                check(channel['id'] in item['favorites'], 'Preferito via bridge')
                check(channel['id'] in app.store.load('library.json')['playlists'][0]['favorites'], 'Persistenza preferiti')
                capture('catalogo-linux.png')
                app.js(f"document.getElementById('play-{channel['id']}').click()")
                advance()
            elif current == 2 and app.current and app.engine_ready and app.player.media_player_get_time(app.player.handle) > 700:
                check(app.player.media_player_has_vout(app.player.handle) > 0, 'Output video nativo')
                check(all(v > 0 for v in app.player.size()), f'Formato fixture: {app.player.size()}')
                check(app.player.decoded_frames > 2, 'Frame decodificati')
                print('VIDEO', app.player.size(), 'buffer', app.player.frame_width, app.player.frame_height, flush=True)
                check(not app.visible, 'Catalogo nascosto in playback')
                stage['video_time'] = app.player.media_player_get_time(app.player.handle)
                capture('video-linux.png')
                app.show_menu()
                advance()
            elif current == 3 and elapsed > 1:
                check(app.visible and app.web.get_visible(), 'Menu sul video')
                check(app.player.media_player_get_time(app.player.handle) > stage['video_time'], 'Video continua sotto OSD')
                capture('menu-video-linux.png')
                app.hide_menu()
                GLib.timeout_add(150, lambda: (app.toggle_info(), False)[1])
                advance()
            elif current == 4 and app.info_visible and elapsed > 1:
                check(app.info_visible, 'Info visibili')
                capture('info-linux.png')
                app.js("document.getElementById('volume').value=0;document.getElementById('volume').dispatchEvent(new Event('input'))", app.info)
                advance()
            elif current == 5 and app.volume == 0:
                check(app.volume == 0, 'Telecomando collegato al player')
                app.action(dict(action='escape'))
                check(not app.info_visible, 'Esc chiude info')
                app.toggle_fullscreen()
                advance()
            elif current == 6 and app.fullscreen:
                app.toggle_borderless()
                advance()
            elif current == 7 and app.floating and not app.fullscreen:
                check(not app.window.get_decorated(), 'Finestra senza bordi')
                app.toggle_borderless()
                advance()
            elif current == 8 and app.fullscreen and not app.floating:
                app.toggle_fullscreen()
                advance()
            elif current == 9 and not app.fullscreen:
                app.action(dict(action='escape'))
                check(app.visible and app.current, 'Esc apre OSD')
                app.action(dict(action='escape'))
                check(app.current is None and app.visible, 'Secondo Esc stop')
                app.toggle_fullscreen()
                advance()
            elif current == 10 and app.fullscreen:
                app.toggle_fullscreen()
                advance()
            elif current == 11 and not app.fullscreen and elapsed > .5:
                check(all(v > 0 for v in app.window.get_size()), 'Geometria dopo stop/fullscreen')
                print('PASS Linux native: M3U, XMLTV, original UI, bridge, favorites, persistence, LibVLC video/time, OSD, info/remote, fullscreen, floating/return, Esc/stop and fullscreen regression', flush=True)
                app.close()
                return False
        except Exception as error:
            app.fail(str(error))
            return False
        return True

    GLib.timeout_add(200, pulse)
