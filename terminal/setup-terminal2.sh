#!/bin/bash
#
# Fish Shell & Modern Terminal Enhancement Suite
# Automates the setup of Fish, Starship, FastFetch, and more on Ubuntu/Debian/Fedora systems.

# --- Safety First: Exit on any error ---
set -e

# --- Global Variables ---
PKG_MANAGER=""

# --- Logging Functions for pretty output ---
info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
    exit 1
}

warn() {
    echo -e "\033[1;33m[WARN]\033[0m $1"
}

# --- Package Manager Detection ---
check_package_manager() {
    info "Checking system package manager..."
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    else
        error "Unsupported package manager. Please use a Debian/Ubuntu or Fedora based system."
    fi
    info "Found package manager: $PKG_MANAGER"
}

# --- Backup Function ---
backup_file() {
    local FILE_PATH="$1"
    if [ -f "$FILE_PATH" ]; then
        local BACKUP_PATH="${FILE_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
        info "Existing file found at $FILE_PATH. Backing it up to $BACKUP_PATH"
        mv "$FILE_PATH" "$BACKUP_PATH"
    fi
}

# --- User Confirmation ---
display_warning() {
    warn "This script will create/replace configuration files."
    warn "Existing configurations will be backed up (e.g., config.fish -> config.fish.bak.timestamp)."
    echo "- ~/.config/fish/config.fish"
    echo "- ~/.config/starship.toml"
    echo "- ~/.config/fastfetch/config.jsonc"
    echo
    read -p "Do you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Exiting script. No changes were made."
        exit 0
    fi
}

# --- Prerequisite Installation ---
check_and_install_dependencies() {
    info "Checking for dependencies..."
    
    case "$PKG_MANAGER" in
        "apt-get")
            PACKAGES="git curl wget unzip fontconfig gawk build-essential cmake fortunes fortunes-off"
            sudo apt-get update
            ;;
        "dnf")
            PACKAGES="git curl wget unzip fontconfig gawk cmake fortune-mod gcc gcc-c++"
            ;;
    esac

    info "Installing base packages: $PACKAGES"
    sudo $PKG_MANAGER install -y $PACKAGES
}

# --- Component Installation Functions ---
install_rust() {
    if command -v cargo &> /dev/null; then
        info "Rust is already installed."
    else
        info "Installing Rust via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
}

install_pokeget() {
    export PATH="$HOME/.cargo/bin:$PATH"
    if command -v pokeget &> /dev/null; then
        info "pokeget is already installed."
    else
        info "Installing pokeget via cargo..."
        cargo install pokeget
    fi
}

install_fastfetch() {
    if command -v fastfetch &> /dev/null; then
        info "FastFetch is already installed."
        return
    fi

    case "$PKG_MANAGER" in
        "apt-get")
            info "Installing FastFetch from latest .deb release..."
            FASTFETCH_URL=$(curl -s "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" | grep "browser_download_url.*-linux-amd64.deb" | cut -d '"' -f 4)
            ;;
        "dnf")
            info "Installing FastFetch from latest .rpm release..."
            FASTFETCH_URL=$(curl -s "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" | grep "browser_download_url.*.rpm" | cut -d '"' -f 4)
            ;;
    esac

    if [ -z "$FASTFETCH_URL" ]; then
        error "Could not find a suitable FastFetch release. Please install manually."
    fi

    local PKG_FILE="/tmp/fastfetch.pkg"
    wget -q --show-progress -O "$PKG_FILE" "$FASTFETCH_URL"
    
    case "$PKG_MANAGER" in
        "apt-get") sudo apt-get install -y "$PKG_FILE" ;;
        "dnf") sudo dnf install -y "$PKG_FILE" ;;
    esac
    rm "$PKG_FILE"
}

install_nerd_font() {
    local FONT_DIR="$HOME/.local/share/fonts"
    if fc-list | grep -qi "JetBrainsMono Nerd Font"; then
        info "JetBrains Mono Nerd Font is already installed."
    else
        info "Installing JetBrains Mono Nerd Font..."
        mkdir -p "$FONT_DIR"
        local FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip"
        wget -q --show-progress -O /tmp/JetBrainsMono.zip "$FONT_URL"
        unzip -o /tmp/JetBrainsMono.zip -d "$FONT_DIR"
        rm /tmp/JetBrainsMono.zip
        info "Updating font cache..."
        fc-cache -fv
    fi
}

