#!/bin/bash

# Fish Shell 4.0 Setup Script
# Automates the setup of Fish Shell, Starship Prompt, FastFetch, and JetBrains Mono Nerd Font.

# ⚠️ WARNING: This script will overwrite configuration files.
# Make sure to back up your existing configurations before running this script.
# I am not responsible for any data loss, misconfigurations, or issues that may arise.

set -e  # Exit immediately on errors

function info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

function error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
    exit 1
}

# Display warning message
echo -e "\033[1;31m⚠️ WARNING\033[0m"
echo "This script will overwrite the following configuration files:"
echo "- ~/.config/fish/config.fish"
echo "- ~/.config/starship.toml"
echo "- ~/.config/fastfetch/config.jsonc"
echo
echo "Make sure to back up your existing configurations before proceeding."
echo "I am not responsible for any data loss, misconfigurations, or issues."
echo
read -p "Do you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Exiting script. No changes were made."
    exit 1
fi

# Function to install fortune-mod
install_fortune() {
    if ! command -v fortune >/dev/null 2>&1; then
        info "Installing fortune-mod..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y fortune-mod
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y fortune-mod
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm fortune-mod
        elif command -v brew >/dev/null 2>&1; then
            brew install fortune
        else
            error "Unsupported package manager. Please install fortune-mod manually."
        fi
    else
        info "fortune-mod is already installed."
    fi
}

# Paths
POKEID_FILE="$HOME/.pokeid"
FASTFETCH_CONFIG_DIR="$HOME/.config/fastfetch"
FISH_CONFIG_DIR="$HOME/.config/fish"
STARSHIP_CONFIG_DIR="$HOME/.config"
FASTFETCH_CONFIG="$FASTFETCH_CONFIG_DIR/config.jsonc"
FISH_CONFIG="$FISH_CONFIG_DIR/config.fish"
STARSHIP_CONFIG="$STARSHIP_CONFIG_DIR/starship.toml"

# Function to assign a Pokémon deterministically (or randomly if necessary)
assign_pokemon() {
    # If a Pokémon is already assigned, reuse it
    if [ -f "$POKEID_FILE" ]; then
        echo "Pokémon already assigned: $(cat "$POKEID_FILE")"
        return
    fi

    # Generate a unique identifier for the system (hostname + machine-id)
    unique_id="$(hostname)$(cat /etc/machine-id 2>/dev/null || echo "fallback-id")"

    # Hash the unique ID to generate a Pokédex number (1-905 for Gen 1-8 Pokémon)
    hashed_index=$(( $(echo -n "$unique_id" | sha256sum | awk '{print $1}' | sed 's/[^0-9]//g' | cut -c1-8) % 905 + 1 ))

    # Retrieve Pokémon using pokeget for the hashed index
    if command -v pokeget >/dev/null 2>&1; then
        pokemon_name=$(pokeget "$hashed_index" 2>/dev/null) || pokemon_name="Unknown Pokémon (Index $hashed_index)"
    else
        echo "pokeget is not installed! Assigning a random Pokémon."
        pokemon_name="Random Pokémon $(date +%s | sha256sum | cut -d' ' -f1 | head -c 8)"
    fi

    # Save the assigned Pokémon
    echo "$hashed_index" > "$POKEID_FILE"
    echo "Assigned Pokémon number: $pokemon_name"
}

# Install dependencies
install_dependencies() {
    info "Installing essential dependencies..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y
        sudo apt-get install -y git curl wget unzip fontconfig autoconf build-essential zlib1g-dev libncurses5-dev
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm git curl wget unzip fontconfig base-devel ncurses
    else
        error "Unsupported package manager."
    fi
}

# Install Rust
install_rust() {
    if ! command -v rustc >/dev/null 2>&1; then
        info "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        info "Rust is already installed."
    fi
}

# Install pokeget
install_pokeget() {
    if ! command -v pokeget >/dev/null 2>&1; then
        info "Installing pokeget..."
        cargo install pokeget
    else
        info "pokeget is already installed."
    fi
}

