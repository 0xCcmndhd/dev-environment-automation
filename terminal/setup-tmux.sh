#!/bin/bash
# tmux Setup Script with Catppuccin Theme and Optimized Keybindings
set -e  # Exit immediately on errors

function info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

function error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
    exit 1
}

# Install tmux
if ! command -v tmux >/dev/null 2>&1; then
    info "Installing tmux..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y tmux
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm tmux
    else
        error "Unsupported package manager for tmux."
    fi
else
    info "tmux is already installed."
fi

# Install TPM (Tmux Plugin Manager)
info "Installing Tmux Plugin Manager (TPM)..."
mkdir -p ~/.config/tmux/plugins
if [ ! -d ~/.config/tmux/plugins/tpm ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
else
    info "TPM is already installed."
fi

# Backup existing tmux configuration (if any)
if [ -f ~/.config/tmux/tmux.conf ]; then
    info "Backing up existing tmux configuration..."
    cp ~/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf.bak
fi

# Configure tmux with Catppuccin theme and optimized keybindings
info "Configuring tmux with Catppuccin theme and optimized keybindings..."
cat > ~/.config/tmux/tmux.conf << 'EOF'
# ==========================
# ===  General settings  ===
# ==========================
set-option -sa terminal-overrides ",xterm*:Tc"
set -g default-terminal "tmux-256color"
set -g history-limit 20000
set -g buffer-limit 20
set -g mouse on
set -g focus-events on

# ==========================
# ===   Key bindings    ===
# ==========================
# Unbind default prefix (Ctrl + B)
unbind C-b

# Set prefix to Ctrl + A
set -g prefix C-a
bind C-a send-prefix

# Reload configuration
unbind r
bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

# Splitting windows
bind o split-window -v -c "#{pane_current_path}"
bind p split-window -h -c "#{pane_current_path}"

# Vim style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Quick window selection
bind -r C-h select-window -t :-
bind -r C-l select-window -t :+

# Pane resizing
bind -r H resize-pane -L 2
bind -r J resize-pane -D 2
bind -r K resize-pane -U 2
bind -r L resize-pane -R 2

# ==========================
# ===   Window/Pane     ===
# ==========================
set -g base-index 1
set -g pane-base-index 1
set-window-option -g pane-base-index 1
set-option -g renumber-windows on

# ==========================
# ===    Status bar     ===
# ==========================
# Status bar customization
set -g status-position bottom  # Ensure status bar is at the bottom
set -g status-interval 1
set -g status-justify left

# Increase status bar lengths to prevent overlap
set -g status-right-length 200  # Increased from 100
set -g status-left-length 150   # Increased from 100

# Theme
set -g @plugin 'catppuccin/tmux'
set -g @catppuccin_flavour 'mocha'

# Window customization
set -g @catppuccin_window_left_separator ""
set -g @catppuccin_window_right_separator " "
set -g @catppuccin_window_middle_separator " █"
set -g @catppuccin_window_number_position "right"
set -g @catppuccin_window_default_fill "number"
set -g @catppuccin_window_default_text "#W"
set -g @catppuccin_window_current_fill "number"
set -g @catppuccin_window_current_text "#W"

# Status modules configuration
set -g @catppuccin_status_modules_right "application session date_time cpu battery"
set -g @catppuccin_status_modules_left "directory"

# Module customization
set -g @catppuccin_directory_text "󰉋 #{pane_current_path}"
set -g @catppuccin_date_time_text "󰃰 %Y-%m-%d 󰥔 %H:%M"
set -g @catppuccin_cpu_text "󰍛 CPU: #{cpu_percentage}"
set -g @catppuccin_battery_text "󰂄 Batt: #{battery_percentage}"

# Status bar separators
set -g @catppuccin_status_left_separator  ""
set -g @catppuccin_status_right_separator ""
set -g @catppuccin_status_fill "icon"
set -g @catppuccin_status_connect_separator "yes"

# ==========================
# ===     Pluins       ===
# ==========================
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'christoomey/vim-tmux-navigator'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'fcsonline/tmux-thumbs'
set -g @plugin 'sainnhe/tmux-fzf'
set -g @plugin 'tmux-plugins/tmux-cpu'

# Initialize TMUX plugin manager
run '~/.config/tmux/plugins/tpm/tpm'
EOF

# Reload tmux configuration
info "Reloading tmux configuration..."
tmux source ~/.config/tmux/tmux.conf

# Install tmux plugins
info "Installing tmux plugins..."
~/.config/tmux/plugins/tpm/bin/install_plugins

info "tmux setup complete! Restart tmux to see the changes."
