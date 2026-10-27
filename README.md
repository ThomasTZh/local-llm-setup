# Local LLM setup

Dual-GPU, local-first inference on a single Linux workstation: one `llama-server`
router for text and vision, Ollama as a fallback, and self-hosted search,
crawl, and image generation on loopback.

Snapshot recorded **27 October 2026**. This repository is a point-in-time record,
not an installer. Every value marked *verified* was read from the running system
on that date; see [`verification/snapshot-2026-10-27.md`](verification/snapshot-2026-10-27.md)
for the commands, results, and what could not be checked.

## Hardware

| Item | Value | Source |
|---|---|---|
| CPU | 12th Gen Intel Core i5-12600K, 10 cores / 16 threads | `lscpu`, verified |
| RAM | 31 GiB usable, 42 GiB swap | `free -h`, verified |
| GPU 0 | GeForce RTX 4080, 16 GB, compute 8.9 (`AD103`, PCIe 01:00.0) | `lspci` + profile, verified |
| GPU 1 | GeForce RTX 5060 Ti, 16 GB, compute 12.0 (`GB206`, PCIe 06:00.0) | `lspci` + profile, verified |
| GPU link | PCIe, no NVLink | `lspci` topology |
| Driver | NVIDIA 595.104.02, open kernel module | `/proc/driver/nvidia/version` |
| CUDA toolkit | 13.2 (V13.2.51) | `nvcc --version` |
| OS | Nobara Linux 44, kernel 7.2.11-200.nobara.fc44.x86_64 | `/etc/os-release` |

Two 16 GB cards, no peer access, so the layer split is what fits the model
rather than what the interconnect allows.

## Runtime

| Layer | Value |
|---|---|
| Engine | llama.cpp build `b10988`, version 0.4.1-dev |
| Commit | `9f31776c3` (15 September 2026) |
| CUDA build | `GGML_CUDA=ON`, `GGML_CUDA_FA=ON`, `GGML_CUDA_FA_ALL_QUANTS=OFF`, arches `89;120` |
| Server | `llama-server` in router mode on `127.0.0.1:8080` |
| Router policy | `max_instances 1`, `models_autoload true`, no preload: all models unloaded when idle |
| Per-request policy | `--parallel 1`, `--n-gpu-layers all`, `--split-mode layer`, `--flash-attn on`, `--no-context-shift`, `--no-cont-batching`, `--fit off`, `--cache-prompt`, `--metrics` |
| Threads | 7 generation, 8 batch; batch 1024 / ubatch 256 |

Compiled for both architectures so one binary serves the Ada and the Blackwell
card in a fixed `CUDA0, CUDA1` order.

## Models

Three catalogue entries share one resident slot; a request lazily loads the
selected profile and evicts the previous one.

| Profile | Weights | Context | KV K/V | Layer split | MTP | Alias |
|---|---|---:|---|---|---|---|
| Text (default) | Swift 1.5 Qwen3.8-27B Q4_K_S, 15.2 GiB | 217,088 | q8_0 / q5_1 | 28:36 | 3 draft tokens | `swift-1.5-qwen3.8-27b-q4-k-s` |
| Vision | same weights + F16 projector, 885 MiB | 180,224 | q8_0 / q5_1 | 28:36 | 3 draft tokens | `swift-1.5-qwen3.8-27b-q4-k-s-vision` |
| Second | Gemma-4-31B QAT Q4_0, 16.4 GiB | 65,536 | q8_0 / q8_0 | 2:3 | off | `gemma-4-31b-it-qat-q4-0-uncensored-heretic-q4-0` |

Profile settings live in [`config/profiles.json`](config/profiles.json); download
provenance with filenames, byte counts, and SHA-256 in
[`models/manifest.json`](models/manifest.json).

Pinned sources:

