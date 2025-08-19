ADR-0001: Ingress and DNS 

Decision 

    Use Caddy as the single ingress for internal apps with automatic TLS via local_certs.
    Use internal DNS to resolve app hostnames to the reverse proxy host.
    Proxy to backends by container name (local) or IP (remote VM).
     

Context 

    Need turnkey TLS on private networks and consistent hostnames for internal apps.
    Simplicity and maintainability favored.
     

Alternatives 

    Traefik or Nginx Proxy Manager: viable but not chosen due to higher complexity or feature fit.
    Direct service exposure: rejected; removes central policy and TLS consistency.
     

Consequences 

    Centralized TLS and routing, simple certificate management.
    One reverse proxy becomes the single entry point; monitor carefully.
