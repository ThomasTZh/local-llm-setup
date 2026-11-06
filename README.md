# Local LLM setup

This repository records how to run several AI tools on one desktop computer, with
no cloud service and no internet connection. It lists the exact programs, files,
and settings that worked together, so the same setup can be rebuilt on a similar
machine. Each claim is backed by a check, and steps that were never run are
marked as untested.

## Purpose and gaps

The repository exists so that a working local-AI deployment can be rebuilt from
a written record instead of from a running machine.

- **Gap:** upstream documentation covers each component in isolation [1][2][5].
  It does not pin the engine build, weight revisions, hashes, and container
  versions that worked together on two GPUs, and it does not separate claims
  that were checked from claims that were not.
- **Approach:** publish those pinned identifiers, a scripted recipe under
  [`setup/`](setup/README.md), and a verification record that marks what was not
  run.

## Features

- **Text and vision inference:** a llama.cpp [1] router on `127.0.0.1:8080`
  holds three profiles and loads one at a time.
- **Long context on 30 GB:** 217,088 tokens for text and 180,224 for vision,
  using Q8_0 key and Q5_1 value caches and a 28:36 layer split.
- **Zero idle VRAM:** nothing is preloaded; `GET /v1/models` lists three ids and
  a request loads only the model it names.
- **Fallback model:** Ollama [10] serves `qwen3.8-27b-q4` on `127.0.0.1:11434`
  outside the router.
- **Private search and crawl:** SearXNG [7] on `8888` and Crawl4AI [8] on
  `11235`, both in rootless Podman containers, exposed as three tools
  (`web_search`, `web_fetch`, `web_crawl`).
- **On-demand images:** ComfyUI [6] with Sakura Qwen Image 2.1 Turbo [5] on the
  second card, started and stopped independently of inference.
- **Rebuild and check:** `setup/preflight.sh`, `build-llama.sh`,
  `download-models.sh`, `router/install-router.sh`, `router/start-router.sh`
  and `verify.sh`; steps 0 to 4 take about an hour, mostly build and download.

## Not for / limitations

- **Not for one 16 GB card.** The catalogue assumes roughly 30 GB across two
  cards; one 16 GB card cannot hold the default profile, and one 24 GB card
  would need a shorter context.
- **Not a multi-user service.** Every service binds to loopback except the
  second DSH preset on `3081`. One model is resident at a time, and a request
  that switches profiles waits for the load.
- **No performance figures.** Throughput, latency, and VRAM-in-use measurements
  were out of scope, so there are no speed numbers to compare against. The
  checks below cover correctness, not speed.
- **Some checks could not run.** GPU memory in use, PCIe topology, and
  peer-access tests need NVIDIA device nodes that the recording shell did not
  have; the 16 GB figures are the rated capacity of each card.
- **Not everything was executed.** A clean-machine run of the full sequence, the
  build script, and the download script were not run (existing artifacts were
  hashed instead). The Podman install path, starting ComfyUI, and `verify.sh
  --load` were also untested. Details are in [`setup/README.md`](setup/README.md)
  and the verification record.
