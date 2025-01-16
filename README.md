
# Fish Shell 4.0 Setup Script

This script automates the setup of **Fish Shell 4.0**, **Starship Prompt**, **FastFetch**, and **JetBrains Mono Nerd Font**. It also assigns a unique Pokémon identifier to each system for fun and easy identification.

## ⚠️ Warning

**Before running this script, make sure to back up your existing configuration files.** This script will overwrite the following files:
- `~/.config/fish/config.fish`
- `~/.config/starship.toml`
- `~/.config/fastfetch/config.jsonc`

I am **not responsible** for any data loss, misconfigurations, or issues that may arise from running this script. Use it at your own risk.

## Features

- **Fish Shell 4.0**: Installs the latest Fish Shell with modern features.
- **Starship Prompt**: Configures a fast, customizable, and beautiful shell prompt.
- **FastFetch**: Displays system information with style.
- **JetBrains Mono Nerd Font**: Installs a developer-friendly monospaced font with Nerd Font icons.
- **Pokémon Identifier**: Assigns a unique Pokémon to each system for fun and identification.

## Requirements

- **Bash**: The script is written in Bash and requires a Bash-compatible shell.
- **curl**: Used to download files.
- **unzip**: Used to extract downloaded font files.
- **git**: Used to clone repositories (e.g., FastFetch).
- **Rust**: Required for building `pokeget` and other tools.
- **pokeget**: A CLI tool to fetch Pokémon information.

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/fish-shell-setup.git
   cd fish-shell-setup
   ```

2. Make the script executable:
   ```bash
   chmod +x setup-fish-4.sh
   ```

3. Run the script:
   ```bash
   ./setup-fish-4.sh
   ```

4. Restart your terminal or log out and log back in to apply the changes.

## Configuration Files

- **Fish Shell**: `~/.config/fish/config.fish`
- **Starship Prompt**: `~/.config/starship.toml`
- **FastFetch**: `~/.config/fastfetch/config.jsonc`
- **Pokémon Identifier**: `~/.pokeid`

## Customization

- **Pokémon Identifier**: The script assigns a unique Pokémon to each system. You can manually edit `~/.pokeid` to change the Pokémon.
- **FastFetch**: Customize the system information displayed by editing `~/.config/fastfetch/config.jsonc`.
- **Starship Prompt**: Customize the prompt by editing `~/.config/starship.toml`.

## Troubleshooting

- **Font Issues**: Ensure your terminal emulator supports Nerd Fonts and has JetBrains Mono Nerd Font selected.
- **Pokémon Not Found**: If `pokeget` fails to fetch a Pokémon, ensure it is installed and up to date.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

Enjoy your new Fish Shell setup! 🐟✨
