# Dev Environment Automation

A toolkit to bootstrap and operate a personal AI/ML and homelab environment on Docker Compose. It includes:

- Dockerized stacks with templates (reverse proxy, SSO, dashboards, LLM backends, frontends)
- Proxmox VM provisioning (idempotent, CLI-first)
- GPU fan control automation (Ansible + systemd)
- Terminal/CLI environment setup (Fish, Starship, FastFetch, tmux)
- Documentation (ADR, operations, roadmap)

This README replaces the old fish-shell–only README.

---

## Features

- Utilities stack:
  - Caddy reverse proxy (TLS), Glance dashboard, Watchtower, Authelia (SSO), Redis, Uptime Kuma, Vaultwarden, optional code-server
  - Templated configs generated at deploy time (no secrets committed)
- AI stack:
  - Backends: Ollama, llama.cpp (OpenAI-compatible API)
  - Frontends: Open WebUI, SillyTavern
  - Pipelines, TTS (OpenAI-compatible), n8n automation, ComfyUI
  - Profiles select which services run
- Proxmox automation:
  - Declarative VMs via YAML, applied idempotently via `qm` + cloud-init
- Fan control:
  - Ansible role + systemd unit and scripts for GPU fan control
- Terminal:
  - Scripts for Fish/Starship/FastFetch and tmux

---

## Repository structure (short)

- docker/
  - deploy.sh (interactive generator and deployer)
  - templates/ (ai-compose, Caddy, Authelia, llama.cpp Dockerfile, helpers)
- docs/
  - ADR/, MASTER-REF.md, OPERATIONS.md, ROADMAP.md
- proxmox/
  - provision.sh, vms.example.yml
- fan-control/
  - README, Ansible role, systemd templates
- terminal/
  - setup-terminal.sh, setup-tmux.sh

---

## Quick start

Prerequisites:
- Linux host with Docker Engine + Compose plugin
- NVIDIA driver + NVIDIA Container Toolkit if using GPU
- python3 (for model helper scripts) if needed
- Ansible (optional, for fan-control)
- Proxmox API/SSH access (optional, for provisioning)

Steps:
1) Clone
   - git clone <your-repo-url>
   - cd dev-environment-automation

2) Utilities stack
   - cd docker
   - ./deploy.sh
   - Choose “Utilities”
   - The script:
     - Ensures Docker is installed and your user is in the `docker` group (you may need to log out/in)
     - Creates ~/docker/utilities
     - Writes a .env interactively (or reuses your existing one)
     - Generates docker-compose.yml and supporting configs (Caddyfile, Glance, Authelia)
     - Deploys the stack

3) AI stack
   - cd docker
   - ./deploy.sh
   - Choose “AI”
   - Select COMPOSE_PROFILES (e.g. openwebui,ollama,watchtower,sillytavern,n8n,comfyui,tts-openedai, or add llamacpp)
   - The script:
     - Writes/updates .env (AI paths and options)
     - Creates ~/docker/ai subdirectories for selected profiles
     - Generates an AI docker-compose.yml from templates
     - Optionally copies llama.cpp Dockerfile and helpers if llamacpp profile is selected
     - Deploys the stack

---

## llama.cpp defaults (in template)

The llama.cpp service (profile: llamacpp) is built from source with CUDA + Flash-Attn and runs:

- -m ${LLAMACPP_MODEL_PATH}
- -c ${LLAMACPP_CTX_SIZE} (default 16384)
- -ngl ${LLAMACPP_NGL} (default 80)
- --flash-attn
- --cache-type-k q4_1, --cache-type-v q4_1
- -ot .ffn_.*_exps.=CPU (override-tensor: MoE experts on CPU)
- threads/batch from .env defaults

These defaults allow CPU-MoE operation (experts on CPU, non-expert/attention on GPU) to keep VRAM use low. Adjust LLAMACPP_* values in .env to tune.

Set LLAMACPP_MODEL_PATH to your GGUF file path. The template defaults to a Qwen3-235B GGUF path.

---

## GPT-OSS 120B (MoE) example

To run on a GPU-poor setup with CPU-MoE:

- In ~/docker/ai/.env:
  - COMPOSE_PROFILES=llamacpp,openwebui,watchtower (or as you like)
  - LLAMACPP_MODEL_PATH=/models/gpt-oss-120b-mxfp4-00001-of-00003.gguf
  - LLAMACPP_NGL=999 (offload non-experts)
  - Keep -ot .ffn_.*_exps.=CPU as provided by the template
- Deploy the AI stack from docker/deploy.sh
- Expect ~5–8GB VRAM used with fast prefills; experts run on CPU.
- If you prefer the newer llama.cpp `--n-cpu-moe` flag, you can add it by editing the command in docker/templates/ai-compose.yml.template (or we can factor it into env in a follow-up change).

---

## Open WebUI wiring

- OLLAMA_BASE_URL defaults to http://ollama:11434 if profile enabled
- OPENAI_API_BASE_URL defaults to http://llamacpp:8000/v1 if profile enabled
- TTS_URL defaults to http://tts-openedai:8000/v1 if profile enabled
- Pipelines accessible via PIPELINES_URL

---

## Security notes

- No public exposure required; use local DNS/VPN to reach services
- Authelia is templated; configure secrets at runtime
- Do not commit local .env files

---

## Proxmox VM automation

- See proxmox/provision.sh and proxmox/vms.example.yml
- Apply: ./proxmox/provision.sh apply -f proxmox/vms.yml
- Delete: ./proxmox/provision.sh delete -f proxmox/vms.yml
- Uses SSH to run qm/pvesh on the Proxmox node; idempotent and safe

---

## Fan control

- See fan-control/README.md for Ansible role usage and systemd unit templates

---

## Terminal and tmux

- terminal/setup-terminal.sh configures Fish/Starship/FastFetch
- terminal/setup-tmux.sh installs tmux and configures Catppuccin theme and plugins