install_fish() {
    if command -v fish &> /dev/null; then
        info "Fish Shell is already installed."
    else
        info "Installing Fish Shell..."
        case "$PKG_MANAGER" in
            "apt-get")
                sudo add-apt-repository ppa:fish-shell/release-3 -y
                sudo apt-get update
                sudo apt-get install -y fish
                ;;
            "dnf")
                sudo dnf install -y fish
                ;;
        esac
    fi
    
    info "Setting Fish as the default shell for $(whoami)..."
    local FISH_PATH=$(command -v fish)
    if [ -n "$FISH_PATH" ] && [ "$(getent passwd "$(whoami)" | cut -d: -f7)" != "$FISH_PATH" ]; then
        sudo chsh -s "$FISH_PATH" "$(whoami)"
        info "Default shell changed. This will take effect on your next login."
    else
        info "Fish is already the default shell."
    fi
}

install_starship() {
    if command -v starship &> /dev/null; then
        info "Starship is already installed."
    else
        info "Installing Starship prompt..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
}

# --- Configuration Functions ---
assign_pokemon() {
    local POKEID_FILE="$HOME/.pokeid"
    if [ -s "$POKEID_FILE" ]; then
        info "Pokémon already assigned: #$(cat "$POKEID_FILE"). Reusing."
        return
    fi

    info "Assigning a unique Pokémon identifier to this system..."
    local machine_id=$(cat /etc/machine-id 2>/dev/null || systemd-machine-id-get 2>/dev/null)
    
    if [ -z "$machine_id" ]; then
        warn "Could not get machine ID. Using random Pokémon."
        echo $(( RANDOM % 1025 + 1 )) > "$POKEID_FILE"
        return
    fi

    # Generate Pokémon ID using hex conversion method
    local pokedex_num=0
    for (( i=0; i<${#machine_id}; i++ )); do
        local char=$(printf '%d' "'${machine_id:$i:1}")
        pokedex_num=$(( pokedex_num + char ))
    done
    pokedex_num=$(( (pokedex_num % 1025) + 1 ))

    echo "$pokedex_num" > "$POKEID_FILE"
    info "System assigned Pokédex #$pokedex_num."
}

configure_fish_shell() {
    info "Configuring Fish Shell..."
    local CONFIG_DIR="$HOME/.config/fish"
    local CONFIG_FILE="$CONFIG_DIR/config.fish"
    mkdir -p "$CONFIG_DIR"
    backup_file "$CONFIG_FILE"

    cat > "$CONFIG_FILE" << 'EOF'
# Add Cargo's bin directory to the Fish path if it's not already there
if not contains "$HOME/.cargo/bin" $fish_user_paths
    set -U fish_user_paths "$HOME/.cargo/bin" $fish_user_paths
end

# --- Starship Prompt Initialization ---
if status is-interactive
    starship init fish | source
end

# --- Custom Fish Greeting ---
function fish_greeting
    set_color normal
    echo ""

    set POKEMON_ID_FILE "$HOME/.pokeid"
    set POKEGET_CMD "pokeget"

    if test -s "$POKEMON_ID_FILE"; and command -v $POKEGET_CMD &> /dev/null
        $POKEGET_CMD (cat $POKEMON_ID_FILE) --hide-name | fastfetch --logo-type file-raw --logo -
    else
        fastfetch
    end

    if command -v fortune &> /dev/null
        echo ""
        fortune -s
    end
    echo ""
end
EOF
}

configure_starship_prompt() {
    info "Configuring Starship prompt..."
    local CONFIG_FILE="$HOME/.config/starship.toml"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    backup_file "$CONFIG_FILE"

    cat > "$CONFIG_FILE" << 'EOF'
add_newline = true
format = """$all$character"""

[character]
success_symbol = "[❯](purple)"
error_symbol = "[❯](red)"
vimcmd_symbol = "[❮](green)"

[directory]
truncation_length = 3
truncation_symbol = "…/"
home_symbol = "~"

[git_status]
conflicted = "⚔️ "
ahead = "⇡${count}"
behind = "${count}"
staged = "[+${count}](green)"
modified = "[~${count}](red)"
untracked = "[?${count}](yellow)"
deleted = "🗑️ "
renamed = "➡️ "
style = "bold yellow"

[git_branch]
symbol = "🌱 "

[nodejs]
format = "via [🌐 v${version}]($style) "
[python]
format = "via [🐍 v${version}]($style) "
[rust]
format = "via [🦀 v${version}]($style) "
[package]
format = "[$symbol$version]($style) "
symbol = "📦 "

[battery]
full_symbol = "🔋 "
charging_symbol = "⚡️ "
discharging_symbol = "🔌 "
display = [ { threshold = 10, style = "bold red" }, { threshold = 30, style = "bold yellow" }, { style = "bold green" } ]

[time]
disabled = false
format = "[$time]($style) "
time_format = "%H:%M"
style = "bold dimmed white"

[cmd_duration]
min_time = 2000
format = "took [$duration]($style) "
style = "bold yellow"

# Disable noisy modules
[hostname]
disabled = true
[username]
disabled = true
[line_break]
disabled = true
EOF
}

configure_fastfetch_logo() {
    info "Configuring FastFetch..."
    local CONFIG_DIR="$HOME/.config/fastfetch"
    local CONFIG_FILE="$CONFIG_DIR/config.jsonc"
    mkdir -p "$CONFIG_DIR"
    backup_file "$CONFIG_FILE"

    cat > "$CONFIG_FILE" << 'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "padding": {
            "top": 2
        }
    },
    "display": {
        "separator": "",
        "key": {
            "width": 15
        }
    },
    "modules": [
        // OS & Shell Info (Yellow)
        { "type": "os", "key": " OS", "keyColor": "yellow", "format": "{2}" },
        { "type": "kernel", "key": "├ kernel", "keyColor": "yellow" },
        { "type": "packages", "key": "├󰏖 packages", "keyColor": "yellow" },
        { "type": "shell", "key": "└ shell", "keyColor": "yellow" },
        // Host & Hardware Info (Green)
        { "type": "host", "key": "󰌢 Host", "keyColor": "green" },
        { "type": "cpu", "temp": true, "key": "├󰻠 cpu", "keyColor": "green" },
        { "type": "gpu", "key": "├󰍛 gpu", "keyColor": "green" },
        { "type": "display", "key": "├󰍹 display", "keyColor": "green" },
        { "type": "uptime", "key": "└󰅐 uptime", "keyColor": "green" },
        // System Status Block (Magenta)
        { "type": "loadavg", "key": "󰊘 Load", "keyColor": "magenta" },
        { "type": "processes", "key": "├󰥧 Processes", "keyColor": "magenta" },
        { "type": "users", "key": "├h Users", "keyColor": "magenta" },
        { "type": "memory", "key": "├󰑭 RAM", "keyColor": "magenta" },
        { "type": "swap", "key": "├󰓡 Swap", "keyColor": "magenta" },
        { "type": "disk", "key": "├ Disk (Root)", "keyColor": "magenta", "folders": ["/"] },
        { "type": "localip", "key": "└󰩟 Local IP", "keyColor": "magenta", "showType": false },
        // Desktop Environment Info (Blue)
        { "type": "wm", "key": " DE/WM", "keyColor": "blue" },
        { "type": "terminal", "key": "└ Terminal", "keyColor": "blue" }
    ]
}
EOF
}

# --- Main Execution Logic ---
main() {
    display_warning
    check_package_manager

    info "--- Starting Terminal Enhancement Setup ---"
    
    info "==> Step 1: Installing Dependencies..."
    check_and_install_dependencies
    install_rust
    install_pokeget
    install_fastfetch
    install_nerd_font
    install_fish
    install_starship
    
    info "==> Step 2: Applying Configurations..."
    assign_pokemon
    configure_fastfetch_logo
    configure_starship_prompt
    configure_fish_shell
    
    info "--- Setup Complete! ---"
    warn "Please log out and log back in, or reboot your system, for all changes to take full effect."
}

# --- Run the main function ---
main
