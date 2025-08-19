Dev Environment Automation — Public Master Reference 

Purpose 

    Reproducible, code-driven deployment of a homelab developer environment using Docker Compose, templates, and a reverse proxy.
     

Scope 

    Utilities stack (reverse proxy, dashboard, lifecycle tooling).
    AI/dev stack (LLM runtime and web UI; configuration via templates).
    Clear separation of concerns by VM/host, TLS for internal domains, and an audit-friendly workflow.
     

Key Components 

    Reverse proxy: Caddy (TLS termination, local internal CA).
    Dashboard: Glance (status, links, widgets).
    Image lifecycle: Watchtower.
    AI: Open WebUI (containerized), Ollama (host or container, configured via templates).
    Network access: private-only (e.g., Tailscale) and local DNS for internal hostnames.
     

High-level Architecture 

    Clients resolve internal app hostnames to the Utilities VM (reverse proxy).
    Caddy terminates TLS (internal CA) and proxies to services by container name (local) or IP (remote VMs).
    Each stack is generated from templates with envsubst to keep the repo free of secrets.
     

Repository Structure (short) 

    docker/
        deploy.sh (interactive generator and deployer)
        templates/ (Caddyfile, service configs, compose templates)
         
    docs/
        MASTER-REF.md (this file)
        ROADMAP.md
        OPERATIONS.md
        ADR/ (architecture decision records)
         
    terminal/ (terminal and tmux setup helpers)
     

Development Workflow (summary) 

    Configure .env locally (never commit secrets).
    Use deploy.sh to generate stack configs from templates and bring them up.
    Review logs and validate reverse proxy config before exposing new services.
    Use issues/branches/PRs to track and review changes.