- **Weights and container images are not redistributed.** They are fetched from
  upstream under their own licences; see [Licenses](#licenses).
- **No orchestration or remote access.** This is a single-workstation setup, not
  a cluster or a hosted service.

## Reproduction environment

| Component | Requirement |
| --- | --- |
| Operating system | Nobara 44 (Fedora-based KDE), kernel 7.2.11, x86_64 |
| Language/compiler | `g++` and CMake for the llama.cpp build; CUDA toolkit 13.2 (`nvcc` V13.2.51); Python 3.13 for the image stack |
| Hardware | Intel i5-12600K, 10 cores and 16 threads, 31 GiB RAM; RTX 4080 16 GB (Ada, compute 8.9) and RTX 5060 Ti 16 GB (Blackwell, compute 12.0), no NVLink; NVIDIA 595.104.02 open kernel module |
| Libraries | llama.cpp b10988 (commit `9f31776c3`), Ollama 0.33.3, PyTorch 2.13.0+cu130, ComfyUI 0.37.0, ComfyUI-GGUF `373048b` |
| Input | None. The recipe downloads 34 GB of weights and verifies four SHA-256 values |

## Install and run

Run from the repository root. The recipe installs into `AI_HOME`, default
`~/local-llm-setup`.

```bash
export AI_HOME="$HOME/local-llm-setup"

# 0. check GPUs, toolkit, disk, and memory; changes nothing
bash setup/preflight.sh

# 1. build llama.cpp at the pinned commit with CUDA and Flash Attention
bash setup/build-llama.sh

# 2. fetch 34 GB of weights and verify four SHA-256 values
bash setup/download-models.sh

# 3. render the router preset and start it on 127.0.0.1:8080
bash setup/router/install-router.sh
bash setup/router/start-router.sh

# 4. verify endpoints, catalogue, and hashes; --load forces one generation
bash setup/verify.sh
bash setup/verify.sh --load
```

Optional additions:

```bash
bash setup/web-stack/install-web-stack.sh   # SearXNG and Crawl4AI
# image generation: see setup/image-gen/README.md
```

Expected output: `GET /v1/models` lists three ids with nothing loaded;
`verify.sh` reports the router, the three model ids, both web services when
installed, and three matching weight hashes; `verify.sh --load` returns a short
reply. Requirements, per-card tuning, and the exact unexecuted steps are in
[`setup/README.md`](setup/README.md).

## Layout

| Component | Path | Contents | Class |
| --- | --- | --- | --- |
| Project description | `README.md` | This page | Original |
| Rebuild recipe | `setup/` | Seven scripts, three service units, router preset template, example environment files | Original |
| Launcher profiles | `config/profiles.json` | Context, cache, split, and template settings; local paths and device identifiers removed | Original |
| Weight record | `models/manifest.json` | Repositories, revisions, byte counts, SHA-256 hashes | Original |
| Container record | `web-stack/images.json` | SearXNG and Crawl4AI versions and tags; digests omitted | Original |
| Image stack record | `image-gen/manifest.json` | ComfyUI revisions and asset hashes | Original |
| Verification record | `verification/` | What was checked, how, and what was not | Original |
| llama.cpp | — | b10988, commit `9f31776c3`; MIT [1] | Third-party |
| Swift 1.5 Qwen3.8-27B | — | Revision `a1614465`, Q4_K_S weights plus F16 projector [2] | Third-party |
| Gemma-4-31B QAT Q4_0 | — | Revision `053a14ea` [3], with the canonical chat template from `google/gemma-4-31B-it` [4] | Third-party |
| Sakura Qwen Image 2.1 Turbo | — | Revision `583e2bf9`, Qwen Research Licence [5] | Third-party |
| ComfyUI and ComfyUI-GGUF | — | 0.37.0 and `373048b`; GPL-3.0 and Apache-2.0 [6] | Third-party |
| SearXNG | — | 2026.9.25; AGPL-3.0 [7] | Third-party |
| Crawl4AI | — | 0.9.4; Apache-2.0 [8] | Third-party |
| Ollama | — | 0.33.3 client and server; MIT [10] | Third-party |

No upstream file is copied into this repository. The third-party rows are
fetched during installation and keep their own licences.

## Results

| Check | Conditions | Result |
| --- | --- | --- |
| Weight integrity | Four files on disk, SHA-256 recomputed | 4/4 match [`models/manifest.json`](models/manifest.json); prefixes `46a360c2…`, `daa1116c…`, `b51c17e9…`, `ae53464b…` |
| Model catalogue | `GET /v1/models` on the running router | Three ids, all unloaded |
| Service ports | One HTTP request per port | 8080 router metadata; 11434, 8888, and 3081 return 200; 11235 returns 307 asking for a key; 3080 returns 401; 8188 refuses a connection |
| Recipe scripts | Shell syntax check, all seven scripts | Pass |
| Router preset | Started from the rendered preset on an alternate port without local tooling | Role `router`, `max_instances 1`, three expected model ids |
| `verify.sh` | Against the live services | Pass: router, three model ids, both web services, three weight hashes |
| Upstream links | One request per link | All resolve. The Sakura revision recorded at download now returns 404 after an upstream history rewrite, so the model is linked by repository and local hashes remain the integrity check |

No throughput, latency, or VRAM measurement was produced. Those numbers are
absent from this release, not merely unlisted.

## Acknowledgements

- The llama.cpp [1] authors for the engine, and the model publishers [2][3][4]
  for weights and chat templates.
- Sakura Qwen Image 2.1 Turbo [5] builds on Qwen-Image-2.1-Turbo [9]; both are
  used under the Qwen Research Licence.
- The ComfyUI and ComfyUI-GGUF maintainers [6], SearXNG [7], and Crawl4AI [8]
  provide the runtimes behind the optional stacks.
- Ollama [10] provides the fallback model server.
- DSH and Pi act as clients in the recorded deployment; neither is distributed
  here.

## References

1. ggml-org. *llama.cpp*, commit `9f31776c3773cf03f98535c19b7e6d394af374b4`, MIT Licence. <https://github.com/ggml-org/llama.cpp/commit/9f31776c3773cf03f98535c19b7e6d394af374b4>
2. ukisai. *Swift-1.5-Qwen3.8-27B-GGUF*, revision `a1614465cfa35d04d3e8575d713fa779662b5eab`; licence as stated on the model card. <https://huggingface.co/ukisai/Swift-1.5-Qwen3.8-27B-GGUF/tree/a1614465cfa35d04d3e8575d713fa779662b5eab>
3. llmfan46. *gemma-4-31B-it-qat-q4_0-uncensored-heretic-GGUF*, revision `053a14eaa2fb22e77f139d1adc5cb31960348765`, Apache-2.0. <https://huggingface.co/llmfan46/gemma-4-31B-it-qat-q4_0-uncensored-heretic-GGUF/tree/053a14eaa2fb22e77f139d1adc5cb31960348765>
4. Google. *gemma-4-31B-it*, revision `842da3794eaa0b77d5f08bae87a17459d91ff475`, `chat_template.jinja`. <https://huggingface.co/google/gemma-4-31B-it/tree/842da3794eaa0b77d5f08bae87a17459d91ff475>
5. webmp3. *Sakura-Qwen-Image-2.1-Turbo-Uncensored-GGUF*, revision `583e2bf97f2df7b6e194df07a2f4d8185d7989c1`, Qwen Research Licence. <https://huggingface.co/webmp3/Sakura-Qwen-Image-2.1-Turbo-Uncensored-GGUF>
6. Comfy-Org. *ComfyUI* 0.37.0, commit `73c9bad4d21e7addbe1d13bc92eee0f1431b017d`, GPL-3.0. <https://github.com/Comfy-Org/ComfyUI/releases/tag/v0.37.0>; leejet. *ComfyUI-GGUF*, commit `373048b8403a7820620065210a691263d4da0a61`, Apache-2.0. <https://github.com/leejet/ComfyUI-GGUF/commit/373048b8403a7820620065210a691263d4da0a61>
7. SearXNG. *SearXNG* 2026.9.25, AGPL-3.0; container `ghcr.io/searxng/searxng`. <https://github.com/searxng/searxng/pkgs/container/searxng>
8. UncleCode. *Crawl4AI* 0.9.4, Apache-2.0; image `docker.io/unclecode/crawl4ai`. <https://hub.docker.com/r/unclecode/crawl4ai/tags?name=0.9.4>
9. Qwen. *Qwen-Image-2.1-Turbo*, base model for [5]. <https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo>
10. Ollama. *Ollama* 0.33.3, MIT Licence. <https://ollama.com>

## Licenses

- **Original files:** `README.md`, `setup/`, `config/`, `models/`, `web-stack/`,
  `image-gen/`, and `verification/`. No licence file is included in this
  repository yet, so no licence is granted for reuse; add one before
  redistributing these files.
- **Third-party components:** not redistributed here. Each keeps its upstream
  licence: llama.cpp MIT [1], ComfyUI GPL-3.0 [6], ComfyUI-GGUF Apache-2.0 [6],
  SearXNG AGPL-3.0 [7], Crawl4AI Apache-2.0 [8], Ollama MIT [10], and the model
  weights under the terms on their model cards [2][3][4][5].
- **Obtained separately:** weights, container images, and toolchains are
  downloaded during installation and are never bundled with the repository.
