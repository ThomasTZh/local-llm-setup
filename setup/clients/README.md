# Connecting clients

Everything below speaks the OpenAI-compatible API that `llama-server` exposes, so
any client that accepts a base URL and a model id will work.

| Endpoint | Base URL | Notes |
|---|---|---|
| Router | `http://127.0.0.1:8080/v1` | Model ids from `GET /v1/models`; the API key is not checked, any string works |
| Ollama | `http://127.0.0.1:11434/v1` | Only if you installed the Ollama fallback separately |

Model ids on the router are the section names in `setup/router/models.ini`:

- `swift-1.5-qwen3.8-27b-q4-k-s` for text, 217,088 tokens of context
- `swift-1.5-qwen3.8-27b-q4-k-s-vision` for images, 180,224 tokens
- `gemma-4-31b-it-qat-q4-0-uncensored-heretic-q4-0` for the short-context second opinion, 65,536 tokens

## Pi

Copy [`pi-models.json`](pi-models.json) to `~/.pi/agent/models.json`, then:

```bash
pi --list-models
pi --model llama-cpp/swift-1.5-qwen3.8-27b-q4-k-s
```

The file also carries the thinking-level mapping per model, which is what makes
the thinking selector in Pi behave. The `apiKey` value is a placeholder; the
router ignores it.

## DSH

A stock DSH install (`dsh web`) can be pointed at the router base URL with any of
the three model ids. The DSH configuration on the recorded machine is bespoke:
presets, the MCP gateway, and the notification plugin are local work that is not
part of this recipe. Treat DSH as one client among several, not a dependency.

## Tools

The recorded machine wires search and crawl into DSH through a small stdio MCP
gateway that exposes `web_search`, `web_fetch`, and `web_crawl`. That gateway is
not published here. The services it calls are plain HTTP:

- SearXNG: `GET http://127.0.0.1:8888/search?q=...&format=json`, enabled by the
  `formats: [html, json]` line in the settings file
- Crawl4AI: `POST http://127.0.0.1:11235/crawl` with
  `Authorization: Bearer <your token>`

Point any MCP server or script at those two endpoints.
