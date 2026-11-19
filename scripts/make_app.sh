#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/UURemoteClone.app"
BIN="$ROOT/.build/release/UURemoteClone"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/UURemoteClone"
cp "$ROOT/native/official/runtime/macos/libstreamer.dylib" "$APP/Contents/Frameworks/"
cp "$ROOT/native/official/runtime/macos/streamer-config.json" "$APP/Contents/Resources/"

# SwiftPM 二进制依赖需要随包嵌入
FRAMEWORK="$(find "$ROOT/.build" -maxdepth 5 -name "WebRTC.framework" -type d 2>/dev/null | head -1)"
if [ -n "${FRAMEWORK}" ]; then
  cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/UURemoteClone" 2>/dev/null || true
  codesign --force --sign - "$APP/Contents/Frameworks/WebRTC.framework" || true
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>UURemoteClone</string>
  <key>CFBundleDisplayName</key><string>UU远程</string>
  <key>CFBundleIdentifier</key><string>com.example.uuremote.clone</string>
  <key>CFBundleExecutable</key><string>UURemoteClone</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>4.48.1</string>
  <key>CFBundleVersion</key><string>633</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>用于远控时传输麦克风声音</string>
  <key>NSCameraUsageDescription</key><string>用于远控时传输摄像头画面</string>
</dict>
</plist>
PLIST

# Preserve the supplied streamer's own signature; sign the enclosing app only.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "built: $APP"
du -sh "$APP"
