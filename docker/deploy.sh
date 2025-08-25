#!/bin/bash
#
# Homelab Docker Deployment Script
# An interactive script to securely deploy and manage containerized service stacks.

# --- Safety First: Exit on any error ---
set -euo pipefail

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
SCRIPT_DIR_TMP="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
readonly SCRIPT_DIR="${SCRIPT_DIR_TMP}"
# The path to the templates directory, relative to the script's location.
readonly TEMPLATES_DIR="$SCRIPT_DIR/templates"
# The parent directory where all Docker Stacks will be deployed (unused; remove or export if needed).
#readonly DOCKER_BASE_DIR="$HOME/docker"

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
            # shellcheck source=/etc/os-release
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
    # shellcheck disable=SC1091
    source .env
    set +a
    envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
    
    success "   -> Caddyfile created/updated at $CONFIG_PATH"
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
    # shellcheck disable=SC1091
    source .env
    set +a
    envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
    success "   -> glance.yml created/updated at $CONFIG_PATH"
}

# Generates minimal, working Authelia config and users database if missing
generate_authelia_from_template() {
    local CONFIG_DIR="./authelia/config"
    local TEMPLATE_PATH="$TEMPLATES_DIR/authelia/configuration.yml.template"
    # Host and container paths for apps.yml
    local APPS_YML_HOST="$TEMPLATES_DIR/authelia/apps.yml"
    local APPS_YML_CONT="/templates/authelia/apps.yml"
#    local APPS_YML="$TEMPLATES_DIR/authelia/apps.yml"
    local OUT_YML="${CONFIG_DIR}/configuration.yml"
    local USERS_DB="${CONFIG_DIR}/users_database.yml"

    mkdir -p "$CONFIG_DIR"

    # Helper: robust backup with sudo fallback
    backup_file() {
      local src="$1"; local ts
      ts="$(date +%Y%m%d-%H%M%S)"
      local dst="${src}.bak.${ts}"
      [ -f "$src" ] || return 0
      if mv "$src" "$dst"; then
        return 0
      fi
      warn "mv failed for $src; trying sudo mv..."
      if sudo mv "$src" "$dst"; then
        return 0
      fi
      warn "sudo mv failed; trying sudo cp -a + rm..."
      sudo cp -a "$src" "$dst" && sudo rm -f "$src" || error "Failed to backup $src"
    }

    # Ensure yq via Docker (no host dep)
    run_yq() {
        docker run --rm -i \
          -e DOMAIN="${DOMAIN:-${LOCAL_DOMAIN:-lan}}" \
          -v "$PWD":/work -w /work \
          -v "$TEMPLATES_DIR":/templates:ro \
          ghcr.io/mikefarah/yq:latest e "$@"
    }
    [ -f "$APPS_YML_HOST" ] || error "Missing $APPS_YML_HOST"
    # 1) Minimal users DB if missing
    if [ ! -f "$USERS_DB" ]; then
        warn "Authelia users_database.yml not found. Creating a minimal one for user 'admin'."
        local ADMIN_PASS
        read -r -s -p "Enter password for Authelia admin user 'admin': " ADMIN_PASS
        echo
        if [ -z "$ADMIN_PASS" ]; then
            error "Empty password provided for Authelia admin."
        fi
        info "Hashing admin password (argon2id)..."
        local HASH
        # shellcheck disable=SC2016
        HASH=$(docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "$ADMIN_PASS" --variant argon2id --iterations 3 --parallelism 4 --memory 65536 | sed 's/^Digest: //' | grep -E '^\$argon2(id|i)\$' | tail -n1)
        cat > "$USERS_DB" <<EOF
users:
  admin:
    displayname: Admin
    email: admin@example.com
    password: "${HASH}"
EOF
        unset ADMIN_PASS HASH
        success "Created $USERS_DB"
    else
        info "Existing users_database.yml found."
    fi

    # 2) Read domain from apps.yml (authoritative)
    if [ ! -f "$APPS_YML_HOST" ]; then
        error "Missing $APPS_YML_HOST"
        return 1
    fi
    local DOMAIN
    DOMAIN=$(run_yq -r '.domain' "$APPS_YML_CONT")
    [ -z "$DOMAIN" ] && DOMAIN="${LOCAL_DOMAIN:-lan}"

    # 3) Preserve secrets if config exists
    local SESSION_SECRET="" STORAGE_KEY="" RESET_JWT=""
    if [ -f "$OUT_YML" ]; then
        info "Preserving existing Authelia secrets."
        # Make sure we can read the file even if owned by root
        if [ ! -r "$OUT_YML" ]; then
          sudo chmod a+r "$OUT_YML" 2>/dev/null || true
        fi
        SESSION_SECRET=$(awk '$1=="session:"{ins=1;next} ins && $1=="secret:"{print $2; ins=0}' "$OUT_YML")
        STORAGE_KEY=$(awk '$1=="storage:"{ins=1;next} ins && $1=="encryption_key:"{print $2; ins=0}' "$OUT_YML")
        RESET_JWT=$(awk '$1=="identity_validation:"{ins=1;next} ins && $1=="jwt_secret:"{print $2; ins=0}' "$OUT_YML")
        # Ensure directory is writable, then backup with fallback
        sudo chown -R "$(id -u)":"$(id -g)" "$CONFIG_DIR" 2>/dev/null || true
        backup_file "$OUT_YML"
    fi
    # Fallback secrets if any missing
    gen_b64() { openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64; }
    [ -z "${SESSION_SECRET:-}" ] && SESSION_SECRET=$(gen_b64)
    [ -z "${STORAGE_KEY:-}" ] && STORAGE_KEY=$(gen_b64)
    [ -z "${RESET_JWT:-}" ] && RESET_JWT=$(gen_b64)

    # 4) Build app names list then compose YAML in bash (robust with -euo pipefail)
    local APP_NAMES
    APP_NAMES=$(run_yq -r '.apps[] | select((.sso // false) or (.cookie // false)) | .name' "$APPS_YML_CONT")
    if [ -z "${APP_NAMES:-}" ]; then
        error "No apps matched in apps.yml to build Authelia cookies/domains."
    fi

    # 4a) Build the cookies YAML block
    local COOKIES=""
    while IFS= read -r _app; do
      [ -z "$_app" ] && continue
      COOKIES+="    - name: authelia_${_app}\n"
      COOKIES+="      domain: ${_app}.${DOMAIN}\n"
      COOKIES+="      authelia_url: https://auth.${DOMAIN}\n"
      COOKIES+="      default_redirection_url: https://${_app}.${DOMAIN}\n"
      COOKIES+="      same_site: lax\n"
      COOKIES+="      expiration: 1h\n"
      COOKIES+="      inactivity: 5m\n"
      COOKIES+="      remember_me: 1M\n"
    done <<< "$APP_NAMES"

    # 4b) Build the access_control domain list YAML block
    local DOMAINS=""
    while IFS= read -r _app; do
      [ -z "$_app" ] && continue
      DOMAINS+="      - ${_app}.${DOMAIN}\n"
    done <<< "$APP_NAMES"

    # 5) Render from template, injecting via temp files
    if [ ! -f "$TEMPLATE_PATH" ]; then
        error "Missing template $TEMPLATE_PATH"
        return 1
    fi
    mkdir -p "$(dirname "$OUT_YML")"
    local _tmp_c _tmp_d
    _tmp_c="$(mktemp)"; _tmp_d="$(mktemp)"
    printf '%b' "$COOKIES" >"$_tmp_c"
    printf '%b' "$DOMAINS" >"$_tmp_d"
    sed \
      -e "s|\${SESSION_SECRET}|${SESSION_SECRET}|g" \
      -e "s|\${STORAGE_KEY}|${STORAGE_KEY}|g" \
      -e "s|\${RESET_JWT}|${RESET_JWT}|g" \
      -e "s|\${LOCAL_DOMAIN}|${DOMAIN}|g" \
      -e "/__COOKIES__/{
            r $_tmp_c
            d
          }" \
      -e "/__ACCESS_RULE_DOMAINS__/{
            r $_tmp_d
            d
          }" \
      "$TEMPLATE_PATH" > "$OUT_YML"
    rm -f "$_tmp_c" "$_tmp_d"

    [ -z "${COOKIES:-}" ] && error "Cookies list generation is empty; check templates/authelia/apps.yml"
    [ -z "${DOMAINS:-}" ] && error "Domain list generation is empty; check templates/authelia/apps.yml"

    # 7) Permissions
    local UID_ GID_
    UID_=$(id -u); GID_=$(id -g)
    sudo chown -R "$UID_":"$GID_" "$CONFIG_DIR"
    chmod 640 "$OUT_YML" "$USERS_DB" 2>/dev/null || true

    success "Authelia config generated at $OUT_YML"
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
    # shellcheck disable=SC1091
    source .env
    set +a
    
    envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
    success "   -> AI docker-compose.yml created at $CONFIG_PATH"
}

