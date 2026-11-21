# Arch Linux Dotfiles & System Configuration

Personal Arch Linux desktop and system configuration maintained by **Thomas Lableigne** (`TLableigne`). Built around a Wayland tiling workflow (Hyprland), custom shell tooling, and multi-identity Git governance.

## Architecture & Stack

### Window Manager & Desktop
* **Hyprland (Wayland):** Modular configuration (based on the `end4` / illogical-impulse ecosystem) with custom animations, window rules, and dynamic theming.
* **Quickshell & Wlogout:** Interactive status bar, widgets, system controls, and graphical session menu.
* **Dynamic Profiles (`hyprprofile`):** Custom switcher managing wallpaper sets, color schemes (`looks/`), and layout profiles.

### Terminal & Shell
* **Kitty:** GPU-accelerated terminal emulator configured with custom color schemes.
* **Fish Shell:** Primary interactive shell enhanced with custom utility functions (`create-dual-repo`, `power`, `info`, `findall`).
* **Starship:** Minimalist, fast cross-shell prompt.

### Bootloader & System
* **GRUB:** Custom 1440p Cyberpunk 2077 HUD bootloader theme (`cyberpunk-custom`) with compiled `.pf2` fonts and vector icons.
* **Pacman:** Custom package manager configuration (`/etc/pacman.conf`).
* **Local Binaries (`~/.local/bin`):** Utility scripts including `hyprprofile`, `hyprprofile-waybar`, `arrpc-gamefix`, and `ghub4linux`.

### Multi-Identity Git Workflow
* Dynamic profile switching using `includeIf` conditional directives and dedicated SSH host aliases across three contexts: Personal (`NightGx`), Professional (`TLableigne`), and University (`gitlab-iut`).

## Repository Structure

```text
.
├── bin/          # Custom utility scripts (~/.local/bin)
├── fish/         # Fish shell configuration, functions & conf.d
├── git/          # Global Git config and conditional identity rules
├── grub/         # /etc/default/grub and 1440p Cyberpunk GRUB theme
├── looks/        # Theme look definitions and color patches
├── profiles/     # Hyprland & Quickshell profile modules
├── system/       # System-level configurations (pacman.conf)
├── wallpapers/   # Desktop backgrounds and thumbnails
└── install.sh    # Profile deployment and sync script
```

## Deployment

1. **Clone the repository:**
   ```bash
   git clone git@github.com:TLableigne/arch-dotfiles.git ~/Projects/config_arch
   cd ~/Projects/config_arch
   ```

2. **Deploy user configurations:**
   ```bash
   ./install.sh
   cp -r fish/* ~/.config/fish/
   cp git/.gitconfig* ~/
   cp bin/* ~/.local/bin/
   ```

3. **Apply system-level configurations (GRUB & Pacman):**
   ```bash
   sudo cp grub/grub /etc/default/grub
   sudo cp -r grub/cyberpunk-custom /boot/grub/themes/
   sudo grub-mkconfig -o /boot/grub/grub.cfg
   sudo cp system/pacman.conf /etc/pacman.conf
   ```