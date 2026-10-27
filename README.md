# Local LLM setup

Two 16 GB graphics cards, one workstation, and nothing leaving the house: text
and vision inference, a private search and crawl stack, and on-demand image
generation all run locally. No cloud model calls.

This is a snapshot of the machine as it stood on **27 October 2026**. It
describes what is installed and how it is wired, not how to install it. The
short companion file [`verification/snapshot-2026-10-27.md`](verification/snapshot-2026-10-27.md)
records how each claim was checked and what could not be checked.

## The machine

An Intel i5-12600K with 16 threads and 31 GiB of memory, running Nobara 44 (a
Fedora-based KDE distribution) on kernel 7.2.11.

Two NVIDIA cards share the inference work:

| Card | Memory | Architecture | PCIe slot |
|---|---|---:|---|
| GeForce RTX 4080 | 16 GB | Ada, compute 8.9 | 01:00.0 |
| GeForce RTX 5060 Ti | 16 GB | Blackwell, compute 12.0 | 06:00.0 |

They are separate cards on the PCIe bus with no NVLink and no peer access, so a
model is split across them by layer, and the split is chosen to fit the model
rather than to exploit an interconnect. The driver is the 595 open kernel
module, with the CUDA 13.2 toolkit.

## How inference is wired

A single [llama.cpp](https://github.com/ggml-org/llama.cpp) build serves
everything: build `b10988`, version 0.4.1-dev, compiled against
[that pinned commit](https://github.com/ggml-org/llama.cpp/commit/9f31776c3773cf03f98535c19b7e6d394af374b4).
It is one binary compiled for both GPU architectures, 8.9 and 12.0, with CUDA
and Flash Attention enabled.

`llama-server` runs in router mode on `127.0.0.1:8080` and holds a catalogue of
three entries. Nothing is preloaded: the router idles at zero VRAM, loads the
model a request asks for, and evicts it when a different one is requested. Only
one model is ever resident.

Each request runs under a deliberately conservative set of rules: one slot, all
layers on the GPUs, layer-wise split across the two cards, Flash Attention on,
no context shifting, and no continuous batching. Prompt caching and metrics are
on. Seven threads generate and eight handle batching, with 1024-token batches
and 256-token micro-batches.

## The models

Three profiles, each pinned to a specific upstream revision. The links open
those revisions.

| Profile | Model | Size | Context | KV cache | Split | Extras |
|---|---|---:|---:|---|---|---|
| Default text | [Swift 1.5 Qwen3.8-27B, Q4_K_S](https://huggingface.co/ukisai/Swift-1.5-Qwen3.8-27B-GGUF/tree/a1614465cfa35d04d3e8575d713fa779662b5eab) | 15.2 GiB | 217,088 | Q8_0 keys, Q5_1 values | 28:36 | 3-token multi-token prediction |
| Vision | same weights, plus [the F16 projector](https://huggingface.co/ukisai/Swift-1.5-Qwen3.8-27B-GGUF/tree/a1614465cfa35d04d3e8575d713fa779662b5eab) | +885 MiB | 180,224 | Q8_0 keys, Q5_1 values | 28:36 | 3-token multi-token prediction, image input |
| Second opinion | [Gemma-4-31B QAT, Q4_0](https://huggingface.co/llmfan46/gemma-4-31B-it-qat-q4_0-uncensored-heretic-GGUF/tree/053a14eaa2fb22e77f139d1adc5cb31960348765) | 16.4 GiB | 65,536 | Q8_0 keys and values | 2:3 | none; runs with [Google's canonical chat template](https://huggingface.co/google/gemma-4-31B-it/tree/842da3794eaa0b77d5f08bae87a17459d91ff475) |

The text profile deliberately spends its context budget on a long window: 212K
tokens, which fits alongside its weights on the two cards because the values
cache is compressed. The vision profile gives up some context to make room for
the image projector. Gemma is the short-context alternative, split the other
way, and does not use multi-token prediction.

Ollama sits behind the router as a fallback path with a single model,
`qwen3.8-27b-q4`, a 27.3B-parameter Q4_K_M build with a 262K context, vision
and tool support.

Download provenance, exact byte counts, and SHA-256 hashes are in
[`models/manifest.json`](models/manifest.json). Profile settings as the launcher
reads them are in [`config/profiles.json`](config/profiles.json).

## Clients

| Client | Version | What it is for |
|---|---|---|
| DSH | 0.2.1-rc.2 | Primary agent harness, Web UI on port 3080, optional second preset on 3081 |
| Pi | 1.4.0 | Second harness, four model choices, MCP connections |
| Ollama CLI | 0.33.3 | Fallback inference outside the router |

OpenCode was removed on 24 October 2026 and no longer exists on this machine.

## What listens where

| Port | Service | Reachable from | State on 27 October |
|---:|---|---|---|
| 8080 | llama.cpp router | loopback | serving three catalogue entries |
| 11434 | Ollama | loopback | up |
| 8888 | SearXNG | loopback | up |
| 11235 | Crawl4AI | loopback | up, API key required |
| 3080 | DSH Web UI | loopback | up, authentication required |
| 3081 | DSH Web UI, second preset | all interfaces | up |
| 8188 | ComfyUI | not running | image mode stopped |

Text inference, search, and crawl are systemd user services with lingering
enabled, so they survive logout. Image generation starts and stops on demand and
is not part of the always-on set.

## Private search and retrieval

Web search and page retrieval run in rootless Podman containers, both built for
`linux/amd64`, both pinned by digest at deployment:

| Component | Version | Upstream |
|---|---|---|
| SearXNG | 2026.9.25 | [ghcr.io/searxng/searxng](https://github.com/searxng/searxng/pkgs/container/searxng) |
| Crawl4AI | 0.9.4 | [docker.io/unclecode/crawl4ai](https://hub.docker.com/r/unclecode/crawl4ai/tags?name=0.9.4) |

Crawl4AI runs without GPU access and without cloud-model credentials, keeps its
default SSRF protections, and has hooks and internal-URL access disabled. The
MCP gateway in front of the pair exposes exactly three tools: `web_search`,
`web_fetch`, and `web_crawl`. Crawl takes an explicit list of URLs and never
follows links on its own.

## Image generation

A separate stack, kept apart from text inference and not exposed to the agent
harnesses.

| Item | Value |
|---|---|
| Runtime | ComfyUI [0.37.0](https://github.com/Comfy-Org/ComfyUI/releases/tag/v0.37.0) with [ComfyUI-GGUF](https://github.com/leejet/ComfyUI-GGUF/commit/373048b8403a7820620065210a691263d4da0a61), PyTorch 2.13.0+cu130, Python 3.13 |
| Diffusion model | [Sakura Qwen Image 2.1 Turbo, Q4_K_M](https://huggingface.co/webmp3/Sakura-Qwen-Image-2.1-Turbo-Uncensored-GGUF), 3.77 GiB |
| Text encoder | Qwen3VL 8B, BF16, 16.3 GiB |
| VAE | Qwen Image 2.1, BF16 |
| Sampling | 8 Euler steps, CFG 1.0, fixed sigma schedule |
| Licence | Qwen Research License |
| Runs on | the RTX 5060 Ti, on demand |

It derives from [Qwen-Image-2.1-Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo).
The full asset record is in [`image-gen/manifest.json`](image-gen/manifest.json).

## Design choices

- Everything that matters runs locally: inference, search, crawl, image generation.
- Models are pinned by revision and hash; container images by digest, so a
  re-tagged upstream release cannot silently replace what is installed.
- The router holds no VRAM when idle and never keeps two models in memory.
- Backend services stay on loopback, and the Web UI requires authentication.
- Text and image workloads have separate lifecycles, so an image job cannot
  disturb an inference session.
- One binary covers two GPU architectures, with the device order fixed so the
  layer split is always read the same way.

## The rest of this repository

The prose above is the readable layer. Two kinds of file sit underneath it:

| File | Purpose |
|---|---|
| [`config/profiles.json`](config/profiles.json) | The profile settings the launcher reads, with local paths and device identifiers removed |
| [`models/manifest.json`](models/manifest.json) | Download record: sources, byte counts, and hashes for the weights |
| [`web-stack/images.json`](web-stack/images.json) | Container versions and tags, without digests |
| [`image-gen/manifest.json`](image-gen/manifest.json) | ComfyUI revisions and image model assets |
| [`verification/snapshot-2026-10-27.md`](verification/snapshot-2026-10-27.md) | What was checked, how, and the limits of the check |

Those JSON files keep exact identifiers because they are meant to be machine
checked. Nothing in them is needed to read this page.
