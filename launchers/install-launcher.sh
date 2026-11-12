#!/usr/bin/env bash
# Install a menu entry that starts the local llama.cpp router.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
python="$(command -v python3 || true)"
if [ -z "$python" ]; then
  echo "python3 was not found on PATH" >&2
  exit 1
fi
if [ ! -f "$root/setup/router/start-router.sh" ]; then
  echo "setup/router/start-router.sh is missing under $root" >&2
  exit 1
fi

ai_home="${AI_HOME:-$root}"
ai_host="${AI_HOST:-127.0.0.1}"
ai_port="${AI_PORT:-8080}"

case "$ai_port" in
  *[!0-9]*|'') echo "AI_PORT must be a port number, got '$ai_port'" >&2; exit 1 ;;
esac
if [ "$ai_port" -lt 1 ] || [ "$ai_port" -gt 65535 ]; then
  echo "AI_PORT must be between 1 and 65535, got '$ai_port'" >&2
  exit 1
fi

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
apps="$data_home/applications"
wrapper_dir="$data_home/local-llm-router"
wrapper="$wrapper_dir/launch.sh"
desktop="$apps/local-llm-router.desktop"

case "$root$wrapper" in
  *'"'*|*'\'*)
    echo "refusing a path containing a double quote or backslash" >&2
    exit 1
    ;;
esac

mkdir -p "$apps" "$wrapper_dir"

{
  printf '%s\n' '#!/bin/bash'
  printf 'export AI_HOME=%q\n' "$ai_home"
  printf 'export AI_HOST=%q\n' "$ai_host"
  printf 'export AI_PORT=%q\n' "$ai_port"
  printf 'exec %q %q "$@"\n' "$python" "$root/launchers/run-local-llm.py"
} > "$wrapper"
chmod 755 "$wrapper"

{
  printf '%s\n' '[Desktop Entry]'
  printf '%s\n' 'Type=Application'
  printf '%s\n' 'Version=1.0'
  printf '%s\n' 'Name=Local LLM router'
  printf '%s\n' 'Comment=Start the local llama.cpp router; Ctrl+C stops it'
  printf 'Exec="%s"\n' "$wrapper"
  printf 'Path=%s\n' "$root"
  printf '%s\n' 'Terminal=true'
  printf '%s\n' 'Icon=utilities-terminal'
  printf '%s\n' 'Categories=Development;'
  printf '%s\n' 'StartupNotify=false'
} > "$desktop"

chmod 755 "$desktop"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$apps" >/dev/null 2>&1 || true
fi

printf 'Installed %s\n' "$desktop"
printf 'Wrapper: %s\n' "$wrapper"
printf 'Router: %s:%s (AI_HOME=%s)\n' "$ai_host" "$ai_port" "$ai_home"
printf 'Remove it with: bash "%s/uninstall-launcher.sh"\n' "$here"
