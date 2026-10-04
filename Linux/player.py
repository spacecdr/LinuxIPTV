"""Small typed LibVLC 3 binding; no Python packages downloaded at runtime."""
import ctypes as C
import ctypes.util
import threading
import cairo
from concurrent.futures import ThreadPoolExecutor


class VideoTrack(C.Structure):
    _fields_ = [('height', C.c_uint), ('width', C.c_uint), ('sar_num', C.c_uint),
                ('sar_den', C.c_uint), ('fps_num', C.c_uint), ('fps_den', C.c_uint),
                ('orientation', C.c_int), ('projection', C.c_int), ('pose', C.c_float * 4)]


class Track(C.Structure):
    _fields_ = [('codec', C.c_uint32), ('fourcc', C.c_uint32), ('id', C.c_int),
                ('type', C.c_int), ('profile', C.c_int), ('level', C.c_int),
                ('video', C.POINTER(VideoTrack)), ('bitrate', C.c_uint),
                ('language', C.c_char_p), ('description', C.c_char_p)]


class Player:
    def __init__(self, redraw, muted=False):
        self.lib = C.CDLL(ctypes.util.find_library('vlc') or 'libvlc.so.5')
        pointer, integer, string = C.c_void_p, C.c_int, C.c_char_p
        signatures = {
            'new': (pointer, [integer, C.POINTER(string)]), 'release': (None, [pointer]),
            'media_player_get_media': (pointer, [pointer]),
            'media_tracks_get': (C.c_uint, [pointer, C.POINTER(C.POINTER(C.POINTER(Track)))]),
            'media_tracks_release': (None, [C.POINTER(C.POINTER(Track)), C.c_uint]),
            'media_player_new': (pointer, [pointer]), 'media_player_release': (None, [pointer]),
            'media_player_set_xwindow': (None, [pointer, C.c_uint32]),
            'media_new_location': (pointer, [pointer, string]), 'media_add_option': (None, [pointer, string]),
            'media_release': (None, [pointer]), 'media_player_set_media': (None, [pointer, pointer]),
            'media_player_play': (integer, [pointer]), 'media_player_stop': (None, [pointer]),
            'media_player_pause': (None, [pointer]), 'media_player_get_state': (integer, [pointer]),
            'media_player_get_time': (C.c_int64, [pointer]), 'media_player_has_vout': (C.c_uint, [pointer]),
            'audio_set_volume': (integer, [pointer, integer]), 'audio_set_mute': (None, [pointer, integer]),
            'video_set_key_input': (None, [pointer, C.c_uint]), 'video_set_mouse_input': (None, [pointer, C.c_uint]),
            'video_get_size': (integer, [pointer, C.c_uint, C.POINTER(C.c_uint), C.POINTER(C.c_uint)]),
            'video_take_snapshot': (integer, [pointer, C.c_uint, string, C.c_uint, C.c_uint]),
        }
        for name, (restype, argtypes) in signatures.items():
            function = getattr(self.lib, 'libvlc_' + name)
            function.restype, function.argtypes = restype, argtypes
            setattr(self, name, function)
        args = [b'--ignore-config', b'--no-video-title-show', b'--no-osd', b'--no-media-library', b'--quiet', b'--no-snapshot-preview', b'--vout=vmem']
        self.instance = self.new(len(args), (string * len(args))(*args))
        if not self.instance:
            raise RuntimeError('Motore VLC non disponibile.')
        self.handle = self.media_player_new(self.instance)
        if not self.handle:
            self.release(self.instance)
            raise RuntimeError('Impossibile creare il player VLC.')
        self.frame_lock = threading.Lock()
        self.frame = None
        self.aspect = 0
        self.decoded_frames = 0
        self.redraw = redraw
        self.setup_video()
        self.video_set_key_input(self.handle, 0)
        self.video_set_mouse_input(self.handle, 0)
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix='libvlc')
        self.closed = False

    def setup_video(self):
        # Decode with LibVLC into a Cairo-compatible buffer. GTK then composites
        # the video and transparent WebKit overlays in the same window.
        lock_type = C.CFUNCTYPE(C.c_void_p, C.c_void_p, C.POINTER(C.c_void_p))
        display_type = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p)
        setup_type = C.CFUNCTYPE(C.c_uint, C.POINTER(C.c_void_p), C.c_void_p,
                                C.POINTER(C.c_uint), C.POINTER(C.c_uint),
                                C.POINTER(C.c_uint), C.POINTER(C.c_uint))
        def setup(opaque, chroma, width, height, pitches, lines):
            self.frame_width, self.frame_height = width[0], height[0]
            self.pitch = (width[0] * 4 + 31) & ~31
            self.buffer = C.create_string_buffer(self.pitch * height[0] + 32)
            self.buffer_address = (C.addressof(self.buffer) + 31) & ~31
            C.memmove(chroma, b'RV32', 4)
            pitches[0], lines[0] = self.pitch, height[0]
            return 1
        def lock(opaque, planes):
            planes[0] = self.buffer_address
            return None
        def display(opaque, picture):
            with self.frame_lock:
                data = bytearray(C.string_at(self.buffer_address, self.pitch * self.frame_height))
                self.frame = cairo.ImageSurface.create_for_data(data, cairo.FORMAT_RGB24,
                                                              self.frame_width, self.frame_height, self.pitch)
                self.decoded_frames += 1
            self.redraw()
        self.callbacks = (lock_type(lock), display_type(display), setup_type(setup))
        callbacks = self.lib.libvlc_video_set_callbacks
        callbacks.argtypes = [C.c_void_p, lock_type, C.c_void_p, display_type, C.c_void_p]
        callbacks.restype = None
        callbacks(self.handle, self.callbacks[0], None, self.callbacks[1], None)
        formats = self.lib.libvlc_video_set_format_callbacks
        formats.argtypes = [C.c_void_p, setup_type, C.c_void_p]
        formats.restype = None
        formats(self.handle, self.callbacks[2], None)

    def draw(self, context, width, height):
        with self.frame_lock:
            if self.frame is None:
                return
            fw, fh = self.frame.get_width(), self.frame.get_height()
            aspect = self.aspect or fw / fh
            dw = min(width, height * aspect)
            dh = dw / aspect
            context.save()
            context.translate((width - dw) / 2, (height - dh) / 2)
            context.scale(dw / fw, dh / fh)
            context.set_source_surface(self.frame, 0, 0)
            context.paint()
            context.restore()

    def submit(self, function, *args):
        if not self.closed:
            return self.executor.submit(function, *args)

    def play(self, channel, buffer, volume, muted):
        def start():
            self.media_player_stop(self.handle)
            with self.frame_lock:
                self.frame = None
                self.aspect = 0
            media = self.media_new_location(self.instance, channel['url'].encode())
            if not media:
                raise RuntimeError('Indirizzo del canale non valido.')
            self.media_add_option(media, f':network-caching={buffer * 1000}'.encode())
            for key, value in channel['headers'].items():
                if key in {'http-user-agent', 'http-referrer'} and '\n' not in value and '\r' not in value:
                    self.media_add_option(media, f':{key}={value}'.encode())
            self.media_player_set_media(self.handle, media)
            self.media_release(media)
            self.audio_set_volume(self.handle, volume)
            self.audio_set_mute(self.handle, int(muted))
            if self.media_player_play(self.handle) < 0:
                raise RuntimeError('Impossibile avviare il canale.')
        return self.submit(start)

    def display_ratio(self):
        width, height = self.size()
        if not width or not height:
            return 0
        ratio = width / height
        media = self.media_player_get_media(self.handle)
        if media:
            tracks = C.POINTER(C.POINTER(Track))()
            count = self.media_tracks_get(media, C.byref(tracks))
            try:
                for index in range(count):
                    track = tracks[index].contents
                    if track.type == 1 and track.video:
                        video = track.video.contents
                        if video.sar_num and video.sar_den:
                            ratio *= video.sar_num / video.sar_den
                        if video.orientation >= 4:
                            ratio = 1 / ratio
                        break
            finally:
                self.media_tracks_release(tracks, count)
                self.media_release(media)
        self.aspect = ratio
        return ratio

    def size(self):
        width, height = C.c_uint(), C.c_uint()
        self.video_get_size(self.handle, 0, C.byref(width), C.byref(height))
        return width.value, height.value

    def close(self):
        if self.closed:
            return
        self.closed = True
        def release():
            self.media_player_stop(self.handle)
            self.media_player_release(self.handle)
            self.release(self.instance)
        future = self.executor.submit(release)
        self.executor.shutdown(wait=False)
        return future
