#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install -Dm644 -- "$source_dir/omarchyform.desktop" "${XDG_DATA_HOME:-$HOME/.local/share}/applications/omarchyform.desktop"
