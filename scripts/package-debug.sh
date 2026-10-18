#!/bin/zsh
set -euo pipefail
exec zsh "${0:A:h}/package-app.sh" debug