# Install FastFetch
install_fastfetch() {
    if ! command -v fastfetch >/dev/null 2>&1; then
        info "Installing FastFetch..."
        git clone https://github.com/LinusDierheimer/fastfetch.git ~/fastfetch
        cd ~/fastfetch
        mkdir -p build && cd build
        cmake .. && make -j$(nproc)
        sudo make install
        cd ~
        rm -rf ~/fastfetch
    else
        info "FastFetch is already installed."
    fi
}

install_nerd_fonts() {
    FONT_DIR="$HOME/.local/share/fonts"
    FONT_NAME="JetBrains Mono"

    # Check if any JetBrains Mono Nerd Font file already exists
    if [ -n "$(find "$FONT_DIR" -name "*JetBrains Mono*Nerd Font*" -print -quit)" ]; then
        info "JetBrains Mono Nerd Font is already installed."
        return
    fi

    # Download and install the font if it doesn't exist
    info "Installing JetBrains Mono Nerd Font..."
    mkdir -p "$FONT_DIR"
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v2.3.3/JetBrainsMono.zip"
    FONT_TMP_DIR=$(mktemp -d)
    curl -fLo "$FONT_TMP_DIR/JetBrainsMono.zip" "$FONT_URL"
    unzip -o "$FONT_TMP_DIR/JetBrainsMono.zip" -d "$FONT_TMP_DIR"
    find "$FONT_TMP_DIR" -name "*.[o,t]tf" -type f -exec cp {} "$FONT_DIR/" \;
    fc-cache -f "$FONT_DIR"
    rm -rf "$FONT_TMP_DIR"
}

# Install Fish 4.0 beta
install_fish() {
    if ! command -v fish >/dev/null 2>&1; then
        info "Installing Fish 4.0 beta..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo add-apt-repository ppa:fish-shell/beta-4 -y
            sudo apt-get update
            sudo apt-get install -y fish
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm fish
        else
            error "Unsupported package manager for Fish 4.0 beta."
        fi
    else
        info "Fish Shell is already installed."
    fi
}

# Configure FastFetch
configure_fastfetch() {
    info "Configuring FastFetch..."
    mkdir -p "$FASTFETCH_CONFIG_DIR"
    cat > "$FASTFETCH_CONFIG" << 'EOF'
// FastFetch configuration file
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
        { "type": "os", "key": " OS", "keyColor": "yellow", "format": "{2}" },
        { "type": "kernel", "key": "├ kernel", "keyColor": "yellow" },
        { "type": "packages", "key": "├󰏖 packages", "keyColor": "yellow" },
        { "type": "shell", "key": "└ shell", "keyColor": "yellow" },
        { "type": "wm", "key": " DE/WM", "keyColor": "blue" },
        { "type": "lm", "key": "├󰧨 login", "keyColor": "blue" },
        { "type": "wmtheme", "key": "├󰉼 theme", "keyColor": "blue" },
        { "type": "icons", "key": "├󰀻 icons", "keyColor": "blue" },
        { "type": "terminal", "key": "├ shell", "keyColor": "blue" },
        { "type": "wallpaper", "key": "└󰸉 wallpaper", "keyColor": "blue" },
        { "type": "host", "key": "󰌢 PC", "keyColor": "green" },
        { "type": "cpu", "temp": true, "key": "├󰻠 cpu", "keyColor": "green" },
        { "type": "gpu", "key": "├󰍛 gpu", "keyColor": "green" },
        { "type": "disk", "key": "├ disk", "keyColor": "green" },
        { "type": "memory", "key": "├󰑭 ram", "keyColor": "green" },
        { "type": "swap", "key": "├󰓡 swap", "keyColor": "green" },
        { "type": "display", "key": "├󰍹 display", "keyColor": "green" },
        { "type": "uptime", "key": "└󰅐 uptime", "keyColor": "green" },
        { "type": "sound", "key": " SOUND", "keyColor": "cyan" },
        { "type": "player", "key": "├󰥠", "keyColor": "cyan" },
        { "type": "media", "key": "└󰝚 media", "keyColor": "cyan" }
    ]
}
EOF
}