write_llamacpp_assets() {
    # Only write if llamacpp is in profiles
    if ! grep -E '^COMPOSE_PROFILES=' .env | grep -q 'llamacpp'; then
        return
    fi
    local BASE="./llamacpp"
    mkdir -p "$BASE/models"
    # Copy Dockerfile template
    if [ -f "$TEMPLATES_DIR/llamacpp.Dockerfile.template" ]; then
        cp "$TEMPLATES_DIR/llamacpp.Dockerfile.template" "$BASE/Dockerfile"
    fi
    # Copy model downloader
    if [ -f "$TEMPLATES_DIR/get_235b.py.template" ]; then
        cp "$TEMPLATES_DIR/get_235b.py.template" "$BASE/models/get_235b.py"
    fi
}

install_heavy_mode_script() {
    if ! grep -E '^COMPOSE_PROFILES=' .env | grep -q 'llamacpp'; then
        return
    fi
    local TARGET="./heavy-mode.sh"
    if [ -f "$TEMPLATES_DIR/heavy-mode.sh.template" ]; then
        cp "$TEMPLATES_DIR/heavy-mode.sh.template" "$TARGET"
        chmod +x "$TARGET"
    fi
}


# Return 0 if path is a mountpoint or within a mounted fs; 1 otherwise
is_mounted() {
  local path="$1"
  # findmnt -T works on paths with spaces; fall back to mountpoint -q
  if command -v findmnt >/dev/null 2>&1; then
    findmnt -T "$path" >/dev/null 2>&1
  else
    mountpoint -q "$path"
  fi
}

