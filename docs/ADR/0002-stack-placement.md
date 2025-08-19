ADR-0002: Stack Placement 

Decision 

    Utilities stack (reverse proxy, dashboard, lifecycle tools) runs on a Services VM.
    AI/dev stack runs on a dedicated compute VM.
    Future stacks (media, downloads) are separated for resource and fault isolation.
     

Context 

    Separation helps with resource contention, upgrades, and blast radius reduction.
     

Alternatives 

    Single host for all apps: simpler but increases operational risk.
    Full Kubernetes: overkill for current scope and complexity targets.
     

Consequences 

    Clear fault domains and ownership boundaries.
    Requires internal DNS and reverse proxy routing to span hosts.
