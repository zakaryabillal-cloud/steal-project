#!/usr/bin/env bash
# Type-checks the whole project with luau-lsp + Roblox definitions.
# Usage: tools/analyze.sh [paths...]   (needs rojo + luau-lsp on PATH, see rokit.toml)
set -euo pipefail
cd "$(dirname "$0")/.."
DEFS="tools/.cache/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	mkdir -p tools/.cache
	curl -sSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions="$DEFS" --sourcemap=sourcemap.json --base-luaurc=.luaurc --formatter=plain "${@:-src}"