verify_host_path() {
  local path="$1"; local want_write="${2:-false}"
  if [ ! -d "$path" ]; then
    error "Required path not found: $path"
  fi
  if ! is_mounted "$path"; then
    warn "Path exists but is not a mounted filesystem: $path"
    warn "If this is a network share, check your fstab or automount config."
    read -p "Continue anyway? (y/N) " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] || error "Aborting; mount not present: $path"
  fi
  if [ "$want_write" = "true" ]; then
    local tmp="$path/.compose_write_test_$$"
    if ! ( set -e; touch "$tmp" && rm -f "$tmp" ); then
      error "Write test failed at $path. Fix permissions/ACLs or PUID/PGID."
    fi
  fi
}

verify_media_layout() {
  # Reads MEDIA_ROOT and DL_ROOT from .env
  set -a; source .env; set +a
  local mr="${MEDIA_ROOT:-/mnt/truenas/Media}"
  local dl="${DL_ROOT:-$mr/downloads}"

  info "Verifying media root: $mr"
  verify_host_path "$mr" false

  # Expected subfolders (adjust to your layout)
  local subs=("Videos" "Videos/Movies" "Videos/TV Shows" "Music" "Books" "downloads")
  local missing=()
  for s in "${subs[@]}"; do
    if [ ! -d "$mr/$s" ]; then
      missing+=("$mr/$s")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    warn "Missing expected subfolders:"
    printf '  - %s\n' "${missing[@]}"
    read -p "Create them now? (y/N) " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      for m in "${missing[@]}"; do mkdir -p "$m"; done
      success "Created missing subfolders."
    else
      warn "Continuing without creating missing folders."
    fi
  fi

  info "Verifying downloads path: $dl (write test)"
  verify_host_path "$dl" true

  # Optional: check PUID/PGID vs ownership hints
  if command -v stat >/dev/null 2>&1; then
    local owner_uid owner_gid
    owner_uid=$(stat -c '%u' "$dl" 2>/dev/null || echo "")
    owner_gid=$(stat -c '%g' "$dl" 2>/dev/null || echo "")
    if [ -n "$owner_uid" ] && [ -n "$PUID" ] && [ "$owner_uid" != "$PUID" ]; then
      warn "downloads owner uid=$owner_uid differs from PUID=$PUID; ensure ACLs/uid mapping."
    fi
    if [ -n "$owner_gid" ] && [ -n "$PGID" ] && [ "$owner_gid" != "$PGID" ]; then
      warn "downloads owner gid=$owner_gid differs from PGID=$PGID; ensure ACLs/gid mapping."
    fi
  fi
}

