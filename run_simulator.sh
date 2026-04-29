#!/bin/bash
set -e
DEVICE="9409A75D-33D3-46C9-8CB4-3C8FB70A6558"
APP="build/ios/Debug-iphonesimulator/Runner.app"

echo "🔨 Building..."
flutter build ios --simulator --no-codesign

echo "🔏 Signing..."
xattr -cr "$APP"
codesign --force --sign - --timestamp=none --generate-entitlement-der "$APP"

echo "📲 Installing..."
xcrun simctl install "$DEVICE" "$APP"

echo "🚀 Launching..."
BUNDLE_ID=$(defaults read "$PWD/$APP/Info" CFBundleIdentifier)
xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
echo "✅ Kratos is running!"
