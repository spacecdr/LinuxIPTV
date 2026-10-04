#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
VERSION=1.2.0+linux1
STAGE=$(mktemp -d "$ROOT/build-linux.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
mkdir -p dist "$STAGE/usr" "$STAGE/DEBIAN"
python3 Linux/install.py --system-stage --prefix "$STAGE/usr"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: linuxiptv
Version: $VERSION
Section: video
Priority: optional
Architecture: all
Maintainer: spacecdr <spacecdr@users.noreply.github.com>
Depends: python3 (>= 3.10), python3-gi, python3-gi-cairo, gir1.2-gtk-3.0, gir1.2-webkit2-4.1, libvlc5, vlc-plugin-base, vlc-plugin-video-output, xwayland
Recommends: vlc
Homepage: https://github.com/spacecdr/LinuxIPTV
Description: IPTV player for Linux, port of MacIPTV
 Original catalog interface, M3U playlists, favorites, XMLTV programme guide,
 embedded LibVLC playback and floating video window. No channels included.
EOF
mkdir -p "$STAGE/usr/share/doc/linuxiptv"
cp LICENSE "$STAGE/usr/share/doc/linuxiptv/copyright"
dpkg-deb --root-owner-group --build "$STAGE" "dist/linuxiptv_${VERSION}_all.deb"
# Source distribution includes install script, shared UI, tests and original sources.
git ls-files -z --cached --others --exclude-standard | tar --null -T - --transform='s,^,LinuxIPTV/,' -cJf "dist/LinuxIPTV-${VERSION}-source.tar.xz"
cd dist
sha256sum "linuxiptv_${VERSION}_all.deb" "LinuxIPTV-${VERSION}-source.tar.xz" > SHA256SUMS
