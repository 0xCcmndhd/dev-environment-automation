# Docker Stack and Templates

This folder holds the interactive deployer (deploy.sh) and Compose templates for Utilities and AI stacks.

---

## What deploy.sh does

- Ensures Docker is installed and running
  - Adds your user to the docker group on first run (requires logout/login)
- Creates ~/docker/<stack> folders (utilities or ai)
- Manages a local .env (never committed) with your answers
- Generates config files from templates
- Deploys with `docker compose up -d`

Stacks:
- Utilities: reverse proxy (Caddy), dashboard (Glance), Watchtower, Authelia (SSO), Redis, Uptime Kuma, Vaultwarden, optional code-server
- AI: Ollama, llama.cpp, Open WebUI, SillyTavern, pipelines, n8n, ComfyUI, TTS (OpenAI-compatible)

Main menu (stack selection) is in deploy.sh. Service profiles for the AI stack are selected by COMPOSE_PROFILES in .env.

---

## Templates overview

- templates/ai-compose.yml.template
  - Compose file for AI services, selected via COMPOSE_PROFILES
  - Services:
    - watchtower (profile: watchtower)
    - ollama (profile: ollama)
    - llamacpp (profile: llamacpp)
      - Built from templates/llamacpp.Dockerfile.template
      - Command defaults:
        - -m ${LLAMACPP_MODEL_PATH}
        - -c ${LLAMACPP_CTX_SIZE:-16384}
        - -ngl ${LLAMACPP_NGL:-80}
        - --flash-attn
        - --cache-type-k q4_1 --cache-type-v q4_1
        - -ot .ffn_.*_exps.=CPU (MoE experts on CPU)
        - --threads ${LLAMACPP_THREADS:-24}
        - --threads-batch ${LLAMACPP_THREADS_BATCH:-24}
      - Exposes OpenAI-compatible HTTP API on port 8000
      - Binds ${LLAMACPP_MODELS_DIR} to /models
    - openwebui (profile: openwebui)
      - Exposes 3000
      - Environment defaults wire it to Ollama and/or llama.cpp
    - pipelines (profile: openwebui)
    - sillytavern (profile: sillytavern)
      - Exposes 3001
    - n8n (profile: n8n)
      - Exposes 5678
    - comfyui (profile: comfyui)
      - Exposes 8188
    - tts-openedai (profile: tts-openedai)
      - Exposes 8010
  - GPU access is enabled with Compose `deploy.resources.reservations.devices` for NVIDIA

- templates/Caddyfile.template
  - Reverse proxy configuration for Utilities stack (ports 80/443)
  - Generated to ~/docker/utilities/caddy/Caddyfile

- templates/glance.yml.template
  - Glance dashboard config template
  - Generated to ~/docker/utilities/glance/config/glance.yml

- templates/authelia/configuration.yml.template + templates/authelia/apps.yml
  - Authelia config is rendered dynamically using `docker run ghcr.io/mikefarah/yq`
  - You’ll be prompted for the initial admin password (argon2id hash is generated)
  - The apps.yml file provides .apps[] and a .domain; apps with `sso: true` or `cookie: true` drive cookie and access-control sections
  - Rendered to ~/docker/utilities/authelia/config/configuration.yml and users_database.yml

- templates/llamacpp.Dockerfile.template
  - Builds llama.cpp with:
    - CUDA ON, Flash-Attn enabled (Ampere arch 86), CURL ON
    - Targets `llama-server` and `llama-cli`
  - Used by the llamacpp service

- templates/get_235b.py.template
  - Example GGUF downloader for Qwen3-235B shards
  - Copied to ~/docker/ai/llamacpp/models/get_235b.py when llamacpp profile selected

- templates/heavy-mode.sh.template
  - Convenience script to toggle “heavy” mode (stop Ollama, start llama.cpp) and back
  - Copied to ~/docker/ai/heavy-mode.sh when llamacpp profile selected

- quick-check-utilities.sh
  - Sanity checks for Docker/Compose/NVIDIA and common tooling
  - Run it before deploying Utilities if you want a preflight check

---

## .env management

- deploy.sh will prompt for:
  - General: TZ, LOCAL_DOMAIN, PUID, PGID, GLANCE_WEATHER_LOCATION
  - Infra IPs: PROXMOX_IP, UNIFI_IP, TRUENAS_IP
  - DNS: PIHOLE_PRIMARY_IP, PIHOLE_SECONDARY_IP, PIHOLE_PASSWORD
  - Service VM IPs: AI_SERVER_IP, MEDIA_SERVER_IP, DOWNLOADS_SERVER_IP
- AI overrides:
  - COMPOSE_PROFILES (CSV of: openwebui,ollama,llamacpp,watchtower,sillytavern,n8n,comfyui,tts-openedai)
  - OLLAMA_MODELS_DIR (default /opt/models)
  - LLAMACPP_MODELS_DIR (optional)
  - LLAMACPP_MODEL_PATH (optional; set to your GGUF)
  - Defaults added for llama.cpp if missing:
    - LLAMACPP_CTX_SIZE=16384
    - LLAMACPP_NGL=80
    - LLAMACPP_THREADS=24
    - LLAMACPP_THREADS_BATCH=24

---

## Deploy flows

Utilities:
- Creates ~/docker/utilities
- Generates docker-compose.yml with these services: watchtower, caddy, glance, redis, authelia, uptime-kuma, vaultwarden (+ optional code)
- Generates Caddyfile, glance.yml, and Authelia configs
- Deploys via `docker compose up -d`

AI:
- Creates ~/docker/ai
- Prepares directories for selected profiles
- Writes ai docker-compose.yml from template
- If llamacpp is selected:
  - Copies Dockerfile and helper scripts
  - Adds default LLAMACPP_* envs
- Deploys via `docker compose up -d`

---

## Notes and tips

- GPU access requires NVIDIA Container Toolkit. Test: `docker run --rm --gpus all nvidia/cuda:12.3.2-base nvidia-smi`
- llama.cpp K/V cache mode is q4_1 by default in the template to reduce VRAM use
- For GPT-OSS 120B MoE:
  - Set LLAMACPP_MODEL_PATH to the mxfp4 GGUF
  - Keep `-ot .ffn_.*_exps.=CPU` for CPU experts
  - Increase LLAMACPP_NGL if you have VRAM headroom
- Open WebUI defaults assume Ollama and/or llama.cpp are running in the same Compose project
