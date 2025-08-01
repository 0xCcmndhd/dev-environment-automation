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
ensure_docker() {
    # --- Step 1: Check if Docker is installed ---
    if ! command -v docker &> /dev/null; then
        info "Docker is not found. Starting installation..."
        
        # Add the repository and install Docker packages
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
              sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        success "Docker Engine installed successfully."
    else
        info "Docker is already installed."
    fi

# ... in the ensure_docker function ...
    # --- Step 2: MANDATORY Check for Docker group membership ---
    if ! groups | grep -q '\bdocker\b'; then
        info "Adding current user to the 'docker' group for passwordless access..."
        CURRENT_USER=${SUDO_USER:-$USER}
        sudo usermod -aG docker "$CURRENT_USER"
        
        # Now, construct the multi-line message as a single variable
        # The -e interprets the \n as newlines
        MESSAGE_BODY="User '$CURRENT_USER' has been added to the 'docker' group."
        MESSAGE_INSTRUCTIONS="\n\n!!! IMPORTANT: You must log out and log back in for this change to take effect.\n!!! Please log out, SSH back in, and run this script again to continue."
        
        # Use a separate info call for clarity
        info "$MESSAGE_BODY"
        
        # Exit with the error and the full instructions
        error "$MESSAGE_INSTRUCTIONS"
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
    
    if [ ! -f "$CONFIG_PATH" ]; then
        if [ ! -f "$TEMPLATE_PATH" ]; then
            error "Glance config template not found at '$TEMPLATE_PATH'!"
            return 1
        fi
        
        info "  -> glance.yml not found. Generating from template..."
        mkdir -p "$(dirname "$CONFIG_PATH")"
        
        # Source the .env file to load variables, then use envsubst
        set -a
        # shellcheck source=.env
        source .env
        set +a
        envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
        success "   -> glance.yml created at $CONFIG_PATH"
    else
        warn "  -> Existing glance.yml found. Skipping generation."
    fi
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
    read -p "Ready to pull images and start the containers? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Pulling latest images..."
        docker compose pull
        info "Starting Docker containers in detached mode..."
        docker compose up -d
        success "Stack has been deployed!"
    else
        info "Deployment aborted. You can start the stack later with 'docker compose up -d'."
    fi
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
                by 0xCcmndhd (Your Name)
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
    echo ""
    echo "  q) Quit"
    echo ""
    read -p "Enter your choice: " stack_choice

    case "$stack_choice" in
        1) manage_stack "utilities" ;;
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

            # Step 1: Configure the .env file FIRST.
            configure_env_file_if_needed

            # Step 2: Generate ALL necessary config files.
            info "Generating configuration files for '$STACK_NAME' stack..."
            if [ "$STACK_NAME" == "utilities" ]; then
                generate_utilities_compose
                generate_caddyfile
                generate_glance_config # <-- This will now be found
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
            configure_env_file_if_needed
            if [ "$STACK_NAME" == "utilities" ]; then
                generate_utilities_compose
                generate_caddyfile
                generate_glance_config
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
