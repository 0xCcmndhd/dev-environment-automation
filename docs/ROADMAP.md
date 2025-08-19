Roadmap 

Status Summary 

    Stabilized: Utilities stack (Caddy, Glance, Watchtower), templated configs, local TLS.
    In Progress: Proxmox VM automation (CLI-first approach with cloud-init).
    Planned: SSO with Authelia, web IDE, CI, backups, observability.
     

Milestone M1 — Utilities Stack Stabilization [Done] 

    Caddy templated with envsubst, local TLS via internal CA.
    Glance healthy baseline config.
    Watchtower scheduled and scoped.
     

Milestone M2 — Proxmox VM Automation [In Progress] 

    Goals:
        Declarative VM inventory (YAML).
        Idempotent CLI-based provisioning (qm) with cloud-init.
        Safe defaults (bridge, CPU/mem/disk), consistent naming.
         
    Acceptance:
        A single command provisions or updates target VMs from inventory.
        SSH becomes available with a known user/cloud-init key.
        No secrets are committed to the repo.
         
     

Milestone M3 — Authentication and SSO 

    Authelia behind Caddy (SSO + 2FA).
    Protect sensitive apps (code-server, dashboards, admin UIs).
     

Milestone M4 — Web IDE for Remote Workflows 

    code-server or openvscode-server behind Caddy.
    Optional AI assistance via local or provider models.
     

Milestone M5 — CI and Hygiene 

    Basic CI: shellcheck, caddy validate, docker compose config.
    Pre-commit hooks to enforce style and safety checks.
    .env.example + docs for quick onboarding.
     

Milestone M6 — Backups and Recovery 

    Simple, documented backup/restore for config and data volumes.
    Proxmox backup integration (separate repo/host, out of scope here).
     

Out of Scope (for this repo) 

    Media/download app orchestration (separate stacks later).
    Public exposure of services; private-network access only by design.
