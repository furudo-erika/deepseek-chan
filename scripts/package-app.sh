#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
CONFIG=${1:-debug}
case "$CONFIG" in
  debug) FLAGS=(-Onone -g -D DEBUG); APP="$ROOT/dist/DeepSeek-chan.app" ;;
  release) FLAGS=(-O -whole-module-optimization); APP="$ROOT/dist/release/DeepSeek-chan.app" ;;
  *) print -u2 "Usage: $0 [debug|release]"; exit 2 ;;
esac
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build"
cd "$ROOT"
mkdir -p "$ROOT/.build/AppIcon.iconset"
swift "$ROOT/scripts/PackageIcon.swift" "$ROOT/Assets/companion-icon-macos.png" "$ROOT/.build/AppIcon.iconset"
iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o "$ROOT/.build/AppIcon.icns"
swiftc "${FLAGS[@]}" -module-name EyeWhale -framework AppKit -framework SwiftUI \
  "$ROOT/Sources/TaskBridge.swift" "$ROOT/Sources/TaskBuddiesView.swift" "$ROOT/Sources/ActionLibrary.swift" "$ROOT/Sources/ActionLibraryView.swift" \
  "$ROOT/Sources/PetPersonality.swift" "$ROOT/Sources/ProactiveChatter.swift" \
  "$ROOT/Sources/ScreenDrag.swift" "$ROOT/Sources/DialogueService.swift" "$ROOT/Sources/Views.swift" "$ROOT/Sources/TimerEngine.swift" "$ROOT/Sources/CompanionView.swift" "$ROOT/Sources/main.swift" \
  -o "$APP/Contents/MacOS/EyeWhale"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EyeWhale</string>
<key>CFBundleIdentifier</key><string>local.bill.eyewhale</string>
<key>CFBundleName</key><string>DeepSeek-chan</string>
<key>CFBundleDisplayName</key><string>DeepSeek-chan</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>CFBundleShortVersionString</key><string>1.9.0</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>CompanionMacIcon</string>
<key>NSHumanReadableCopyright</key><string>Personal local app. Not affiliated with DeepSeek.</string>
</dict></plist>
PLIST
if [[ -f "$ROOT/.build/AppIcon.icns" ]]; then
  cp "$ROOT/.build/AppIcon.icns" "$APP/Contents/Resources/CompanionMacIcon.icns"
fi
cp "$ROOT/Assets/deepseek-chan-soft-atlas.png" "$APP/Contents/Resources/deepseek-chan-soft-atlas.png"
cp "$ROOT/Assets/deepseek-chan-dance-atlas.png" "$APP/Contents/Resources/"
cp "$ROOT/Assets/deepseek-chan-daily-atlas.png" "$APP/Contents/Resources/"
cp "$ROOT/Assets/actions/"*.png "$APP/Contents/Resources/"
cp "$ROOT/Assets/action-library.json" "$ROOT/Assets/atlas-layout.json" "$APP/Contents/Resources/"
cp "$ROOT/Assets/atlas-cutouts.json" "$APP/Contents/Resources/"
cp "$ROOT/Assets/atlas-regions.json" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/integrations"
cp "$ROOT/integrations/"*.py "$ROOT/integrations/"*.ts "$ROOT/integrations/"*.mjs "$APP/Contents/Resources/integrations/"
codesign --force --sign - "$APP"
printf '%s app: %s\n' "$CONFIG" "$APP"
