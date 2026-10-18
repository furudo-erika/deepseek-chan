#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
cd "$ROOT"
mkdir -p .build/checks
swiftc -Onone Sources/TimerEngine.swift Tests/main.swift -o .build/checks/timer
.build/checks/timer
for name in Dialogue Drag Action Personality Proactive Halloween; do
  case "$name" in
    Dialogue) SOURCES=(Sources/DialogueService.swift) ;;
    Drag) SOURCES=(Sources/ScreenDrag.swift) ;;
    Action) SOURCES=(Sources/ActionLibrary.swift) ;;
    Personality) SOURCES=(Sources/ActionLibrary.swift Sources/PetPersonality.swift) ;;
    Proactive|Halloween) SOURCES=(Sources/ActionLibrary.swift Sources/PetPersonality.swift Sources/ProactiveChatter.swift) ;;
  esac
  swiftc -Onone -parse-as-library "${SOURCES[@]}" "Tests/${name}Checks.swift" -o ".build/checks/$name"
  ".build/checks/$name"
done
