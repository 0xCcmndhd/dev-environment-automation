Operations 

Prerequisites 

    Docker Engine + Compose plugin installed.
    .env present locally (not committed). See .env.example for required keys.
     

Deploy or Update (Utilities) 

    cd docker
    ./deploy.sh
    Select “Utilities” → Deploy or Update Stack
    Verify:
        docker compose -f ~/docker/utilities/docker-compose.yml ps
        docker compose -f ~/docker/utilities/docker-compose.yml logs caddy --since=2m
        docker compose -f ~/docker/utilities/docker-compose.yml exec caddy caddy validate --config /etc/caddy/Caddyfile
         
     

Reverse Proxy Checks 

    Resolve internal hostnames to the reverse proxy host (Utilities VM).
    Validate config before reload:
        docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
         
    Quick end-to-end test from a client:
        curl -k -H "Host: app.local" https://<utilities-vm-ip> (expect 200/302)
         
     

Updating Images 

    Watchtower runs nightly and cleans up unused images.
    To force update now:
        docker compose -f ~/docker/utilities/docker-compose.yml pull
        docker compose -f ~/docker/utilities/docker-compose.yml up -d
         
     

Backing Up Config 

    Persisted paths (example):
        ~/docker/utilities/caddy/data
        ~/docker/utilities/caddy/config
        ~/docker/utilities/glance/config
        ~/docker/utilities/glance/assets
         
    Back up these directories routinely (rsync or snapshot).
     

Restoring 

    Recreate directories and restore contents.
    Re-run deploy.sh for the stack; containers will reuse restored data.
     

Troubleshooting 

    Caddy won’t start: run caddy validate; check logs for upstream mismatch or DNS errors.
    502 from proxy: test upstream directly from the caddy container with curl.
    Certificate warnings: import the reverse proxy’s local CA on the client device once.
     

Security Notes 

    No public ports are required; use private network access only.
    Enforce SSO (Authelia) for administrative apps when enabled.


AI Stack Operations

Deploy or Update (AI)
    cd docker
    ./deploy.sh
    Select “AI” → Deploy or Update Stack
    Choose COMPOSE_PROFILES (e.g., openwebui,ollama,watchtower or include llamacpp, sillytavern, etc.)
    Verify:
        docker compose -f ~/docker/ai/docker-compose.yml ps
        curl -f http://localhost:8000/health    # llama.cpp health (if enabled)
        curl -f http://localhost:11434/api/tags # Ollama health (if enabled)

Profiles and Directory Layout
    The AI stack will create directories only for selected profiles under ~/docker/ai/*
    Update COMPOSE_PROFILES in ~/docker/ai/.env and re-run deploy.sh → “Generate/Update Config Files” to change the selection

Open WebUI Wiring
    Defaults:
        OLLAMA_BASE_URL=http://ollama:11434
        OPENAI_API_BASE_URL=http://llamacpp:8000/v1
        TTS_URL=http://tts-openedai:8000/v1
    Check container logs if endpoints are not reachable:
        docker compose -f ~/docker/ai/docker-compose.yml logs -f open-webui

llama.cpp Tuning
    Set in ~/docker/ai/.env:
        LLAMACPP_MODEL_PATH=/models/<your>.gguf
        LLAMACPP_CTX_SIZE=16384
        LLAMACPP_NGL=80
        LLAMACPP_THREADS=24
        LLAMACPP_THREADS_BATCH=24
    The template places MoE experts on CPU via:
        -ot .ffn_.*_exps.=CPU
    Increase LLAMACPP_NGL or context size only if VRAM allows.
    Healthcheck:
        curl -f http://localhost:8000/health

Heavy Mode Helper (if llamacpp profile selected)
    ~/docker/ai/heavy-mode.sh status  # show compose + nvidia-smi
    ~/docker/ai/heavy-mode.sh on      # stop Ollama, start llama.cpp
    ~/docker/ai/heavy-mode.sh off     # stop llama.cpp, start Ollama

Troubleshooting
    Containers won’t start:
        docker compose -f ~/docker/ai/docker-compose.yml up -d --build
        docker compose -f ~/docker/ai/docker-compose.yml logs -f
    CUDA / Flash-Attn errors:
        Ensure host driver + toolkit match; the image builds llama.cpp with CUDA and Flash-Attn for arch 86 (Ampere).
    OOM on CPU:
        Reduce context (LLAMACPP_CTX_SIZE) or run fewer services.
