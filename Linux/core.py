"""Portable catalog, private storage and XMLTV support (GPL-3.0-or-later)."""
from __future__ import annotations

import copy
import datetime as dt
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import tempfile
import time
import urllib.parse as url
import urllib.request
import uuid
import xml.etree.ElementTree as ET

M3U_LIMIT = 20 * 1024 * 1024
EPG_LIMIT = 128 * 1024 * 1024
SCHEMES = {'http', 'https', 'rtsp', 'rtmp', 'udp', 'rtp', 'file'}
BROWSE = dict(group='@all', search='', groupSearch='', page=0, selected='', mode='grid')


def decode(data):
    try:
        return data.decode('utf-8-sig')
    except UnicodeDecodeError:
        return data.decode('latin-1')


def resolve(value, base='', schemes=SCHEMES):
    address = url.urljoin(base, value.strip()) if value.strip() else ''
    return address if url.urlsplit(address).scheme.lower() in schemes else ''


def valid_http(value):
    try:
        parsed = url.urlsplit(value)
        return parsed.scheme in {'http', 'https'} and bool(parsed.hostname)
    except ValueError:
        return False


def parse_m3u(data, base=''):
    if len(data) > M3U_LIMIT:
        raise ValueError('La lista supera 20 MB.')
    result, seen = [], set()
    name = group = logo = tvg_id = tvg_name = ''
    headers = {}
    for line in decode(data).splitlines():
        line = line.strip().replace('\ufeff', '')
        if line.startswith('#EXTINF:'):
            quoted, split = False, len(line)
            for i, char in enumerate(line):
                if char == '"':
                    quoted = not quoted
                if char == ',' and not quoted:
                    split = i
                    break
            attrs = {k.lower(): v for k, v in re.findall(r'([\w-]+)\s*=\s*"([^"]*)"', line[:split])}
            name = line[split + 1:].strip() or attrs.get('tvg-name', '')
            group, logo = attrs.get('group-title', ''), resolve(attrs.get('tvg-logo', ''), base)
            tvg_id, tvg_name = attrs.get('tvg-id', ''), attrs.get('tvg-name', '')
            headers = {}
        elif line.startswith('#EXTGRP:'):
            group = line[8:]
        elif line.startswith('#EXTVLCOPT:'):
            key, _, value = line[11:].partition('=')
            if key in {'http-user-agent', 'http-referrer'}:
                headers[key] = value
        elif line and not line.startswith('#'):
            address, _, options = line.partition('|')
            address = resolve(address, base)
            for pair in options.split('&'):
                key, _, value = pair.partition('=')
                mapped = {'user-agent': 'http-user-agent', 'referer': 'http-referrer', 'referrer': 'http-referrer'}.get(key.lower())
                if mapped:
                    headers[mapped] = url.unquote(value)
            if address:
                title = name or url.unquote(url.urlsplit(address).path.rsplit('/', 1)[-1]) or 'Canale'
                category = group or 'Senza gruppo'
                identity = hashlib.sha256(f'{address}\n{category}\n{title}'.encode()).hexdigest()[:24]
                if identity not in seen:
                    seen.add(identity)
                    result.append(dict(id=identity, name=title, group=category, url=address, logo=logo,
                                       headers=headers, tvgID=tvg_id, tvgName=tvg_name))
            name = group = logo = tvg_id = tvg_name = ''
            headers = {}
    if not result:
        raise ValueError('Nessun canale valido nella lista. La lista precedente è stata conservata.')
    return result


def guide_urls(playlist):
    if playlist.get('epgOverride', '').strip():
        return [playlist['epgOverride'].strip()]
    catalog = playlist['catalog']
    header = next((s for s in catalog['raw'].splitlines() if s.lstrip('\ufeff').startswith('#EXTM3U')), '')
    urls = []
    for match in re.findall(r'''(?:x-tvg-url|url-tvg|tvg-url)\s*=\s*["']([^"']+)["']''', header, re.I):
        for value in match.split(','):
            address = resolve(value, catalog['base'], {'http', 'https', 'file'})
            if address and address not in urls:
                urls.append(address)
    return urls[:4]


def fetch(address, limit):
    """Bound downloads during reading, including servers without Content-Length."""
    if url.urlsplit(address).scheme not in {'http', 'https', 'file'}:
        raise ValueError('Protocollo della sorgente non supportato.')
    request = urllib.request.Request(address, headers={'User-Agent': 'LinuxIPTV/1.2.0'})
    with urllib.request.urlopen(request, timeout=45) as response:
        data = response.read(limit + 1)
        if len(data) > limit:
            raise ValueError('La sorgente supera il limite consentito.')
        return data, response.geturl()


