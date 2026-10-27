#!/usr/bin/env bash
# Check that this machine can follow the recipe. Read-only.
set -uo pipefail

AI_HOME="${AI_HOME:-$HOME/local-llm-setup}"
require_disk_gb=90
fails=0
warns=0

ok()    { printf '  ok    %s\n' "$*"; }
warn()  { printf '  warn  %s\n' "$*"; warns=$((warns + 1)); }
bad()   { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }

echo "host"
command -v nvidia-smi >/dev/null && ok "nvidia-smi present" || bad "nvidia-smi not found: install the NVIDIA driver"
if nvidia-smi -L >/dev/null 2>&1; then
  gpus=$(nvidia-smi --query-gpu=name,memory.total,driver_version,compute_cap --format=csv,noheader)
  while IFS= read -r line; do ok "GPU: $line"; done <<< "$gpus"
  count=$(printf '%s\n' "$gpus" | wc -l)
  total_mib=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | awk '{sum += $1} END {print sum + 0}')
  [ "$count" -ge 2 ] && ok "$count GPUs visible" || warn "only $count GPU: two are assumed by the layer split"
  [ "$total_mib" -ge 30000 ] && ok "combined VRAM ${total_mib} MiB" || bad "combined VRAM ${total_mib} MiB is below the 30 GB this catalogue needs"
else
  bad "nvidia-smi cannot talk to the driver"
fi
command -v nvcc >/dev/null && ok "nvcc: $(nvcc --version | tail -1)" || bad "nvcc not found: install the CUDA toolkit"
command -v cmake >/dev/null && ok "cmake: $(cmake --version | head -1)" || bad "cmake not found"
command -v g++ >/dev/null && ok "g++: $(g++ --version | head -1)" || bad "g++ not found"
command -v git >/dev/null && ok "git present" || bad "git not found"
command -v python3 >/dev/null && ok "python3: $(python3 --version)" || bad "python3 not found"
command -v hf >/dev/null && ok "hugging-face cli present" || warn "hf CLI not found: pipx install huggingface_hub"
command -v podman >/dev/null && ok "podman present" || warn "podman not found: only needed for the search and crawl stack"
command -v curl >/dev/null && ok "curl present" || bad "curl not found"

avail_kb=$(df -Pk "$(dirname "$AI_HOME")" 2>/dev/null | awk 'NR==2 {print $4}')
avail_gb=$(( ${avail_kb:-0} / 1024 / 1024 ))
[ "$avail_gb" -ge "$require_disk_gb" ] && ok "disk free at $AI_HOME: ${avail_gb} GB" \
  || bad "disk free at $AI_HOME: ${avail_gb} GB, need about ${require_disk_gb} GB"

mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_gb=$(( mem_kb / 1024 / 1024 ))
[ "$mem_gb" -ge 30 ] && ok "memory: ${mem_gb} GB" || warn "memory: ${mem_gb} GB; 32 GB is the tested figure"

echo
echo "$fails failure(s), $warns warning(s)"
[ "$fails" -eq 0 ]
