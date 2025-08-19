ADR-0004: Proxmox VM Automation 

Decision 

    Use Proxmox CLI (qm) with cloud-init to provision and update VMs idempotently from a declarative inventory file.
     

Interface (proposed) 

    Inventory file (not committed) at proxmox/vms.yml:
        connection: host, user, auth method (env vars or SSH key)
        vms: name, id, cpu, memory, disk, bridge, cloud-init user, ssh key, tags
         
    Command:
        ./proxmox/provision.sh apply -f proxmox/vms.yml
        ./proxmox/provision.sh delete -f proxmox/vms.yml --name utilities
         
     

Why CLI-first 

    Few dependencies, easy to audit, aligns with repo’s shell-first approach.
     

Alternatives 

    Proxmox API libraries or Terraform: viable, but more moving parts for this phase.
     

Consequences 

    Simple, scriptable workflows and reproducible VM definitions.
    Requires cloud-init images and secure key distribution.
