```markdown
# Dev Environment Automation
A toolkit to bootstrap and operate a secure, documented homelab and AI/ML platform on Docker Compose and Proxmox. Includes per‑app SSO (Authelia), reverse proxy (Caddy), acceptance checks, GPU profiles, and idempotent VM provisioning.

- Private-only access via Tailscale; no public ports
- Per‑app subdomain + per‑app portal SSO model (deny‑by‑default)
- Template-driven configs; secrets never committed
- Acceptance checks and validation commands for safe changes

## Highlights
- Utilities stack
  - Caddy (TLS; local CA), Authelia (SSO), Glance, Watchtower, Redis, Uptime Kuma, Vaultwarden, optional code-server
  - Per‑app SSO portals: auth.<app>.<domain> → Authelia; <app>.<domain> → forward_auth
- AI stack (profiles)
  - Backends: Ollama (OpenAI‑ish), llama.cpp (OpenAI‑compatible /v1)
  - Frontends/tools: Open WebUI, SillyTavern, ComfyUI, n8n, TTS (OpenAI‑compatible)
  - Oobabooga UI (SSO) and API (no SSO; supports API key)
- Proxmox automation
  - Declarative VMs via YAML; `qm` + cloud‑init; idempotent apply/delete
- Security posture
  - Tailscale only; split DNS to Caddy; local TLS with Caddy CA
  - Strip upstream Authorization at proxy; per‑app cookie scope; Vaultwarden admin guarded

## Architecture (summary)
- Ingress & Auth: Caddy reverse proxy with local TLS; Authelia for forward_auth
- Access: Tailscale; split DNS (Pi-hole) for *.lan to utilities VM
- Workloads:
  - Utilities VM (Caddy, Authelia, Glance, Watchtower, Redis, Uptime Kuma, Vaultwarden, code-server)
  - AI VM (Ollama, llama.cpp, Oobabooga, Open WebUI, SillyTavern, n8n, ComfyUI, TTS)
- DNS/SNI testing patterns to avoid TLS/forward_auth pitfalls

(WIP: Add an architecture.png diagram in docs/ and link it here.)

## Quick Start
Prereqs
- Linux host with Docker Engine + Compose plugin
- NVIDIA driver + Container Toolkit for GPU profiles
- Optional: Ansible (fan control), Proxmox API/SSH access (provisioning)

Steps
1) Clone
   - `git clone https://github.com/0xCcmndhd/dev-environment-automation.git`
   - `cd dev-environment-automation`
2) Utilities stack
   - `cd docker && ./deploy.sh` → choose “Utilities”
   - Script creates `~/docker/utilities`, writes `.env` interactively, generates Caddyfile/Authelia configs, and deploys
3) AI stack
   - `cd docker && ./deploy.sh` → choose “AI”
   - Select `COMPOSE_PROFILES` (e.g., `openwebui,ollama,watchtower,sillytavern,n8n,comfyui,tts-openedai` or add `llamacpp`)
   - Script creates `~/docker/ai` directories, writes `.env`, generates compose from templates, and deploys

## SSO & Reverse Proxy Model
- Per‑app portal approach:
  - `auth.<app>.lan` → Authelia (portal)
  - `<app>.lan` → Caddy `forward_auth` to Authelia at `/api/authz/forward-auth`
- Headers:
  - Copy identity headers from Authelia; strip upstream `Authorization`
  - Ensure `X-Forwarded-Proto: https` to backends
- Cookies:
  - Per‑app cookie scope to avoid cross‑app cookie leakage
- Known nuance:
  - HEAD against protected roots can 400; use GET with `-L` in checks

## Acceptance Checks (run these)
Caddyfile validate:
```bash
docker run --rm -v ~/docker/utilities/caddy:/c caddy:latest \
  caddy validate --config /c/Caddyfile
```

Authelia validate:
```bash
docker run --rm -v ~/docker/utilities/authelia/config:/config authelia/authelia:latest \
  authelia validate-config --config /config/configuration.yml
```

Portal SNI test:
```bash
curl -kI --resolve auth.glance.lan:443:192.168.120.208 https://auth.glance.lan/
```

Protected app (GET + follow redirects):
```bash
curl -kL -X GET --resolve glance.lan:443:192.168.120.208 https://glance.lan/ -o /dev/null -s -w "%{http_code}\n"
```

Backend health (bypass Caddy):
```bash
curl -sI http://192.168.120.189:7860 | head -n1   # Oobabooga UI
```

## Profiles: AI Stack (examples)
| Profile | Service | Notes |
| --- | --- | --- |
| openwebui | Open WebUI | Defaults to Ollama; can point to llama.cpp/TTS |
| ollama | Ollama | OpenAI-ish; `OLLAMA_HOST=0.0.0.0:11434` |
| llamacpp | llama.cpp | OpenAI-compatible server on port 8000 (/v1) |
| ooba | Oobabooga | UI (7860) behind SSO; API (5000) can use `--api-key` |
| n8n | n8n | SSO-protected |
| comfyui | ComfyUI | SSO-protected |
| tts-openedai | TTS | OpenAI-compatible endpoint |

llama.cpp defaults (template):
- Context (16384), `--flash-attn`, cache types q4_1, CPU‑MoE override (`-ot .ffn_.*_exps.=CPU`)
- Tune via `LLAMACPP_*` in `~/docker/ai/.env` (e.g., `LLAMACPP_MODEL_PATH`, `LLAMACPP_NGL`)

## Security Notes
- No public exposure; access via Tailscale only
- Local TLS via Caddy CA; import CA certs on clients for a clean browser experience
- Strip upstream `Authorization` at proxy to avoid header leakage/loops
- Vaultwarden:
  - No SSO; protect `/admin`, enforce `ADMIN_TOKEN`, `SIGNUPS_ALLOWED=false`, 2FA, IP headers, trusted proxies

## Proxmox VM Automation
- Files: `proxmox/provision.sh`, `proxmox/vms.example.yml`
- Apply desired state:
```bash
./proxmox/provision.sh apply -f proxmox/vms.yml
```
- Delete:
```bash
./proxmox/provision.sh delete -f proxmox/vms.yml
```
- Injects SSH pubkey, uses `qm` + cloud‑init; idempotent

## Troubleshooting
- If curl works but browser fails: import Caddy’s local CA, clear site data for app and portal hosts
- If protected routes 400: use `GET` + `-L` and proper SNI with `--resolve`
- Test backends directly by IP:port to isolate proxy vs app
- For Oobabooga, ensure `CMD_FLAGS.txt` has only valid flags (no quotes, no bare `--`)

## Repository Structure (short)
```
docker/
  deploy.sh
  templates/ (ai-compose, Caddy, Authelia, llama.cpp Dockerfile, helpers)
docs/
  ADR/, MASTER-REF.md, OPERATIONS.md, ROADMAP.md
proxmox/
  provision.sh, vms.example.yml
fan-control/
  README.md, Ansible role, systemd templates
terminal/
  setup-terminal.sh, setup-tmux.sh
```

## Roadmap (next up)
- Proxmox VM automation polish (apply/delete; idempotent)
- AI/search on backup server: SearXNG + Perplexica (routes + Ollama integration)
- Media/downloads separation (Jellyfin/Plex + Arr; qBittorrent + NZB)
- Vaultwarden hardening (admin route, token, trusted proxies, optional allowlist)
- IAM POC: AVP/Cedar RBAC+ABAC with PEP/PDP, decision logs, OPA comparison

## License
MIT 

---
