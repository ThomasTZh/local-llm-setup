#!/usr/bin/env bash
# Start the llama.cpp catalogue router. Nothing loads until the first request.
set -euo pipefail

AI_HOME="${AI_HOME:-$HOME/local-llm-setup}"
AI_HOST="${AI_HOST:-127.0.0.1}"
AI_PORT="${AI_PORT:-8080}"

# Lowest PCI bus number first. On this machine that is the RTX 4080 at 01:00.0,
# so CUDA0 is the 4080 and CUDA1 is the 5060 Ti, matching tensor-split 28,36.
# If your cards enumerate the other way round, set AI_GPU_UUIDS to two UUIDs in
# the desired order, separated by a comma. Read them with:
#   nvidia-smi --query-gpu=uuid,pci.bus_id,name --format=csv
export CUDA_DEVICE_ORDER=PCI_BUS_ID
if [ -n "${AI_GPU_UUIDS:-}" ]; then
  export CUDA_VISIBLE_DEVICES="$AI_GPU_UUIDS"
fi

# CUDA graphs are disabled in this build; a split model measured no faster with
# them, and they complicate slot reuse between models.
export GGML_CUDA_DISABLE_GRAPHS=1
export LLAMA_CACHE="$AI_HOME/runtime/cache"
mkdir -p "$LLAMA_CACHE"

exec "$AI_HOME/build/bin/llama-server" \
  --models-preset "$AI_HOME/runtime/models.ini" \
  --models-max 1 \
  --host "$AI_HOST" \
  --port "$AI_PORT" \
  --log-verbosity 4