class Store:
    def __init__(self, directory=None):
        self.directory = Path(directory or Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'linuxiptv-data')
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.directory.chmod(0o700)

    def write(self, name, data):
        fd, tmp = tempfile.mkstemp(prefix='.write-', dir=self.directory)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(tmp, self.directory / name)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    def save(self, name, value):
        self.write(name, json.dumps(value, ensure_ascii=False).encode())

    def load(self, name, default=None):
        path = self.directory / name
        if not path.exists():
            return copy.deepcopy(default)
        return json.loads(path.read_text())


class Library:
    def __init__(self, store):
        self.store = store
        self.data = store.load('library.json', dict(playlists=[], selectedID=None))
        if not isinstance(self.data, dict) or not isinstance(self.data.get('playlists'), list):
            raise ValueError('Archivio delle playlist non valido.')

    @property
    def selected(self):
        return next((p for p in self.data['playlists'] if p['id'] == self.data['selectedID']), None)

    def commit(self, data):
        self.store.save('library.json', data)
        self.data = data

    def update(self, identity, change):
        data = copy.deepcopy(self.data)
        item = next(p for p in data['playlists'] if p['id'] == identity)
        change(item)
        self.commit(data)

    def install(self, raw, source, base, target='', name='Lista', guide=''):
        channels = parse_m3u(raw, base)
        data = copy.deepcopy(self.data)
        item = next((p for p in data['playlists'] if p['id'] == target), None)
        if item is None:
            item = dict(id=str(uuid.uuid4()), favorites=[], browse=copy.deepcopy(BROWSE))
            data['playlists'].append(item)
        item.update(name=name or 'Lista', catalog=dict(raw=decode(raw), source=source, base=base, channels=channels),
                    epgOverride=guide, updated=time.time())
        data['selectedID'] = item['id']
        self.commit(data)
        return item


def xmltv_date(raw):
    if not raw:
        return None
    parts = raw.split()
    if not re.fullmatch(r'\d{12}|\d{14}', parts[0]):
        return None
    try:
        pattern = '%Y%m%d%H%M%S %z' if len(parts[0]) == 14 else '%Y%m%d%H%M %z'
        return dt.datetime.strptime(parts[0] + ' ' + (parts[1] if len(parts) > 1 else '+0000'), pattern).timestamp()
    except ValueError:
        return None


def parse_xmltv(data, now=None):
    now = time.time() if now is None else now
    if data.startswith(b'\x1f\x8b'):
        with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
            data = stream.read(EPG_LIMIT + 1)
    if len(data) > EPG_LIMIT:
        raise ValueError('Guida EPG oltre 128 MB.')
    # XMLTV needs no DTD. Reject declarations also in UTF-16/32 before parsing.
    if re.search(br'<!\s*(?:DOCTYPE|ENTITY)', data.replace(b'\x00', b''), re.I):
        raise ValueError('Dichiarazioni DTD/entità non consentite.')
    guide = dict(programmes={}, names={}, fetched=time.time())
    depth, count, root = 0, 0, None
    for event, element in ET.iterparse(io.BytesIO(data), events=('start', 'end')):
        if event == 'start':
            depth += 1
            if depth == 1:
                root = element
                if element.tag != 'tv':
                    raise ValueError('Guida XMLTV non valida.')
            continue
        if depth == 2 and element.tag == 'channel':
            identity = element.get('id', '')
            for field in element.findall('display-name'):
                if identity and field.text:
                    guide['names'].setdefault(field.text.strip().lower(), []).append(identity)
        elif depth == 2 and element.tag == 'programme':
            start, end = xmltv_date(element.get('start')), xmltv_date(element.get('stop'))
            identity = element.get('channel', '')
            def field_value(tag):
                values = element.findall(tag)
                preferred = next((v for v in reversed(values) if v.get('lang') == 'it'), values[0] if values else None)
                return ''.join(preferred.itertext()).strip()[:16000] if preferred is not None else ''
            title = field_value('title')
            if identity and title and start is not None and now - 86400 < start < now + 3 * 86400 and (end is None or end > now - 3600):
                count += 1
                if count > 300000:
                    raise ValueError('Troppi programmi nella guida.')
                guide['programmes'].setdefault(identity, []).append(dict(title=title, description=field_value('desc'), start=start, end=end))
        if depth == 2:
            element.clear()
            root.remove(element)
        depth -= 1
    for identity, programmes in guide['programmes'].items():
        unique = {p['start']: p for p in reversed(programmes)}
        programmes = [unique[key] for key in sorted(unique)]
        for first, second in zip(programmes, programmes[1:]):
            if first['end'] is None:
                first['end'] = second['start']
        guide['programmes'][identity] = programmes
    return guide


