#!/usr/bin/env bash
# Install the private search and crawl stack as rootless Podman user services.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_dir="$HOME/.config/local-ai/web-stack"
unit_dir="$HOME/.config/systemd/user"

command -v podman >/dev/null || { echo "podman is required" >&2; exit 1; }
mkdir -p "$config_dir" "$unit_dir"

if [ ! -f "$config_dir/searxng-settings.yml" ]; then
  secret="$(openssl rand -hex 32)"
  sed "s|CHANGE_ME|$secret|" "$here/searxng-settings.yml" > "$config_dir/searxng-settings.yml"
  chmod 600 "$config_dir/searxng-settings.yml"
  echo "wrote $config_dir/searxng-settings.yml with a fresh secret"
else
  echo "keeping existing $config_dir/searxng-settings.yml"
fi

if [ ! -f "$config_dir/crawl4ai.env" ]; then
  install -m 600 "$here/crawl4ai.env.example" "$config_dir/crawl4ai.env"
  token="$(openssl rand -hex 32)"
  sed -i "s|CHANGE_ME|$token|" "$config_dir/crawl4ai.env"
  echo "wrote $config_dir/crawl4ai.env with a fresh API token"
else
  echo "keeping existing $config_dir/crawl4ai.env"
fi

# The original deployment pins both images by manifest digest. Digests are left
# out of this public copy; after pulling, pin them yourself:
#   podman images --digests | grep -E 'searxng|crawl4ai'
podman pull ghcr.io/searxng/searxng:2026.9.25-12f8b6515
podman pull docker.io/unclecode/crawl4ai:0.9.4

install -m 644 "$here/local-ai-searxng.service" "$unit_dir/local-ai-searxng.service"
install -m 644 "$here/local-ai-crawl4ai.service" "$unit_dir/local-ai-crawl4ai.service"

systemctl --user daemon-reload
systemctl --user enable --now local-ai-searxng.service local-ai-crawl4ai.service

echo
echo "waiting for both services"
for _ in $(seq 1 30); do
  searx=$(curl -s -o /dev/null -w '%{http_code}' -m 2 http://127.0.0.1:8888/ || true)
  token=$(sed -n 's/^CRAWL4AI_API_TOKEN=//p' "$config_dir/crawl4ai.env")
  crawl=$(curl -s -o /dev/null -w '%{http_code}' -m 2 -H "Authorization: Bearer $token" http://127.0.0.1:11235/health || true)
  [ "$searx" = "200" ] && [ "$crawl" = "200" ] && break
  sleep 2
done

echo "SearXNG  http://127.0.0.1:8888/        status $searx"
echo "Crawl4AI http://127.0.0.1:11235/health  status $crawl"
echo
echo "API token for clients: $token"
echo "to survive logout on a headless host: loginctl enable-linger $USER"