# ==============================================================================
# MAIN COMPOSE FILE GENERATOR
# This function orchestrates the creation of the final docker-compose.yml.
# ==============================================================================
generate_utilities_compose() {
    # New template-driven utilities compose
    local TEMPLATE_PATH="$TEMPLATES_DIR/utilities-compose.yml.template"
    local CONFIG_PATH="./docker-compose.yml"
    if [ ! -f "$TEMPLATE_PATH" ]; then
        error "Utilities Compose template not found at '$TEMPLATE_PATH'!"
        return 1
    fi
    info "  -> Generating Utilities stack docker-compose.yml from template..."
    set -a; # shellcheck disable=SC1091
    source .env; set +a
    envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
    generate_caddyfile
    success "   -> Utilities docker-compose.yml created at $CONFIG_PATH"
}

generate_media_compose() {
    local TEMPLATE_PATH="$TEMPLATES_DIR/media-compose.yml.template"
    local CONFIG_PATH="./docker-compose.yml"
    [ -f "$TEMPLATE_PATH" ] || error "Media Compose template not found at '$TEMPLATE_PATH'!"
    info "  -> Generating Media stack docker-compose.yml from template..."
    set -a; # shellcheck disable=SC1091
    source .env; set +a
    envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
    success "   -> Media docker-compose.yml created at $CONFIG_PATH"
}

generate_downloads_compose() {
    local TEMPLATE_PATH="$TEMPLATES_DIR/downloads-compose.yml.template"
    local CONFIG_PATH="./docker-compose.yml"
    [ -f "$TEMPLATE_PATH" ] || error "Downloads Compose template not found at '$TEMPLATE_PATH'!"
    info "  -> Generating Downloads stack docker-compose.yml from template..."
    set -a; # shellcheck disable=SC1091
    source .env; set +a
    envsubst < "$TEMPLATE_PATH" > "$CONFIG_PATH"
    success "   -> Downloads docker-compose.yml created at $CONFIG_PATH"
}

# --- .env helpers (idempotent, in-place editing) ---
ensure_env_file_present() {
  [ -f ".env" ] && return 0
  info "No .env found; creating an empty one."
  : > .env
}

get_env() {
  # prints value if KEY=VAL exists; empty otherwise
  local key="$1"
  grep -E "^${key}=" .env | sed -E "s/^${key}=//" | tail -n1
}

upsert_env() {
  # upsert KEY=VALUE (no quotes added; pass pre-quoted if needed)
  local key="$1" val="$2"
  if grep -qE "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${val}|" .env
  else
    echo "${key}=${val}" >> .env
  fi
}

prompt_env() {
  # prompt_env KEY "Prompt text" "fallback_default"
  local key="$1" prompt="$2" fallback="$3"
  local cur; cur="$(get_env "$key")"
  local def="${cur:-$fallback}"
  read -r -e -i "$def" -p "$prompt " val
  upsert_env "$key" "$val"
}

prompt_env_secret() {
  # prompt_env_secret KEY "Prompt text (leave blank to keep current)" required(true/false)
  local key="$1" prompt="$2" required="${3:-false}"
  local cur; cur="$(get_env "$key")"
  local val=""
  read -r -s -p "$prompt " val; echo
  if [ -z "$val" ]; then
    if [ "$required" = "true" ] && [ -z "$cur" ]; then
      error "A value is required for $key."
    fi
    [ -n "$cur" ] && return 0  # keep existing
  fi
  upsert_env "$key" "$val"
}

