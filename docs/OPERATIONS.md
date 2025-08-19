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
