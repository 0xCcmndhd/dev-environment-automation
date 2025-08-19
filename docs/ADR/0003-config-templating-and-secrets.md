ADR-0003: Config Templating and Secrets 

Decision 

    Store human-readable templates in version control.
    Generate runtime configs with envsubst from a local .env (not committed).
    Use .env.example to document required variables.
     

Context 

    Avoid committing secrets; keep configuration portable and reviewable.
     

Alternatives 

    Commit plain configs: rejected (secrets risk).
    Complex secret managers: not required for current scale; may revisit later.
     

Consequences 

    Straightforward generation and review.
    Developers must manage local .env files and keep them out of VCS.