# Configure Fish
configure_fish() {
    info "Configuring Fish Shell..."
    mkdir -p "$FISH_CONFIG_DIR/functions"
    cat > "$FISH_CONFIG" << 'EOF'
if status is-interactive
    # Commands for interactive sessions
end

function fish_greeting
    set_color normal
    echo

    # Display the assigned Pokémon or a random one if none is assigned
    if test -f "$HOME/.pokeid"
        pokeget (cat "$HOME/.pokeid") --hide-name | fastfetch --file-raw -
    else
        pokeget random --hide-name | fastfetch --file-raw -
    end

    # Display a random fortune
    if command -v fortune >/dev/null 2>&1
        fortune -s
    else
        echo "Install 'fortune-mod' to see random fortunes!"
    end

    echo
end

# Initialize Starship prompt
starship init fish | source
EOF
}

# Configure Starship
configure_starship() {
    info "Configuring Starship..."
    mkdir -p "$STARSHIP_CONFIG_DIR"
    cat > "$STARSHIP_CONFIG" << 'EOF'
# Starship prompt configuration
# Don't print a new line at the start of the prompt
add_newline = true

# Prompt format
format = """$all$character"""

# Use a custom prompt character
[character]
success_symbol = "[❯](purple)"
error_symbol = "[❯](red)"
vimcmd_symbol = "[❮](green)"

# Directory module
[directory]
truncation_length = 3
truncation_symbol = "…/"
home_symbol = "~"

# Git status module
[git_status]
conflicted = "⚔️ "
ahead = "⇡${count}"
behind = "⇣${count}"
staged = "[+${count}](green)"
modified = "[~${count}](red)"
untracked = "[?${count}](yellow)"
deleted = "🗑️ "
renamed = "➡️ "
style = "bold yellow"

# Git branch module
[git_branch]
symbol = "🌱 "

# Node.js module
[nodejs]
format = "via [🌐 v${version}]($style) "

# Python module
[python]
format = "via [🐍 v${version}]($style) "

# Rust module
[rust]
format = "via [🦀 v${version}]($style) "

# Package module
[package]
format = "[$symbol$version]($style) "
symbol = "📦 "

# Battery status module
[battery]
full_symbol = "🔋 "
charging_symbol = "⚡️ "
discharging_symbol = "🔌 "
display = [
    { threshold = 10, style = "bold red" },
    { threshold = 30, style = "bold yellow" },
    { style = "bold green" }
]

# Time module
[time]
disabled = false
format = "[$time]($style) "
time_format = "%H:%M"
style = "bold dimmed white"

# Command duration module
[cmd_duration]
min_time = 2000
format = "took [$duration]($style) "
style = "bold yellow"

# Shell indicator
[shell]
powershell_indicator = "_"
unknown_indicator = "mystery shell"
style = "cyan bold"
disabled = true

# AWS Profile
[aws]
symbol = "🅰 "
format = 'on [$symbol($profile )(\($region\) )]($style)'
style = "bold yellow"
disabled = false

# Custom module example (e.g., Kubernetes context)
[custom.k8s]
command = "kubectl config current-context"
when = "command -v kubectl > /dev/null"
format = "on [⎈ $output](bold blue) "

# Disable unused modules
[gcloud]
disabled = true
[env_var]
disabled = true
[hostname]
disabled = true
[username]
disabled = true
[line_break]
disabled = true
EOF
}

# Main Installation Steps
install_dependencies
install_rust
install_pokeget
install_fastfetch
install_nerd_fonts
install_fish
assign_pokemon
configure_fastfetch
configure_fish
configure_starship

info "Setup complete! Restart your terminal to see the changes."