ensure_env_basics() {
  ensure_env_file_present
  warn "---[ General Settings ]---"
  prompt_env TZ "Timezone (e.g., America/New_York):" "America/New_York"
  prompt_env LOCAL_DOMAIN "Primary local domain (lan/home.arpa):" "lan"
  prompt_env GLANCE_WEATHER_LOCATION "City for weather widget:" "Philadelphia"

  warn "---[ User and Group IDs ]---"
  prompt_env PUID "PUID (container user id):" "1000"
  prompt_env PGID "PGID (container group id):" "1000"

  warn "---[ Infra IPs & DNS ]---"
  prompt_env PROXMOX_IP "Proxmox IP:" ""
  prompt_env UNIFI_IP "UniFi IP:" ""
  prompt_env TRUENAS_IP "TrueNAS IP:" ""
  prompt_env PIHOLE_PRIMARY_IP "Pi-hole PRIMARY IP:" ""
  prompt_env PIHOLE_SECONDARY_IP "Pi-hole SECONDARY IP:" ""
  prompt_env_secret PIHOLE_PASSWORD "Pi-hole Web UI password (leave blank to keep current):" false

  warn "---[ Service VM IPs ]---"
  prompt_env AI_SERVER_IP "AI Server VM IP:" ""
  prompt_env MEDIA_SERVER_IP "Media Server VM IP:" ""
  prompt_env DOWNLOADS_SERVER_IP "Downloads Server VM IP:" ""
}

ensure_env_utilities_extras() {
  warn "---[ Utilities extras ]---"
  prompt_env CODE_PASSWORD "code-server password:" "changeme"
  local _ld; _ld="$(get_env LOCAL_DOMAIN)"; _ld="${_ld:-lan}"
  prompt_env NTFY_BASE_URL "ntfy base URL:" "https://ntfy.${_ld}"
  prompt_env LIVESYNC_COUCHDB_USER "Obsidian LiveSync CouchDB user:" "obsidian"
  prompt_env_secret LIVESYNC_COUCHDB_PASSWORD "CouchDB password (leave blank to keep current):" false

  # Optional YOURLS
  read -p "Configure YOURLS now? (y/N) " -n 1 -r; echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    prompt_env YOURLS_SITE "YOURLS site URL:" "https://links.${_ld}"
    prompt_env YOURLS_USER "YOURLS admin user:" "admin"
    prompt_env_secret YOURLS_PASS "YOURLS admin password (leave blank to keep current):" false
    prompt_env_secret YOURLS_DB_PASS "YOURLS DB password (leave blank to keep current):" false
    prompt_env_secret YOURLS_DB_ROOT_PASS "YOURLS DB root password (leave blank to keep current):" false
  fi
}

ensure_env_media_extras() {
  warn "---[ Media paths & app secrets ]---"
  # Defaults reflect your layout
  prompt_env MEDIA_ROOT "MEDIA_ROOT (host path):" "/mnt/truenas/02 - Media"
  prompt_env DL_ROOT "DL_ROOT (host path to downloads):" "/mnt/truenas/02 - Media/downloads"
  prompt_env_secret PLEX_CLAIM "PLEX_CLAIM (leave blank if not using Plex):" false
  prompt_env_secret PHOTOPRISM_ADMIN_PASSWORD "Photoprism admin password (blank to keep):" false
  prompt_env_secret IMMICH_DB_PASSWORD "Immich DB password (blank to keep):" false
}

ensure_env_downloads_extras() {
  warn "---[ Downloads paths & Gluetun ]---"
  prompt_env DL_ROOT "DL_ROOT (host path to downloads):" "/mnt/truenas/02 - Media/downloads"
  prompt_env GLUETUN_VPN_SERVICE_PROVIDER "VPN provider:" "mullvad"
  prompt_env GLUETUN_VPN_TYPE "VPN type:" "wireguard"
  prompt_env_secret GLUETUN_WG_PRIVATE_KEY "WireGuard private key (blank to keep):" false
  prompt_env GLUETUN_SERVER_CITIES "VPN server city:" "Stockholm"
}

