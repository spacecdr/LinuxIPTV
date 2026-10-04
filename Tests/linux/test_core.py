import copy
import datetime as dt
import gzip
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'Linux'))
from core import Library, Matcher, Store, epg_payload, fetch, guide_urls, parse_m3u, parse_xmltv, xmltv_date
from epg import EPGService


class CatalogTests(unittest.TestCase):
    def test_metadata_relative_headers_and_stable_ids(self):
        data = b'''\xef\xbb\xbf#EXTM3U x-tvg-url="guide.xml.gz,https://example.org/guide.xml"
#EXTINF:-1 tvg-id="rai.1" tvg-name="Rai Uno" group-title="News, IT" tvg-logo="logo.png",Rai 1
#EXTVLCOPT:http-user-agent=Example
stream.ts|Referer=https%3A%2F%2Fexample.org%2F
#EXTINF:-1 group-title="News, IT",Rai 1
stream.ts
#EXTINF:-1,Unsafe
javascript:alert(1)
'''
        channels = parse_m3u(data, 'https://example.org/list.m3u')
        self.assertEqual(len(channels), 1)
        channel = channels[0]
        self.assertEqual(channel['logo'], 'https://example.org/logo.png')
        self.assertEqual(channel['headers'], {'http-user-agent': 'Example', 'http-referrer': 'https://example.org/'})
        expected = hashlib.sha256(b'https://example.org/stream.ts\nNews, IT\nRai 1').hexdigest()[:24]
        self.assertEqual(channel['id'], expected)
        self.assertEqual(channel['tvgID'], 'rai.1')
        playlist = dict(catalog=dict(raw=data.decode('utf-8-sig'), base='https://example.org/list.m3u'))
        self.assertEqual(guide_urls(playlist), ['https://example.org/guide.xml.gz', 'https://example.org/guide.xml'])

    def test_latin1_and_large_catalog(self):
        self.assertEqual(parse_m3u('#EXTM3U\n#EXTINF:-1,Caffè\nhttps://example.org/a'.encode('latin1'))[0]['name'], 'Caffè')
        self.assertEqual(len(parse_m3u(('\n'.join(f'#EXTINF:-1,Canale {i}\nhttps://example.org/{i}' for i in range(10000))).encode())), 10000)

    def test_failed_import_and_write_keep_previous_library(self):
        with tempfile.TemporaryDirectory() as directory:
            store = Store(directory)
            library = Library(store)
            item = library.install(b'#EXTM3U\n#EXTINF:-1,Uno\nhttps://example.org/one', '', '')
            identity = item['id']
            library.update(identity, lambda p: p.update(favorites=[p['catalog']['channels'][0]['id']]))
            previous = copy.deepcopy(library.data)
            with self.assertRaises(ValueError):
                library.install(b'<html>not a playlist</html>', '', '', identity)
            self.assertEqual(previous, library.data)
            with patch.object(store, 'save', side_effect=OSError('disk full')):
                with self.assertRaises(OSError):
                    library.install(b'https://example.org/two', '', '', identity)
            self.assertEqual(previous, library.data)
            second = library.install(b'https://example.org/two', '', '', name='Seconda')
            self.assertEqual(second['favorites'], [])
            self.assertEqual(Library(store).data, library.data)
            self.assertEqual(os.stat(Path(directory) / 'library.json').st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(directory).st_mode & 0o777, 0o700)

    def test_download_redirect_limit_and_error(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/redirect':
                    self.send_response(302); self.send_header('Location', '/list'); self.end_headers()
                elif self.path == '/missing':
                    self.send_error(404)
                else:
                    self.send_response(200); self.end_headers(); self.wfile.write(b'https://example.org/channel')
            def log_message(self, *args):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            data, resolved = fetch(base + '/redirect', 100)
            self.assertEqual(resolved, base + '/list')
            self.assertEqual(len(parse_m3u(data)), 1)
            with self.assertRaises(ValueError):
                fetch(base + '/list', 4)
            with self.assertRaises(Exception):
                fetch(base + '/missing', 100)
        finally:
            server.shutdown(); server.server_close(); thread.join()


class EPGTests(unittest.TestCase):
    NOW = 1760000000

    def fixture(self):
        stamp = lambda value: dt.datetime.fromtimestamp(value, dt.timezone.utc).strftime('%Y%m%d%H%M%S +0000')
        return f'''<tv><channel id="rai.1"><display-name>Rai 1</display-name></channel>
<programme channel="rai.1" start="{stamp(self.NOW-600)}"><title lang="en">News</title><title lang="it">Notizie</title><desc>Dettagli</desc></programme>
<programme channel="rai.1" start="{stamp(self.NOW+600)}" stop="{stamp(self.NOW+1800)}"><title>Dopo</title></programme></tv>'''.encode()

    def test_gzip_timezone_schedule_and_diagnostics(self):
        guide = parse_xmltv(gzip.compress(self.fixture()), self.NOW)
        matcher = Matcher(guide)
        channel = dict(id='one', name='Rai 1 HD', tvgID='RAI_1', tvgName='')
        self.assertEqual(matcher.match(channel), ('rai.1', 'normalizedID'))
        schedule = matcher.schedule(channel, self.NOW)
        self.assertEqual(schedule['now']['title'], 'Notizie')
        self.assertEqual(schedule['now']['end'], self.NOW+600)
        self.assertEqual(schedule['next']['title'], 'Dopo')
        self.assertEqual(xmltv_date('20251009090000 +0200'), xmltv_date('20251009070000 +0000'))
        self.assertIsNone(xmltv_date('20251399000000 +0000'))
        playlist = dict(catalog=dict(channels=[channel], raw='', base=''), epgOverride='https://example.org/guide')
        with patch('core.time.time', return_value=self.NOW):
            payload = epg_payload(playlist, guide, 'Guida caricata')
        self.assertEqual(payload['diagnostics']['current'], 1)
        self.assertNotIn('description', payload['programmes']['one']['now'])

    def test_ambiguity_and_timeshift_are_preserved(self):
        guide = dict(programmes={'rai.1': [], 'rai-1': [], 'plus': []}, names={'Rai 1': ['rai.1', 'rai-1'], 'Rai 1 +1': ['plus']})
        matcher = Matcher(guide)
        self.assertEqual(matcher.match(dict(tvgID='RAI_1', name='Rai 1')), (None, 'ambiguous'))
        self.assertEqual(matcher.match(dict(tvgID='rai.1', name='Rai 1')), ('rai.1', 'exactID'))
        self.assertEqual(matcher.match(dict(name='IT | Rai 1 +1 HD')), ('plus', 'name'))
        self.assertEqual(matcher.match(dict(name='Rai 1 +24 HD')), (None, 'missing'))

    def test_reject_entities_invalid_xml_and_gzip(self):
        for data in [b'<html/>', b'<tv>', b'<!DOCTYPE tv [<!ENTITY x "boom">]><tv/>', '<!DOCTYPE tv><tv/>'.encode('utf-16'), b'\x1f\x8bnot-gzip']:
            with self.subTest(data=data), self.assertRaises(Exception):
                parse_xmltv(data, self.NOW)

    def test_stale_background_result_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            callbacks = []
            service = EPGService(Store(directory), lambda work, done: callbacks.append(done), lambda: None)
            playlist = dict(id='test', epgOverride='https://example.org/guide')
            service.refresh(playlist)
            service.cancel('test')
            callbacks[0]((dict(programmes={}, names={}), 'Old guide'), None)
            self.assertNotIn('test', service.guides)


if __name__ == '__main__':
    unittest.main()
