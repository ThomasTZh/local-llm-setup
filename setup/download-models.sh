#!/usr/bin/env bash
# Fetch the three pinned model files, the image projector, and the Gemma chat
# template, then verify every hash. About 34 GB of downloads.
set -euo pipefail

AI_HOME="${AI_HOME:-$HOME/local-llm-setup}"
MODELS="$AI_HOME/models"
CONFIG="$AI_HOME/config"

SWIFT_REPO="ukisai/Swift-1.5-Qwen3.8-27B-GGUF"
SWIFT_REV="a1614465cfa35d04d3e8575d713fa779662b5eab"
GEMMA_REPO="llmfan46/gemma-4-31B-it-qat-q4_0-uncensored-heretic-GGUF"
GEMMA_REV="053a14eaa2fb22e77f139d1adc5cb31960348765"
TEMPLATE_REPO="google/gemma-4-31B-it"
TEMPLATE_REV="842da3794eaa0b77d5f08bae87a17459d91ff475"

if ! command -v hf >/dev/null; then
  echo "the hf CLI is missing: pipx install huggingface_hub" >&2
  exit 1
fi

mkdir -p "$MODELS" "$CONFIG"

# Gated repositories need a token: hf auth login
hf download "$SWIFT_REPO" --revision "$SWIFT_REV" \
  --include "Swift-1.5-Qwen3.8-27B-Q4_K_S.gguf" "mmproj-Swift-1.5-Qwen3.8-27B-F16.gguf" \
  --local-dir "$MODELS"

hf download "$GEMMA_REPO" --revision "$GEMMA_REV" \
  --include "*Q4_0.gguf" \
  --local-dir "$MODELS"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
hf download "$TEMPLATE_REPO" --revision "$TEMPLATE_REV" \
  --include "chat_template.jinja" \
  --local-dir "$tmp"
install -m 644 "$tmp/chat_template.jinja" "$CONFIG/gemma4-chat-template.jinja"

cat > "$MODELS/SHA256SUMS" <<'SUMS'
46a360c2cdde61b044c0ec188aaca9127689ab0e2418e870de6127e47345ac2c  Swift-1.5-Qwen3.8-27B-Q4_K_S.gguf
daa1116c9422fa390cc8688495da0e91781f92841dfc3b31a378ff252571745a  mmproj-Swift-1.5-Qwen3.8-27B-F16.gguf
b51c17e9011abaf08158f9534be1b21f0cde4999a4a064c8d5286f4e2b2c37fa  gemma-4-31B-it-qat-q4_0-uncensored-heretic-Q4_0.gguf
SUMS

echo
echo "verifying weights (about 34 GB of reads)"
( cd "$MODELS" && sha256sum -c SHA256SUMS )

echo "verifying the chat template"
echo "ae53464bf3be25802b3a5b37def7fd89667067d7577049b3b2d74c4d8de4c6d4  $CONFIG/gemma4-chat-template.jinja" | sha256sum -c -

echo
echo "all files verified"
echo "next: setup/router/install-router.sh, then setup/router/start-router.sh"