configure_stack_profiles() {
  local STACK="$1"; shift
  local DEFAULTS="$*"
  local current
  current=$(get_env COMPOSE_PROFILES)
  warn "---[ $STACK stack profiles ]---"
  read -r -e -i "${current:-$DEFAULTS}" -p "Enter COMPOSE_PROFILES (comma-separated) for $STACK: " PROFILES
  upsert_env COMPOSE_PROFILES "$PROFILES"
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
            # --- AI stack services ---
            ollama) mkdir -p "${BASE_DIR}/data" ;;
            llamacpp) mkdir -p "${BASE_DIR}/models" ;;
            openwebui) mkdir -p "${BASE_DIR}/data" ;;
            pipelines) mkdir -p "${BASE_DIR}/data" ;;
            sillytavern)
                mkdir -p "${BASE_DIR}/config" "${BASE_DIR}/data" "${BASE_DIR}/plugins" "${BASE_DIR}/extensions"
                ;;
            n8n) mkdir -p "${BASE_DIR}/data" ;;
            comfyui)
                mkdir -p "${BASE_DIR}/models" "${BASE_DIR}/input" "${BASE_DIR}/output" "${BASE_DIR}/custom_nodes"
                ;;
            tts)
                mkdir -p "${BASE_DIR}/voices" "${BASE_DIR}/config"
                ;;
        esac

        sudo chown -R "$CURRENT_UID":"$CURRENT_GID" "$BASE_DIR"
    done
    success "All service directories prepared."
}


# Optional: AI-specific env additions for profiles and model paths
configure_ai_env_overrides() {
    warn "---[ AI Stack Profiles & Paths ]---"
    echo "Available profiles:"
    echo "  - openwebui    (Open WebUI frontend)"
    echo "  - ollama       (Ollama backend)"
    echo "  - llamacpp     (llama.cpp OpenAI-compatible server)"
    echo "  - sillytavern  (chat frontend)"
    echo "  - n8n          (automation)"
    echo "  - comfyui      (visual pipeline)"
    echo "  - tts-openedai (OpenAI-compatible TTS)"
    echo "  - watchtower   (auto-updates on AI host)"
    local DEFAULT_PROFILES="openwebui,ollama,watchtower,sillytavern,n8n,comfyui,tts-openedai"
    read -r -e -i "$DEFAULT_PROFILES" -p "Enter COMPOSE_PROFILES (comma-separated): " AI_PROFILES

    # Paths with defaults
    local DEFAULT_OLLAMA_DIR="/opt/models"
    read -r -e -i "$DEFAULT_OLLAMA_DIR" -p "Path to Ollama models dir: " OLLAMA_MODELS_DIR
    read -r -e -p "Path to llama.cpp models dir (bind mount) [optional]: " LLAMACPP_MODELS_DIR
    read -r -e -p "llama.cpp GGUF full path (LLAMACPP_MODEL_PATH) [optional]: " LLAMACPP_MODEL_PATH

    # Update or append keys in .env idempotently
    grep -q '^COMPOSE_PROFILES=' .env && sed -i "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=${AI_PROFILES}|" .env || echo "COMPOSE_PROFILES=${AI_PROFILES}" >> .env
    grep -q '^OLLAMA_MODELS_DIR=' .env && sed -i "s|^OLLAMA_MODELS_DIR=.*|OLLAMA_MODELS_DIR=${OLLAMA_MODELS_DIR}|" .env || echo "OLLAMA_MODELS_DIR=${OLLAMA_MODELS_DIR}" >> .env
    if [ -n "$LLAMACPP_MODELS_DIR" ]; then
        grep -q '^LLAMACPP_MODELS_DIR=' .env && sed -i "s|^LLAMACPP_MODELS_DIR=.*|LLAMACPP_MODELS_DIR=${LLAMACPP_MODELS_DIR}|" .env || echo "LLAMACPP_MODELS_DIR=${LLAMACPP_MODELS_DIR}" >> .env
    fi
    if [ -n "$LLAMACPP_MODEL_PATH" ]; then
        grep -q '^LLAMACPP_MODEL_PATH=' .env && sed -i "s|^LLAMACPP_MODEL_PATH=.*|LLAMACPP_MODEL_PATH=${LLAMACPP_MODEL_PATH}|" .env || echo "LLAMACPP_MODEL_PATH=${LLAMACPP_MODEL_PATH}" >> .env
    fi

    success "AI profiles and paths updated in .env"
}

