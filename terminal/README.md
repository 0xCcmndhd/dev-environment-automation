# Terminal Automation Suite

This directory contains scripts to rapidly configure a modern, productive terminal environment on a new Debian/Ubuntu system.

## Scripts

-   `setup-terminal.sh`: The main setup script. This installs and configures Fish Shell 4.0, Starship Prompt, FastFetch, Nerd Fonts, and other core terminal utilities.
-   `setup-tmux.sh`: An optional but highly recommended script to set up `tmux` (a terminal multiplexer) with a beautiful Catppuccin theme, ergonomic keybindings, and powerful productivity plugins.

## Usage

1.  Run `setup-terminal.sh` first to establish the base environment.
2.  After logging back in, run `setup-tmux.sh` to add the terminal multiplexing capabilities.
