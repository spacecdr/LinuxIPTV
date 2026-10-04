#!/usr/bin/env python3
"""Verify real PulseAudio/PipeWire samples using a temporary virtual sink.

No microphone/system-output recording and no audible test tone. Requires pactl,
ffmpeg and a local fixture containing audio. Does not open the user's playlists.
"""
import array
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import wave

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'Linux'))
from player import Player


def run(fixture):
    sink = f'linuxiptv_test_{os.getpid()}'
    module = subprocess.check_output(['pactl', 'load-module', 'module-null-sink', f'sink_name={sink}',
                                      'sink_properties=device.description=LinuxIPTV-Audio-Test'], text=True).strip()
    os.environ['PULSE_SINK'] = sink
    player = None
    try:
        player = Player(lambda: None)
        channel = dict(url=fixture.resolve().as_uri(), headers={})
        player.play(channel, 1, 35, False).result(timeout=10)

        def until(predicate, label):
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if predicate():
                    return
                time.sleep(.1)
            raise AssertionError(label)

        until(lambda: player.media_player_get_state(player.handle) == 3 and player.audio_get_track(player.handle) >= 0, 'Audio track did not start')
        # Reproduce the server overwriting setters made before playback.
        player.submit(player.audio_set_volume, player.handle, 0).result()
        player.submit(player.audio_set_mute, player.handle, 1).result()
        def synchronized():
            player.sync_audio(35, False)
            return not player.audio_pending
        until(synchronized, 'Audio bootstrap did not settle')
        assert player.audio_get_volume(player.handle) == 35
        assert player.audio_get_mute(player.handle) == 0
        sink_id = next(s['index'] for s in json.loads(subprocess.check_output(['pactl', '-f', 'json', 'list', 'sinks'])) if s['name'] == sink)
        inputs = json.loads(subprocess.check_output(['pactl', '-f', 'json', 'list', 'sink-inputs']))
        streams = [s for s in inputs if s.get('properties', {}).get('application.process.id') == str(os.getpid())]
        assert streams and all(s['sink'] == sink_id for s in streams), 'Test stream must use only its virtual sink'

        def rms():
            with tempfile.TemporaryDirectory(prefix='linuxiptv-audio-') as directory:
                target = Path(directory) / 'samples.wav'
                subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'pulse', '-i', sink + '.monitor',
                                '-t', '1', '-ar', '8000', '-ac', '1', '-c:a', 'pcm_s16le', str(target)], check=True, timeout=10)
                with wave.open(str(target)) as stream:
                    samples = array.array('h', stream.readframes(stream.getnframes()))
                return math.sqrt(sum(n*n for n in samples) / len(samples))

        audible = rms()
        assert audible > 20, f'No PCM signal after unmute: RMS={audible}'
        player.submit(player.audio_set_mute, player.handle, 1).result()
        time.sleep(.3)
        muted = rms()
        assert muted < 1, f'Mute did not silence output: RMS={muted}'
        player.submit(player.audio_set_mute, player.handle, 0).result()
        time.sleep(.3)
        resumed = rms()
        assert resumed > 20, f'Unmute did not restore output: RMS={resumed}'
        player.submit(player.audio_set_volume, player.handle, 0).result()
        time.sleep(.3)
        zero = rms()
        assert zero < 1, f'Volume zero did not silence output: RMS={zero}'
        player.play(channel, 1, 35, False).result(timeout=10)
        until(synchronized, 'Audio not restored on channel change')
        changed = rms()
        assert changed > 20, f'Channel change remained silent: RMS={changed}'
        player.close().result(timeout=10)
        player = Player(lambda: None, silent=True)
        player.play(channel, 1, 0, True).result(timeout=10)
        until(lambda: player.media_player_get_state(player.handle) == 3, 'Silent player did not start')
        time.sleep(.5)
        inputs = json.loads(subprocess.check_output(['pactl', '-f', 'json', 'list', 'sink-inputs']))
        assert not any(s.get('properties', {}).get('application.process.id') == str(os.getpid()) for s in inputs), 'Smoke test must never create a system audio stream'
        print(f'PASS audio PCM: restored={audible:.1f}, muted={muted:.1f}, resumed={resumed:.1f}, zero={zero:.1f}, channel-change={changed:.1f}; smoke isolated from system mixer')
    finally:
        if player:
            future = player.close()
            if future:
                future.result(timeout=10)
        subprocess.run(['pactl', 'unload-module', module], check=True)


if __name__ == '__main__':
    run(Path(sys.argv[1]))