ensure_ai_host_dirs() {
    # Read values from .env (use defaults if not set)
    local OMD LMD
    OMD=$(grep -E '^OLLAMA_MODELS_DIR=' .env | cut -d= -f2)
    [ -z "$OMD" ] && OMD="/opt/models"
    LMD=$(grep -E '^LLAMACPP_MODELS_DIR=' .env | cut -d= -f2)

    # Create and set sane perms for host model dirs (readable by container root; writable by your user)
    if [ ! -d "$OMD" ]; then
        sudo mkdir -p "$OMD"
        sudo chown "$USER":"$USER" "$OMD"
        sudo chmod 755 "$OMD"
        info "Created Ollama models dir: $OMD"
    fi
    if [ -n "$LMD" ] && [ ! -d "$LMD" ]; then
        sudo mkdir -p "$LMD"
        sudo chown "$USER":"$USER" "$LMD"
        sudo chmod 755 "$LMD"
        info "Created llama.cpp models dir: $LMD"
    fi
}

ensure_llamacpp_env_defaults() {
    # idempotent inserts
    grep -q '^LLAMACPP_CTX_SIZE=' .env || echo 'LLAMACPP_CTX_SIZE=16384' >> .env
    grep -q '^LLAMACPP_NGL=' .env || echo 'LLAMACPP_NGL=80' >> .env
    grep -q '^LLAMACPP_THREADS=' .env || echo 'LLAMACPP_THREADS=24' >> .env
    grep -q '^LLAMACPP_THREADS_BATCH=' .env || echo 'LLAMACPP_THREADS_BATCH=24' >> .env
    # If user gave a models dir but no model path, set a sensible default (matches compose)
    if grep -q '^LLAMACPP_MODELS_DIR=' .env && ! grep -q '^LLAMACPP_MODEL_PATH=' .env; then
        echo 'LLAMACPP_MODEL_PATH=/models/Qwen3-235B-A22B-Thinking-2507-UD-Q2_K_XL/UD-Q2_K_XL/Qwen3-235B-A22B-Thinking-2507-UD-Q2_K_XL-00001-of-00002.gguf' >> .env
    fi
}

# Map profiles -> directories to prep
compute_ai_dirs_from_profiles() {
  local profiles_csv="$1"
  local -A map=(
    [openwebui]="openwebui pipelines"
    [ollama]="ollama"
    [llamacpp]="llamacpp"
    [sillytavern]="sillytavern"
    [n8n]="n8n"
    [comfyui]="comfyui"
    [tts-openedai]="tts"
    [watchtower]="watchtower"
  )
  local IFS=','; read -ra profs <<< "$profiles_csv"
  local out=()
  for p in "${profs[@]}"; do
    if [ -n "${map[$p]}" ]; then
      # split map value into words safely
      read -r -a words <<< "${map[$p]}"
      out+=("${words[@]}")
    fi
  done
  printf '%s\n' "${out[@]}"
}