| Model | Repository | Revision |
|---|---|---|
| Swift 1.5 Qwen3.8-27B | `ukisai/Swift-1.5-Qwen3.8-27B-GGUF` | `a1614465cfa35d04d3e8575d713fa779662b5eab` |
| Gemma-4-31B QAT | `llmfan46/gemma-4-31B-it-qat-q4_0-uncensored-heretic-GGUF` | `053a14eaa2fb22e77f139d1adc5cb31960348765` |
| Gemma-4 chat template | `google/gemma-4-31b-it` | `842da3794eaa0b77d5f08bae87a17459d91ff475` |

Ollama holds one fallback model, `qwen3.8-27b-q4:latest`: 27.3B parameters,
Q4_K_M, 262,144-token context, vision and tools capable.

## Services

| Port | Service | Binding | Response on 27 Oct |
|---:|---|---|---|
| 8080 | llama.cpp router | `127.0.0.1` | reachable, `/v1/models` lists 3 entries |
| 11434 | Ollama | `127.0.0.1` | `200` |
| 8888 | SearXNG | `127.0.0.1` | `200` |
| 11235 | Crawl4AI | `127.0.0.1` | `307`, API key required |
| 3080 | DSH Web UI, general preset | `127.0.0.1` | `401`, authentication required |
| 3081 | DSH Web UI, second preset | `0.0.0.0` | `200` |
| 8188 | ComfyUI | not listening | image mode stopped |

Text inference, search, and crawl run as systemd user units with lingering
enabled, so they survive logout. Image generation has its own on-demand
lifecycle and is not part of the always-on set.

## Clients

| Client | Version | Role |
|---|---|---|
| DSH | 0.2.1-rc.2 | Primary agent harness, Web UI on `:3080`, optional second preset on `:3081` |
| Pi | 1.4.0 | Second harness, four model choices, MCP connections |
| Ollama CLI | 0.33.3 | Fallback inference outside the router |

OpenCode was undeployed on 24 October 2026; no `opencode` binary remains on
`PATH`. The harness set is DSH, Pi, and Ollama.

## Private web stack

Search and retrieval run in rootless Podman containers, pinned by digest.
Exact digests are kept out of this public copy; the versions identify the
release.

| Component | Version | Source |
|---|---|---|
| SearXNG | 2026.9.25-12f8b6515 | [ghcr.io/searxng/searxng](https://github.com/searxng/searxng/pkgs/container/searxng) |
| Crawl4AI | 0.9.4 | [docker.io/unclecode/crawl4ai](https://hub.docker.com/r/unclecode/crawl4ai) |

Both are `linux/amd64`. Crawl4AI runs without GPU access or cloud-model
credentials, keeps its default SSRF protections, and has hooks and internal-URL
access disabled. The MCP gateway in front of them exposes only `web_search`,
`web_fetch`, and `web_crawl`; crawl accepts explicit URLs and never follows
links.

## Image generation

A separate stack, not wired into the text harnesses.

| Item | Value |
|---|---|
| Stack | ComfyUI v0.37.0 (`73c9bad`), ComfyUI-GGUF (`373048b`), PyTorch 2.13.0+cu130, Python 3.13.14 |
| Diffusion | Sakura Qwen Image 2.1 Turbo Q4_K_M, 3.77 GiB |
| Text encoder | Qwen3VL 8B, BF16 |
| VAE | Qwen Image 2.1 VAE, BF16 |
| Sampler | 8 Euler steps, CFG 1.0, fixed sigma |
| Licence | Qwen Research License |
| GPU | RTX 5060 Ti, started on demand |

Full asset manifest: [`image-gen/manifest.json`](image-gen/manifest.json).

## Design notes

- Local inference, search, crawl, and image generation on one host; no cloud model calls.
- Weights pinned by repository revision and SHA-256; container images pinned by digest.
- Lazy router: no VRAM held until the first request, one model resident at a time.
- Backend services on loopback; the DSH Web UI requires authentication.
- Separate lifecycles for always-on text workloads and on-demand image workloads.
- One binary for two GPU architectures, with the device order fixed by UUID.
