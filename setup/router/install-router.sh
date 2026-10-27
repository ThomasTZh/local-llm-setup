#!/usr/bin/env bash
# Render models.ini.template into $AI_HOME/runtime/models.ini.
set -euo pipefail

AI_HOME="${AI_HOME:-$HOME/local-llm-setup}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$AI_HOME/runtime"
sed "s|@AI_HOME@|$AI_HOME|g" "$here/models.ini.template" > "$AI_HOME/runtime/models.ini"

missing=0
while IFS= read -r path; do
  if [ ! -f "$path" ]; then
    echo "missing: $path" >&2
    missing=1
  fi
done < <(grep -oE '(model|mmproj|chat-template-file) = .*' "$AI_HOME/runtime/models.ini" | sed 's/^[a-z-]* = //')

echo "wrote $AI_HOME/runtime/models.ini"
if [ "$missing" -ne 0 ]; then
  echo "some files are missing; run setup/download-models.sh first" >&2
  exit 1
fi
echo "all referenced files exist"