deploy_stack() {
    # Export .env so COMPOSE_PROFILES and others affect compose behavior
    if [ -f ".env" ]; then
        set -a
        # shellcheck disable=SC1091
        source .env
        set +a
    fi

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
    docker compose pull

    info "Starting or updating containers in detached mode..."
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
Last Docker Documentation Review: 2025-08-23
---------------------------------------------------------------------
EOF
    echo ""
    echo "Select a service stack to manage:"
    echo "  1) Utilities (Caddy, Authelia, Glance, etc.)"
    echo "  2) AI (Open WebUI, SillyTavern, etc.)"
    echo "  3) Media (Arr, Jellyfin/Plex, Overseerr, etc.)"
    echo "  4) Downloads (qBittorrent, SAB, yt-dlp, Pinchflat, etc.)"
    echo ""
    echo "  q) Quit"
    echo ""
    read -r -p "Enter your choice: " stack_choice

    case "$stack_choice" in
        1) manage_stack "utilities" ;;
        2) manage_stack "ai" ;;
        3) manage_stack "media" ;;
        4) manage_stack "downloads" ;;
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
    read -r -p "Enter your action: " action_choice

    case "$action_choice" in
        1)
            # --- DEPLOYMENT LOGIC ---
            info "Preparing to deploy the '$STACK_NAME' stack..."
            mkdir -p "$DEPLOY_PATH"
            cd "$DEPLOY_PATH" || exit

            # Env base handlers
            ensure_env_file_present
            ensure_env_basics
            if [ "$STACK_NAME" == "ai" ]; then
                # Collect AI-specific env and ensure host model dirs exist
                configure_ai_env_overrides
                ensure_ai_host_dirs

                # Build only the needed service dir list from profiles
                local profiles
                profiles=$(grep -E '^COMPOSE_PROFILES=' .env | cut -d= -f2)
                if [ -z "$profiles" ]; then
                    warn "COMPOSE_PROFILES not set in .env; defaulting to openwebui,ollama,watchtower"
                    profiles="openwebui,ollama,watchtower"
                    grep -q '^COMPOSE_PROFILES=' .env && sed -i "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=${profiles}|" .env || echo "COMPOSE_PROFILES=${profiles}" >> .env
                fi
                mapfile -t AI_DIRS < <(compute_ai_dirs_from_profiles "$profiles")
                prepare_service_directories "$STACK_NAME" "${AI_DIRS[@]}"
                write_llamacpp_assets
                ensure_llamacpp_env_defaults
                # Generate AI compose
                generate_ai_compose
                install_heavy_mode_script
            elif [ "$STACK_NAME" == "utilities" ]; then
                configure_stack_profiles "utilities" "core,watchtower,code,ntfy"
                prepare_service_directories "$STACK_NAME" caddy glance watchtower code authelia redis uptime-kuma vaultwarden ntfy couchdb kiwix privatebin
                ensure_env_utilities_extras
                generate_utilities_compose
                generate_glance_config
                generate_authelia_from_template
            elif [ "$STACK_NAME" == "media" ]; then
                configure_stack_profiles "media" "arr,jellyfin,overseerr,watchtower"
                prepare_service_directories "$STACK_NAME" prowlarr sonarr radarr lidarr readarr bazarr jellyfin plex overseerr audiobookshelf calibre calibre-web photoprism immich
                ensure_env_media_extras
                verify_media_layout
                generate_media_compose
            elif [ "$STACK_NAME" == "downloads" ]; then
                configure_stack_profiles "downloads" "vpn,qbittorrent,sabnzbd,yt-dlp,pinchflat,podgrab,watchtower"
                prepare_service_directories "$STACK_NAME" gluetun qbittorrent sabnzbd yt-dlp podgrab pinchflat watchtower
                ensure_env_downloads_extras
                generate_downloads_compose
            fi

            # Deploy stack
            deploy_stack
            ;;
        2)
            # --- CONFIG ONLY MODE ---
            info "Generating config files for '$STACK_NAME' without deploying..."
            mkdir -p "$DEPLOY_PATH"
            cd "$DEPLOY_PATH" || exit

            # Ensure .env exists
            ensure_env_file_present
            ensure_env_basics

            if [ "$STACK_NAME" == "ai" ]; then
                # Collect AI env and ensure dirs
                configure_ai_env_overrides
                ensure_ai_host_dirs

                local profiles
                profiles=$(grep -E '^COMPOSE_PROFILES=' .env | cut -d= -f2)
                if [ -z "$profiles" ]; then
                    profiles="openwebui,ollama,watchtower"
                    grep -q '^COMPOSE_PROFILES=' .env && sed -i "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=${profiles}|" .env || echo "COMPOSE_PROFILES=${profiles}" >> .env
                fi
                mapfile -t AI_DIRS < <(compute_ai_dirs_from_profiles "$profiles")
                prepare_service_directories "$STACK_NAME" "${AI_DIRS[@]}"

                generate_ai_compose
            elif [ "$STACK_NAME" == "utilities" ]; then
                configure_stack_profiles "utilities" "core,watchtower,code"
                prepare_service_directories "$STACK_NAME" caddy glance watchtower code authelia redis uptime-kuma vaultwarden
                ensure_env_utilities_extras
                generate_utilities_compose
                generate_glance_config
                generate_authelia_from_template
            elif [ "$STACK_NAME" == "media" ]; then
                configure_stack_profiles "media" "arr,jellyfin,overseerr,watchtower"
                prepare_service_directories "$STACK_NAME" prowlarr sonarr radarr lidarr readarr bazarr jellyfin overseerr
                ensure_env_media_extras
                verify_media_layout
                generate_media_compose
            elif [ "$STACK_NAME" == "downloads" ]; then
                configure_stack_profiles "downloads" "vpn,qbittorrent,sabnzbd,yt-dlp,pinchflat,podgrab,watchtower"
                prepare_service_directories "$STACK_NAME" gluetun qbittorrent sabnzbd yt-dlp podgrab pinchflat watchtower
                ensure_env_downloads_extras
                generate_downloads_compose
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
