#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/dist/MacIPTV.app"
VENDOR="$PWD/vendor/VLC"
if [ -n "${IPTV_SDK:-}" ]; then
  SDK="$IPTV_SDK"
elif [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
  SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
else
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi
if [ ! -d "$VENDOR/lib" ]; then
  mkdir -p "$VENDOR"
  if [ ! -d "$PWD/vendor/mount/VLC.app" ]; then
    if [ ! -f vendor/vlc-universal.dmg ]; then
      curl -fL --retry 2 https://download.videolan.org/vlc/3.0.24/macosx/vlc-3.0.24-universal.dmg -o vendor/vlc-universal.dmg
    fi
    hdiutil attach vendor/vlc-universal.dmg -nobrowse -readonly -mountpoint "$PWD/vendor/mount"
  fi
  cp -R vendor/mount/VLC.app/Contents/MacOS/lib "$VENDOR/"
  cp -R vendor/mount/VLC.app/Contents/MacOS/plugins "$VENDOR/"
  cp -R vendor/mount/VLC.app/Contents/MacOS/share "$VENDOR/"
  cp -R vendor/mount/VLC.app/Contents/MacOS/include "$VENDOR/"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" build
if [ ! -d "$APP/Contents/Frameworks/VLC" ]; then
  cp -R "$VENDOR" "$APP/Contents/Frameworks/VLC"
fi
# LibVLC does not use the VLC application UI or the obsolete Growl plugin.
mkdir -p build/excluded-plugins
for PLUGIN in libmacosx_plugin.dylib libosx_notifications_plugin.dylib; do
  if [ -f "$APP/Contents/Frameworks/VLC/plugins/$PLUGIN" ]; then
    mv "$APP/Contents/Frameworks/VLC/plugins/$PLUGIN" "build/excluded-plugins/$PLUGIN"
  fi
done
cp Resources/* "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacIPTV</string>
<key>CFBundleIdentifier</key><string>it.local.iptvmac</string>
<key>CFBundleName</key><string>MacIPTV</string>
<key>CFBundleDisplayName</key><string>MacIPTV</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.5</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
<key>NSLocalNetworkUsageDescription</key><string>Riproduzione dei canali IPTV e caricamento delle liste nella rete locale.</string>
</dict></plist>
PLIST
for ARCH in arm64 x86_64; do
  xcrun clang -target "$ARCH-apple-macosx13.0" -isysroot "$SDK" -I "$VENDOR/include" -c Sources/VideoSupport.c -o "build/VideoSupport-$ARCH.o"
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" \
    -import-objc-header Sources/VLCBridge.h Sources/*.swift "build/VideoSupport-$ARCH.o" -lz \
    -L "$VENDOR/lib" -lvlc -framework Cocoa -framework WebKit -framework CryptoKit \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks/VLC/lib' \
    -o "build/MacIPTV-$ARCH"
done
xcrun lipo -create build/MacIPTV-arm64 build/MacIPTV-x86_64 -output "$APP/Contents/MacOS/MacIPTV"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
xcrun lipo -archs "$APP/Contents/MacOS/MacIPTV"
echo "Build: $APP"
