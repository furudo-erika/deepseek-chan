#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
TOOL=${ICON_COMPOSER_TOOL:-'/Applications/Icon Composer.app/Contents/Executables/ictool'}
[[ -x "$TOOL" ]] || { print -u2 'Set ICON_COMPOSER_TOOL to Apple Icon Composer’s ictool executable.'; exit 2; }
"$TOOL" "$ROOT/Assets/CompanionNative.icon" --export-image --output-file "$ROOT/Assets/companion-icon-macos.png" --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
