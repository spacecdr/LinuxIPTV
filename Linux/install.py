#!/usr/bin/env python3
"""Install a private per-user copy, or stage files for a Debian package."""
import argparse
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent


def install(prefix, system=False):
    data = prefix / 'share/linuxiptv'
    data.mkdir(parents=True, exist_ok=True)
    for name in ('Linux', 'Resources'):
        shutil.copytree(ROOT / name, data / name, dirs_exist_ok=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    (data / 'docs/assets').mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'docs/assets/icon.svg', data / 'docs/assets/icon.svg')
    for name in ('LICENSE', 'THIRD_PARTY.md', 'README.md'):
        shutil.copy2(ROOT / name, data / name)
    bindir = prefix / 'bin'
    bindir.mkdir(parents=True, exist_ok=True)
    app_path = Path('/usr/share/linuxiptv') if system else data
    # repr safely quotes Python literals; the launcher contains no shell expansion.
    launcher = bindir / 'linuxiptv'
    launcher.write_text('#!/usr/bin/python3\nimport os, sys\nos.execv("/usr/bin/python3", ["/usr/bin/python3", ' + repr(str(app_path / 'Linux/app.py')) + '] + sys.argv[1:])\n')
    launcher.chmod(0o755)
    applications = prefix / 'share/applications'
    applications.mkdir(parents=True, exist_ok=True)
    executable = '/usr/bin/linuxiptv' if system else str(launcher)
    escaped = executable.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$')
    (applications / 'linuxiptv.desktop').write_text(f'''[Desktop Entry]
Type=Application
Name=LinuxIPTV
Comment=Playlist M3U, guida EPG e player VLC
Exec="{escaped}"
Icon=linuxiptv
Terminal=false
Categories=AudioVideo;Video;Player;
StartupWMClass=linuxiptv
''')
    icons = prefix / 'share/icons/hicolor/scalable/apps'
    icons.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'docs/assets/icon.svg', icons / 'linuxiptv.svg')
    return launcher


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Installa LinuxIPTV per il proprio utente, senza sudo')
    parser.add_argument('--prefix', type=Path, default=Path.home() / '.local')
    parser.add_argument('--system-stage', action='store_true')
    args = parser.parse_args()
    if not args.system_stage:
        try:
            import gi
            gi.require_version('Gtk', '3.0')
            gi.require_version('WebKit2', '4.1')
            gi.require_foreign('cairo')
            import ctypes.util
            if not ctypes.util.find_library('vlc'):
                raise ImportError('LibVLC')
        except (ImportError, ValueError):
            sys.exit('Dipendenze mancanti. Su Ubuntu/Debian: sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-webkit2-4.1 libvlc5 vlc-plugin-base vlc-plugin-video-output xwayland')
    print('Installato:', install(args.prefix.resolve(), args.system_stage))
