#!/bin/sh
# Builds a release binary and wraps it in build/EvoWizard.app (menu-bar only, ad-hoc signed).
set -eu
cd "$(dirname "$0")/.."

swift build -c release
APP=build/EvoWizard.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/EvoWizard" "$APP/Contents/MacOS/EvoWizard"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>EvoWizard</string>
    <key>CFBundleDisplayName</key><string>Evo Wizard</string>
    <key>CFBundleIdentifier</key><string>dev.evowizard.app</string>
    <key>CFBundleExecutable</key><string>EvoWizard</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
