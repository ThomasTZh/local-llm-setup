#!/usr/bin/env bash
# Build llama.cpp at the pinned commit with the flags this catalogue was built with.
set -euo pipefail

AI_HOME="${AI_HOME:-$HOME/local-llm-setup}"
LLAMA_REPO="https://github.com/ggml-org/llama.cpp"
LLAMA_COMMIT="9f31776c3773cf03f98535c19b7e6d394af374b4"

SRC="$AI_HOME/src/llama.cpp"
BUILD="$AI_HOME/build"
mkdir -p "$AI_HOME/src"

if [ ! -d "$SRC/.git" ]; then
  git clone "$LLAMA_REPO" "$SRC"
fi
git -C "$SRC" fetch --tags
git -C "$SRC" checkout --detach "$LLAMA_COMMIT"
git -C "$SRC" submodule update --init --recursive

# 89 covers the RTX 4080; 120 covers the RTX 5060 Ti. Add 120a instead of 120 if
# you want the Blackwell feature-a target. Flash Attention is built in; add
# -DGGML_CUDA_FA_ALL_QUANTS=ON only if you need every quantised KV type.
cmake --fresh -S "$SRC" -B "$BUILD" \
  -DGGML_CUDA=ON \
  -DGGML_CUDA_FA=ON \
  -DCMAKE_CUDA_ARCHITECTURES="89;120" \
  -DCMAKE_CUDA_FLAGS=--cudart=shared \
  -DCMAKE_CUDA_RUNTIME_LIBRARY=Shared \
  -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_CURL=OFF

cmake --build "$BUILD" --config Release -j "$(nproc)"

# Shared-lib build: the binary is a small stub, the code lives in build/bin/*.so
"$BUILD/bin/llama-server" --version
echo
echo "built at $BUILD/bin/llama-server"
echo "next: setup/download-models.sh, then setup/router/install-router.sh"
