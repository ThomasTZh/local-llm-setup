#!/usr/bin/env bash
# Remove the menu entry and wrapper installed by install-launcher.sh.
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
apps="$data_home/applications"
wrapper_dir="$data_home/local-llm-router"
desktop="$apps/local-llm-router.desktop"

if [ -e "$desktop" ]; then
  rm -f -- "$desktop"
  printf 'Removed %s\n' "$desktop"
else
  printf 'No launcher entry at %s\n' "$desktop"
fi

if [ -e "$wrapper_dir/launch.sh" ]; then
  rm -f -- "$wrapper_dir/launch.sh"
  rmdir "$wrapper_dir" 2>/dev/null || true
  printf 'Removed %s\n' "$wrapper_dir/launch.sh"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$apps" >/dev/null 2>&1 || true
fi
