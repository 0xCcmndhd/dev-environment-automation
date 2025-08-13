#!/bin/bash
#
# Homelab Docker Deployment Script
# An interactive script to securely deploy and manage containerized service stacks.

# --- Safety First: Exit on any error ---
set -e

# --- Logging Functions ---
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }

# ==============================================================================
# GLOBAL PATH & CONFIGURATION VARIABLES
# These are set once to ensure paths are always correct.
# ==============================================================================
# The absolute path to the directory where this script is located.
readonly SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# The path to the templates directory, relative to the script's location.
readonly TEMPLATES_DIR="$SCRIPT_DIR/templates"
# The parent directory where all Docker Stacks will be deployed.
readonly DOCKER_BASE_DIR="$HOME/docker"

# ==============================================================================
# PREREQUISITE: DOCKER INSTALLATION & PERMISSIONS
# ==============================================================================
# ==============================================================================
# PREREQUISITE: DOCKER INSTALLATION & PERMISSIONS
# ==============================================================================
ensure_docker() {
    # --- Step 1: Check if Docker is installed ---
    if ! command -v docker &> /dev/null; then
        info "Docker is not found. Attempting installation for your OS..."
        if command -v dnf &> /dev/null; then
            # --- Fedora/Nobara/RHEL Installation ---
            info "DNF package manager detected (Fedora/Nobara)."
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        elif command -v apt-get &> /dev/null; then
            # --- Debian/Ubuntu Installation ---
            info "APT package manager detected (Debian/Ubuntu)."
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl
            sudo install -m 0755 -d /etc/apt/keyrings
            sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
            sudo chmod a+r /etc/apt/keyrings/docker.asc
            # Note: The UBUNTU_CODENAME variable is specific to Ubuntu.
            # This logic needs to be robust for other Debian-based distros if needed.
            . /etc/os-release
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
                  ${VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        else
            error "Unsupported package manager. Please install Docker and Docker Compose manually."
        fi

        # --- Post-installation steps for all OSes ---
        info "Enabling and starting the Docker service..."
        sudo systemctl start docker
        sudo systemctl enable docker
        success "Docker Engine installed successfully."
    else
        info "Docker is already installed."
    fi

    # --- Step 2: MANDATORY Check for Docker group membership ---
    # This part is universal and doesn't need to change.
    if ! groups | grep -q '\bdocker\b'; then
        info "Adding current user to the 'docker' group for passwordless access..."
        # This handles both cases where the script is run with or without sudo
        CURRENT_USER=${SUDO_USER:-$USER}
        sudo usermod -aG docker "$CURRENT_USER"
        
        MESSAGE_BODY="User '$CURRENT_USER' has been added to the 'docker' group."
        MESSAGE_INSTRUCTIONS="\n\n!!! IMPORTANT: You MUST log out and log back in for this change to take effect.\n!!! Please log out, SSH back in, and run this script again to continue."
        
        info "$MESSAGE_BODY"
        error "$MESSAGE_INSTRUCTIONS" # Exits the script
    else
        info "User has correct Docker permissions."
    fi
}
# ==============================================================================
# INDIVIDUAL SERVICE DEFINITIONS
# These are helper functions that append a single service to the compose file.
# ==============================================================================

# Appends the Watchtower service block to docker-compose.yml
add_watchtower_service() {
    info "  -> Adding Watchtower service..."
    cat >> docker-compose.yml << 'EOF'

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ=${TZ}
      # Schedule to run every morning at 4 AM.
      - WATCHTOWER_SCHEDULE=0 0 4 * * *
      # Automatically clean up old, unused images after an update.
      - WATCHTOWER_CLEANUP=true
    command: --include-stopped
EOF
}

# Creates the Caddyfile from a template, intentionally overwriting the old one.
generate_caddyfile() {
    # Use the reliable global variable for the template path
    local TEMPLATE_PATH="$TEMPLATES_DIR/Caddyfile.template"
    local CONFIG_PATH="./caddy/Caddyfile"
    
    if [ ! -f "$TEMPLATE_PATH" ]; then
        error "Caddyfile template not found at '$TEMPLATE_PATH'!"
        return 1
    fi
    
    info "  -> Generating Caddyfile from template..."
    # Ensure the target directory exists
    mkdir -p "$(dirname "$CONFIG_PATH")"

    # Backup the old Caddyfile before overwriting, just in case.
    if [ -f "$CONFIG_PATH" ]; then
        mv "$CONFIG_PATH" "${CONFIG_PATH}.bak"
    fi
    
    # Source the .env file to load variables, then use envsubst
    set -a
    # shellcheck source=.env
    source .env
    set +a
    envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
    
    success "   -> Caddyfile created/updated at $CONFIG_PATH"
}

# Appends the Caddy service block to docker-compose.yml
add_caddy_service() {
    info "  -> Adding Caddy service..."
    cat >> docker-compose.yml << 'EOF'

  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile
      - ./caddy/data:/data
      - ./caddy/config:/config
EOF
}

# Appends the Glance service block to docker-compose.yml
add_glance_service() {
    info "  -> Adding Glance dashboard service..."
    cat >> docker-compose.yml << 'EOF'

  glance:
    image: glanceapp/glance:latest
    container_name: glance
    restart: unless-stopped
    # Note: We do not expose ports directly. Caddy will handle access.
    # ports:
    #   - "3030:8080"
    volumes:
      - ./glance/config:/app/config
      - ./glance/assets:/app/assets
      # We need the Docker socket to use the server-stats and containers widget
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - PUID=${PUID} # Add PUID/PGID for good practice
      - PGID=${PGID}
      - TZ=${TZ}
EOF
}

# Creates the glance.yml config from a template
generate_glance_config() {
    # Use the reliable global variable for the template path
    local TEMPLATE_PATH="$TEMPLATES_DIR/glance.yml.template"
    local CONFIG_PATH="./glance/config/glance.yml"

    if [ ! -f "$TEMPLATE_PATH" ]; then
        error "Glance config template not found at '$TEMPLATE_PATH'!"
        return 1
    fi

    info "  -> Generating glance.yml from template..."
    mkdir -p "$(dirname "$CONFIG_PATH")"

    # Backup the old file before overwriting, if it exists.
    if [ -f "$CONFIG_PATH" ]; then
        mv "$CONFIG_PATH" "${CONFIG_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    # Source the .env file to load variables, then use envsubst
    set -a
    # shellcheck source=.env
    source .env
    set +a
    envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
    success "   -> glance.yml created/updated at $CONFIG_PATH"
}

# Generates minimal, working Authelia config and users database if missing
generate_authelia_configs() {
    local CONFIG_DIR="./authelia/config"
    mkdir -p "$CONFIG_DIR"

    # Helper to generate secure random base64 if missing
    generate_random_b64() {
        if command -v openssl >/dev/null 2>&1; then
            openssl rand -base64 32
        else
            head -c 32 /dev/urandom | base64
        fi
    }

    # 1) users_database.yml
    local USERS_DB="${CONFIG_DIR}/users_database.yml"
    if [ ! -f "$USERS_DB" ]; then
        warn "Authelia users_database.yml not found. Creating a minimal one for user 'admin'."
        local ADMIN_PASS
        read -p "Enter password for Authelia admin user 'admin': " -s ADMIN_PASS
        echo
        if [ -z "$ADMIN_PASS" ]; then
            error "Empty password provided for Authelia admin. Aborting users database creation."
            return 1
        fi
        info "Hashing admin password with Authelia (argon2id)..."
        local HASH
        HASH=$(docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "$ADMIN_PASS" --variant argon2id --iterations 3 --parallelism 4 --memory 65536 | sed 's/^Digest: //' | grep -Eo '^\$argon2(id|i)\$.*' | tail -n1)
        if [ -z "$HASH" ]; then
            error "Failed to generate password hash via Authelia container."
            return 1
        fi
        cat > "$USERS_DB" << EOF
users:
  admin:
    displayname: Admin
    email: admin@example.com
    password: "${HASH}"
EOF
        success "Created $USERS_DB"
        unset ADMIN_PASS HASH
    else
        info "Existing Authelia users_database.yml found. Skipping."
    fi

    # 2) configuration.yml
    local CONFIG_YML="${CONFIG_DIR}/configuration.yml"
    if [ ! -f "$CONFIG_YML" ]; then
        warn "Authelia configuration.yml not found. Creating a minimal working configuration."
        local SESSION_SECRET
        local STORAGE_KEY
        local RESET_JWT
        SESSION_SECRET=$(generate_random_b64)
        STORAGE_KEY=$(generate_random_b64)
        RESET_JWT=$(generate_random_b64)
        local DOMAIN="${LOCAL_DOMAIN:-lan}"

        cat > "$CONFIG_YML" << EOF
server:
  address: "0.0.0.0:9091"

log:
  level: info

theme: dark
default_redirection_url: https://glance.${DOMAIN}

authentication_backend:
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id
      iterations: 3
      parallelism: 4
      memory: 65536

session:
  cookies:
    - name: authelia_session
      domain: ${DOMAIN}
      same_site: lax
      expiration: 1h
      inactivity: 5m
      remember_me: 1M
      secret: "${SESSION_SECRET}"

storage:
  encryption_key: "${STORAGE_KEY}"
  local:
    path: /config/db.sqlite3

notifier:
  filesystem:
    filename: /config/notification.txt

access_control:
  default_policy: one_factor
  rules:
    - domain: ["glance.${DOMAIN}", "code.${DOMAIN}", "uptime.${DOMAIN}", "vaultwarden.${DOMAIN}"]
      policy: one_factor

totp:
  issuer: "${DOMAIN}"
  period: 30
  skew: 1

identity_validation:
  reset_password:
    jwt_secret: "${RESET_JWT}"
EOF
        success "Created $CONFIG_YML"
        unset SESSION_SECRET STORAGE_KEY RESET_JWT DOMAIN
    else
        info "Existing Authelia configuration.yml found. Skipping."
    fi

    # Ensure ownership and reasonable permissions
    local CURRENT_UID CURRENT_GID
    CURRENT_UID=$(id -u)
    CURRENT_GID=$(id -g)
    sudo chown -R "$CURRENT_UID":"$CURRENT_GID" "$CONFIG_DIR"
    chmod 644 "$CONFIG_DIR"/* || true
    success "Authelia config files are ready."
}
 
# New services for Utilities stack
add_redis_service() {
    info "  -> Adding Redis service..."
    cat >> docker-compose.yml << 'EOF'

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - ./redis/data:/data
EOF
}

add_authelia_service() {
    info "  -> Adding Authelia service..."
    cat >> docker-compose.yml << 'EOF'

  authelia:
    image: authelia/authelia:latest
    container_name: authelia
    restart: unless-stopped
    command: --config /config/configuration.yml
    depends_on:
      - redis
    volumes:
      - ./authelia/config:/config
    environment:
      - TZ=${TZ}
EOF
}

add_uptime_kuma_service() {
    info "  -> Adding Uptime Kuma service..."
    cat >> docker-compose.yml << 'EOF'

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    volumes:
      - ./uptime-kuma/data:/app/data
    environment:
      - TZ=${TZ}
EOF
}

add_vaultwarden_service() {
    info "  -> Adding Vaultwarden service..."
    cat >> docker-compose.yml << 'EOF'

  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    environment:
      - TZ=${TZ}
      - WEBSOCKET_ENABLED=true
    volumes:
      - ./vaultwarden/data:/data
EOF
}

# Appends the code-server service block to docker-compose.yml (optional)
add_code_server_service() {
    info "  -> Adding code-server service..."
    cat >> docker-compose.yml << 'EOF'

  code:
    image: codercom/code-server:latest
    container_name: code
    restart: unless-stopped
    # No ports exposed; Caddy will reverse proxy internally
    environment:
      - TZ=${TZ}
      - PASSWORD=${CODE_PASSWORD}
    volumes:
      - ./code/config:/home/coder/.config
      - ./code/projects:/home/coder/project
EOF
}

generate_ai_compose() {
    # Use the reliable global variable for the template path
    local TEMPLATE_PATH="$TEMPLATES_DIR/ai-compose.yml.template"
    local CONFIG_PATH="./docker-compose.yml"
    
    if [ ! -f "$TEMPLATE_PATH" ]; then
        error "AI Compose template not found at '$TEMPLATE_PATH'!"
        return 1
    fi

    info "  -> Generating AI stack docker-compose.yml from template..."

    # Source the .env file to load variables, then use envsubst
    set -a
    # shellcheck source=.env
    source .env
    set +a
    
    envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
    success "   -> AI docker-compose.yml created at $CONFIG_PATH"
}

# ==============================================================================
# MAIN COMPOSE FILE GENERATOR
# This function orchestrates the creation of the final docker-compose.yml.
# ==============================================================================
generate_utilities_compose() {
    # Start with a clean slate by overwriting the file with the header.
    info "Creating new docker-compose.yml..."
    echo "services:" > docker-compose.yml

    # Call the helper function for each service we want in this stack.
    add_watchtower_service
    add_caddy_service # Example of how we'll add more later
    add_glance_service # Example
    add_redis_service
    add_authelia_service
    add_uptime_kuma_service
    add_vaultwarden_service

    # Optionally include code-server service
    read -p "Include code-server (VS Code in browser)? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        add_code_server_service
    fi

    # After adding all services, generate configs that depend on them
    generate_caddyfile

    success "docker-compose.yml generated successfully."
}

configure_env_file_if_needed() {
    if [ -f ".env" ]; then
        warn "An existing .env file was found."
        read -p "Do you want to re-configure and a new one? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Backup the old file before creating a new one
            mv .env .env.bak.$(date +%Y%m%d-%H%M%S)
            info "Backed up existing .env file."
            configure_env_file
        else
            info "Using existing .env file."
        fi
    else
        # No .env file exists, so we must create one.
        configure_env_file
    fi
}

prepare_service_directories() {
    # --- NEW, CRUCIAL FUNCTION ---
    # This prepares directories and fixes permissions BEFORE any configs are written.
    local STACK_NAME="$1"
    shift
    local SERVICES=("$@")

    info "Preparing and validating configuration directories for '$STACK_NAME'..."
    
    local CURRENT_UID
    CURRENT_UID=$(id -u)
    local CURRENT_GID
    CURRENT_GID=$(id -g)

    for SERVICE in "${SERVICES[@]}"; do
        local BASE_DIR="./${SERVICE}"
        local CONFIG_DIR="${BASE_DIR}/config"
        info "  -> Ensuring directory exists and has correct permissions: $CONFIG_DIR"
        mkdir -p "$CONFIG_DIR"

        # Create additional data dirs used by bind mounts for specific services
        case "$SERVICE" in
            caddy) mkdir -p "${BASE_DIR}/data" ;;
            glance) mkdir -p "${BASE_DIR}/assets" ;;
            code) mkdir -p "${BASE_DIR}/projects" ;;
            authelia) ;;
            uptime-kuma) mkdir -p "${BASE_DIR}/data" ;;
            vaultwarden) mkdir -p "${BASE_DIR}/data" ;;
            redis) mkdir -p "${BASE_DIR}/data" ;;
        esac

        sudo chown -R "$CURRENT_UID":"$CURRENT_GID" "$BASE_DIR"
    done
    success "All service directories prepared."
}

configure_env_file() {
    warn "Configuring environment variables for all stacks..."
    echo "This will create a secure '.env' file to store your settings."
    
    # --- General ---
    warn "---[ General Settings ]---"
    read -p "Enter your TimeZone (e.g., America/New_York): " -i "America/New_York" -e TZ
    read -p "Enter your primary local domain (e.g., lan, home.arpa): " -i "lan" -e LOCAL_DOMAIN
    read -p "Enter your city for the weather widget: " -i "Philadelphia" -e GLANCE_WEATHER_LOCATION

    # --- User/Group IDs ---
    warn "---[ User and Group IDs ]---"
    read -p "Enter the User ID (PUID) for containers: " -i "1000" -e PUID
    read -p "Enter the Group ID (PGID) for containers: " -i "1000" -e PGID

    # --- Infrastructure IPs ---
    warn "---[ Infrastructure IP Addresses & Secrets ]---"
    read -p "Enter the IP address of your Proxmox host: " -e PROXMOX_IP
    read -p "Enter the IP address of your UniFi Controller: " -e UNIFI_IP
    read -p "Enter the IP address of your TrueNAS server: " -e TRUENAS_IP
    read -p "Enter the IP of your PRIMARY Pi-hole (Proxmox CT): " -e PIHOLE_PRIMARY_IP
    read -p "Enter the IP of your SECONDARY Pi-hole (Raspberry Pi): " -e PIHOLE_SECONDARY_IP
    read -p "Enter the Web UI password for Pi-hole: " -s PIHOLE_PASSWORD
    echo "" # Add a newline after the sensitive password input
    
    # --- Server IPs ---
    warn "---[ Service VM IP Addresses ]---"
    read -p "Enter the IP of your AI Server VM: " -e AI_SERVER_IP
    read -p "Enter the IP of your Media Server VM: " -e MEDIA_SERVER_IP
    read -p "Enter the IP of your Downloads Server VM: " -e DOWNLOADS_SERVER_IP
    # Add more prompts here for Media, Downloads VMs as you build those stacks

    info "Writing all settings to .env file..."
    cat > .env << EOF
# --- General Settings ---
TZ=${TZ}
LOCAL_DOMAIN=${LOCAL_DOMAIN}
PUID=${PUID}
PGID=${PGID}

# --- Glance Widget Settings ---
GLANCE_WEATHER_LOCATION=${GLANCE_WEATHER_LOCATION}

# --- Infrastructure IPs & Secrets ---
PROXMOX_IP=${PROXMOX_IP}
UNIFI_IP=${UNIFI_IP}
TRUENAS_IP=${TRUENAS_IP}
PIHOLE_PRIMARY_IP=${PIHOLE_PRIMARY_IP}
PIHOLE_SECONDARY_IP=${PIHOLE_SECONDARY_IP}
PIHOLE_PASSWORD=${PIHOLE_PASSWORD}

# --- Service VM IPs ---
AI_SERVER_IP=${AI_SERVER_IP}
MEDIA_SERVER_IP=${MEDIA_SERVER_IP}
DOWNLOADS_SERVER_IP=${DOWNLOADS_SERVER_IP}
EOF
    success ".env file created securely."
}

deploy_stack() {
    info "The following services are configured for deployment:"
    docker compose -f docker-compose.yml config --services | sed 's/^/    - /'
    echo ""
    read -p "Ready to pull updated images and deploy/update the stack? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment aborted."
        return
    fi
    
    info "Pulling the latest versions of all defined images..."
    # 'pull' will download any new versions of images like 'caddy:latest'
    docker compose pull

    info "Starting or updating containers in detached mode..."
    # 'up -d' will automatically stop and re-create any containers whose
    # configuration or image has changed. It leaves unchanged containers running.
    docker compose up -d --remove-orphans

    success "Stack has been successfully deployed/updated!"
}

cleanup_stack() {
    local STACK_NAME="$1"
    local DEPLOY_PATH="$HOME/docker/$STACK_NAME"

    if [ ! -d "$DEPLOY_PATH" ]; then
        warn "Directory for '$STACK_NAME' stack not found. Nothing to clean up."
        return
    fi
    cd "$DEPLOY_PATH" || exit

    warn "You are about to permanently remove the '$STACK_NAME' stack."
    warn "Configuration files on disk will NOT be deleted."
    read -p "Are you absolutely sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled."
        return
    fi

    info "Stopping and removing containers, networks, and volumes..."
    docker compose down -v

    success "Stack '$STACK_NAME' has been successfully torn down."
}


# ==============================================================================
# MAIN MENU
# ==============================================================================
main_menu() {
    # --- Display the professional header ---
    clear
    cat << "EOF"
=====================================================================
            Homelab Service Deployment Manager
                      by 0xCcmndhd
---------------------------------------------------------------------
 This script automates the deployment of containerized service stacks.
 It is designed to be idempotent and secure. For more information,
 see the project README.
=====================================================================
Last Docker Documentation Review: 2024-07-31
---------------------------------------------------------------------
EOF
    echo ""
    echo "Select a service stack to manage:"
    echo "  1) Utilities (Caddy, Watchtower, Glance, etc.)"
    echo "  2) AI (Open Webui, Sillytavern)"
    echo ""
    echo "  q) Quit"
    echo ""
    read -p "Enter your choice: " stack_choice

    case "$stack_choice" in
        1) manage_stack "utilities" ;;
        2) manage_stack "ai" ;;
        q) exit 0 ;;
        *) error "Invalid choice. Please try again." ;;
    esac
}

manage_stack() {
    local STACK_NAME="$1"
    local DEPLOY_PATH="$HOME/docker/$STACK_NAME"
    
    clear
    echo "Managing stack: $STACK_NAME"
    echo "--------------------------"
    echo "  1) Deploy or Update Stack"
    echo "  2) Generate/Update Config Files Only (No Restart)"
    echo "  3) Clean Up / Uninstall Stack"
    echo "  b) Back to Main Menu"
    echo ""
    read -p "Enter your action: " action_choice

    case "$action_choice" in
        1)
            # --- DEPLOYMENT LOGIC ---
            info "Preparing to deploy the '$STACK_NAME' stack..."
            mkdir -p "$DEPLOY_PATH"
            cd "$DEPLOY_PATH" || exit
            
            # Step 1: Prepare directories with correct permissions FIRST
            # This is the line that was missing a function to call.
            prepare_service_directories "$STACK_NAME" caddy glance watchtower code authelia redis uptime-kuma vaultwarden

            # Step 1: Configure the .env file FIRST.
            configure_env_file_if_needed

            # Step 2: Generate ALL necessary config files.
            info "Generating configuration files for '$STACK_NAME' stack..."
            if [ "$STACK_NAME" == "utilities" ]; then
                generate_utilities_compose
                generate_glance_config # <-- This will now be found
                generate_authelia_configs
            elif [ "$STACK_NAME" == "ai" ]; then # <-- ADD THIS BLOCK
            generate_ai_compose
            else
                error "Config file generator for stack '$STACK_NAME' is not implemented yet."
            fi
            
            # Step 3: Now that all configs are in place, deploy the stack.
            deploy_stack
            ;;
        2) 
            # --- NEW: CONFIG ONLY MODE ---
            info "Generating config files for '$STACK_NAME' without deploying..."
            cd "$DEPLOY_PATH" || mkdir -p "$DEPLOY_PATH" && cd "$DEPLOY_PATH"
              
            prepare_service_directories "$STACK_NAME" caddy glance watchtower code authelia redis uptime-kuma vaultwarden
            configure_env_file_if_needed
            if [ "$STACK_NAME" == "utilities" ]; then
                generate_utilities_compose
                generate_glance_config
                generate_authelia_configs
            elif [ "$STACK_NAME" == "ai" ]; then # <-- ADD THIS BLOCK
            generate_ai_compose
            fi
            success "All configuration files have been generated in '$DEPLOY_PATH'."
            ;;
        3)
            # --- CLEANUP LOGIC ---
            cleanup_stack "$STACK_NAME"
            ;;
        b)
            main_menu
            ;;
        *)
            error "Invalid action."
            ;;
    esac
}

# --- Script Entry Point ---
# We run the Docker prerequisite check before showing the main menu.
ensure_docker
main_menu
