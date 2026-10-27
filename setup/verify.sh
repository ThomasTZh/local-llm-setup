#!/usr/bin/env bash
# Check a finished installation. Add --load to also run one short generation.
set -uo pipefail

AI_HOME="${AI_HOME:-$HOME/local-llm-setup}"
PORT="${AI_PORT:-8080}"
BASE="http://127.0.0.1:$PORT"
do_load=false
[ "${1:-}" = "--load" ] && do_load=true

fails=0
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }

echo "router"
if curl -sf -m 5 "$BASE/props" >/dev/null; then
  role=$(curl -sf -m 5 "$BASE/props" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("role","?"))')
  [ "$role" = "router" ] && ok "router answering on $BASE" || bad "service on $BASE is not a router (role=$role)"
  ids=$(curl -sf -m 5 "$BASE/v1/models" | python3 -c 'import json,sys; print("\n".join(m["id"] for m in json.load(sys.stdin)["data"]))')
  count=$(printf '%s\n' "$ids" | grep -c . || true)
  if [ "$count" -eq 3 ]; then
    ok "catalogue lists the expected three models"
  elif [ "$count" -ge 1 ]; then
    ok "catalogue lists $count models (the recorded machine has 3)"
  else
    bad "catalogue is empty"
  fi
  printf '%s\n' "$ids" | sed 's/^/        /'
else
  bad "no router on $BASE; start setup/router/start-router.sh"
fi

echo "weights"
if [ -f "$AI_HOME/models/SHA256SUMS" ]; then
  ( cd "$AI_HOME/models" && sha256sum -c --quiet SHA256SUMS ) && ok "weight hashes match" || bad "weight hash mismatch"
elif [ -f "$AI_HOME/models/manifest.json" ]; then
  # No flat checksum file: verify whatever is present against the manifest.
  if ( cd "$AI_HOME/models" && python3 - "$AI_HOME/models/manifest.json" <<'PY'
import hashlib, json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
bad = 0
checked = 0
for source in manifest.get("sources", []):
    for entry in source.get("files", []):
        path = pathlib.Path(entry["filename"])
        if not path.exists():
            print(f"missing {path}")
            bad += 1
            continue
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
                digest.update(block)
        checked += 1
        if digest.hexdigest() != entry["sha256"]:
            print(f"mismatch {path}")
            bad += 1
print(f"checked {checked} file(s), {bad} problem(s)")
sys.exit(1 if bad else 0)
PY
  ); then
    ok "weight hashes match models/manifest.json"
  else
    bad "weight hash mismatch or missing file"
  fi
else
  bad "no models/SHA256SUMS or models/manifest.json to verify against"
fi

echo "search stack (optional)"
if curl -sf -m 5 -o /dev/null http://127.0.0.1:8888/; then ok "SearXNG on 8888"; else bad "SearXNG not answering on 8888"; fi
token=""
[ -f "$HOME/.config/local-ai/web-stack/crawl4ai.env" ] && token=$(sed -n 's/^CRAWL4AI_API_TOKEN=//p' "$HOME/.config/local-ai/web-stack/crawl4ai.env")
if [ -n "$token" ]; then
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' -H "Authorization: Bearer $token" http://127.0.0.1:11235/health)
  [ "$code" = "200" ] && ok "Crawl4AI healthy on 11235" || bad "Crawl4AI returned $code on /health"
else
  bad "no Crawl4AI token found at ~/.config/local-ai/web-stack/crawl4ai.env"
fi

if [ "$do_load" = true ] && curl -sf -m 5 "$BASE/props" >/dev/null; then
  echo "generation (this loads the model, expect 30 to 90 seconds for the first call)"
  start=$(date +%s)
  answer=$(curl -s -m 300 "$BASE/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d '{"model":"swift-1.5-qwen3.8-27b-q4-k-s","messages":[{"role":"user","content":"Reply with the single word: ready"}],"max_tokens":16}' \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["choices"][0]["message"].get("content","").strip())' 2>/dev/null)
  elapsed=$(( $(date +%s) - start ))
  [ -n "$answer" ] && ok "model answered in ${elapsed}s: $answer" || bad "no answer from the model"
fi

echo
if [ "$fails" -eq 0 ]; then echo "verification passed"; else echo "$fails check(s) failed"; fi
[ "$fails" -eq 0 ]
