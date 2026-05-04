#!/bin/bash
set -e
DEVICE="9409A75D-33D3-46C9-8CB4-3C8FB70A6558"
APP="build/ios/Debug-iphonesimulator/Runner.app"

echo "🔨 Building..."
flutter build ios --simulator --no-codesign

echo "🔏 Signing..."
# Thin all embedded FAT frameworks to arm64 only (prevents codesign resource-fork
# errors on macOS Sequoia with Flutter 3.41.x universal simulator binaries)
for FW in "$APP/Frameworks"/*.framework; do
  [ -d "$FW" ] || continue
  BIN="$FW/$(basename "$FW" .framework)"
  [ -f "$BIN" ] || continue
  ARCHS=$(lipo -archs "$BIN" 2>/dev/null || echo "")
  if echo "$ARCHS" | grep -q x86_64; then
    lipo "$BIN" -thin arm64 -output "$BIN.arm64" 2>/dev/null && mv "$BIN.arm64" "$BIN" || true
  fi
  xattr -cr "$FW"
  codesign --force --sign - --timestamp=none "$FW"
done
xattr -cr "$APP"
codesign --force --sign - --timestamp=none "$APP"

echo "📲 Installing..."
xcrun simctl install "$DEVICE" "$APP"

echo "🚀 Launching..."
BUNDLE_ID=$(defaults read "$PWD/$APP/Info" CFBundleIdentifier)
xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
echo "✅ Kratos is running!"