class Matcher:
    @staticmethod
    def id_key(value):
        return re.sub(r'[\s.\-_]', '', value.lower())

    @classmethod
    def name_key(cls, value):
        value = re.sub(r'^(?:it|it-it|italia|italy)\s*[-|:]\s*', '', value.strip().lower())
        previous = None
        while previous != value:
            previous = value
            value = re.sub(r'\s+(?:sd|hd|fhd|full\s*hd|uhd|4k|h[.]?26[45]|hevc)\s*$', '', value)
        return cls.id_key(value)

    def __init__(self, guide):
        self.guide = guide
        self.known = set(guide['programmes']) | {identity for values in guide['names'].values() for identity in values}
        self.ids, self.names = {}, {}
        for identity in self.known:
            self.ids.setdefault(self.id_key(identity), set()).add(identity)
        for name, values in guide['names'].items():
            if self.name_key(name):
                self.names.setdefault(self.name_key(name), set()).update(values)

    def match(self, channel):
        identity = channel.get('tvgID') or ''
        if identity and identity in self.known:
            return identity, 'exactID'
        candidates = self.ids.get(self.id_key(identity), set()) if identity else set()
        if candidates:
            return (next(iter(candidates)), 'normalizedID') if len(candidates) == 1 else (None, 'ambiguous')
        candidates = set()
        for name in [channel.get('tvgName') or '', channel['name']]:
            candidates.update(self.names.get(self.name_key(name), set()))
        return (next(iter(candidates)), 'name') if len(candidates) == 1 else (None, 'ambiguous' if candidates else 'missing')

    def schedule(self, channel, now=None):
        now = time.time() if now is None else now
        identity, _ = self.match(channel)
        result = {}
        for programme in self.guide['programmes'].get(identity, []):
            if programme['start'] <= now < (programme.get('end') or programme['start'] + 21600):
                result['now'] = programme
            elif programme['start'] > now:
                result['next'] = programme
                break
        return result


def epg_payload(playlist, guide, status, busy=False):
    channels = playlist['catalog']['channels']
    diagnostics = dict(total=len(channels), withID=sum(bool(c.get('tvgID')) for c in channels),
                       sourceCount=len(guide_urls(playlist)), source='XMLTV configurato' if playlist.get('epgOverride') else 'Dalla playlist',
                       matched=0, current=0, upcoming=0, guideChannels=0, programmes=0)
    rows = {}
    if guide:
        matcher = Matcher(guide)
        missing = []
        for channel in channels:
            identity, kind = matcher.match(channel)
            diagnostics[kind] = diagnostics.get(kind, 0) + 1
            diagnostics['matched'] += identity is not None
            schedule = matcher.schedule(channel)
            diagnostics['current'] += 'now' in schedule
            diagnostics['upcoming'] += 'next' in schedule
            if schedule:
                rows[channel['id']] = {k: {a: b for a, b in p.items() if a != 'description'} for k, p in schedule.items()}
            if identity is None and len(missing) < 3:
                missing.append(channel['name'] + ' [' + (channel.get('tvgID') or 'tvg-id assente') + ']')
        diagnostics.update(fetched=guide['fetched'], guideChannels=len(matcher.known),
                           programmes=sum(map(len, guide['programmes'].values())), unmatchedExamples=missing,
                           guideExamples=sorted(matcher.known)[:5], hint='I programmi sono mostrati per i canali associati e gli orari coperti dalla guida.')
        if not diagnostics['matched']:
            diagnostics['hint'] = 'Guida caricata, ma nessun canale associato: confronta gli ID e i nomi.'
        elif not diagnostics['current']:
            diagnostics['hint'] = 'Canali associati, ma nessun programma in onda adesso. Verifica gli orari della guida.'
    return dict(programmes=rows, diagnostics=diagnostics, status=status, busy=busy)
