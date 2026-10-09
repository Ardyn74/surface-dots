#!/usr/bin/env bash
set -euo pipefail

# Choose your theme style: "stellarium" or "pixel"
LOCK_THEME="stellarium"

GREEN="\e[32m"; BLUE="\e[34m"; YELLOW="\e[33m"; RED="\e[31m"; RESET="\e[0m"
log() { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

if [ "$EUID" -eq 0 ]; then
    err "Do NOT run as root. Run as standard user with sudo permissions."
fi

# 1. Base System Updates & Hardware Permissions
log "Updating package database and setting up user permissions..."
sudo pacman -Syu --needed --noconfirm
sudo usermod -aG video,input "$USER"

# 2. Install Official Dependencies (System, Hyprland, Audio, SDDM, Qt)
log "Installing dependencies from official repositories..."
sudo pacman -S --needed --noconfirm \
    hyprland hypridle hyprlock hyprpicker quickshell awww \
    xdg-utils xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    polkit-gnome sddm networkmanager nm-connection-editor bluez bluez-utils blueman \
    upower webkit2gtk-4.1 dunst rofi kitty thunar firefox mpv zathura fastfetch starship \
    qt6ct kvantum papirus-icon-theme qt6-5compat qt6-svg qqc2-desktop-style \
    qt5-declarative qt5-quickcontrols2 qt5-svg qt5-graphicaleffects \
    pipewire pipewire-pulse wireplumber libpulse pamixer pavucontrol playerctl brightnessctl \
    libnotify wl-clipboard grim slurp swappy vdirsyncer khal curl jq pacman-contrib \
    ttf-nerd-fonts-symbols ttf-jetbrains-mono-nerd git base-devel

# 3. Ensure AUR Helper (paru) and AUR Packages
if ! command -v paru &>/dev/null; then
    log "Installing paru..."
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
    rm -rf /tmp/paru
fi

log "Installing AUR packages and fonts..."
paru -S --needed --noconfirm \
    grimblast-git \
    ttf-cm-unicode \
    evercal \
    inter-font \
    ttf-plus-jakarta-sans

# Install Manrope fonts directly to avoid broken AUR download links
log "Installing Manrope fonts manually..."
sudo mkdir -p /usr/local/share/fonts/manrope
sudo curl -sL "https://github.com/sharanda/manrope/raw/master/fonts/ttf/Manrope-Regular.ttf" -o /usr/local/share/fonts/manrope/Manrope-Regular.ttf
sudo curl -sL "https://github.com/sharanda/manrope/raw/master/fonts/ttf/Manrope-Bold.ttf" -o /usr/local/share/fonts/manrope/Manrope-Bold.ttf
sudo curl -sL "https://github.com/sharanda/manrope/raw/master/fonts/ttf/Manrope-Medium.ttf" -o /usr/local/share/fonts/manrope/Manrope-Medium.ttf
sudo curl -sL "https://github.com/sharanda/manrope/raw/master/fonts/ttf/Manrope-SemiBold.ttf" -o /usr/local/share/fonts/manrope/Manrope-SemiBold.ttf
sudo fc-cache -fv > /dev/null

# 4. Locate surface-dots files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/.config" ]; then
    REPO_DIR="$SCRIPT_DIR"
    log "Using local repository at $REPO_DIR"
else
    REPO_DIR="/tmp/surface-dots"
    rm -rf "$REPO_DIR"
    log "Cloning repository..."
    git clone --depth=1 https://github.com/Ardyn74/surface-dots.git "$REPO_DIR"
fi

# 5. Deploy Configurations
log "Deploying user configurations..."
mkdir -p ~/.config ~/.local/bin ~/.icons

# Copy all .config trees
cp -r "$REPO_DIR/.config/"* ~/.config/

# Ensure no default hyprland.conf overrides hyprland.lua
rm -f ~/.config/hypr/hyprland.conf

# Patch hardcoded /home/snes paths across all config files
log "Patching hardcoded paths to $HOME..."
grep -rl "/home/snes" ~/.config/ 2>/dev/null | while read -r file; do
    sed -i "s|/home/snes|$HOME|g" "$file" 2>/dev/null || true
done

# Ensure all scripts have execute permissions
find ~/.config/hypr/scripts ~/.config/quickshell/utils ~/.config/rofi -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

# 6. Configure Lock Screen (Hyprlock & Hypridle)
log "Configuring Hyprlock theme: $LOCK_THEME..."
cp "$REPO_DIR/.config/hypr/hyprlock/$LOCK_THEME/hyprlock.conf" ~/.config/hypr/hyprlock.conf
cp "$REPO_DIR/.config/hypr/hyprlock/$LOCK_THEME/background.jpg" ~/.config/hypr/background.jpg
cp "$REPO_DIR/.config/hypr/hypridle.conf" ~/.config/hypr/hypridle.conf

# 7. Configure SDDM Login Theme
log "Configuring SDDM theme: $LOCK_THEME..."
sudo mkdir -p /usr/share/sddm/themes /etc/sddm.conf.d

if [ "$LOCK_THEME" = "pixel" ]; then
    sudo cp -r "$REPO_DIR/sddm/themes/pixel/no_faceanimation" /usr/share/sddm/themes/pixel
    echo -e "[Theme]\nCurrent=pixel" | sudo tee /etc/sddm.conf.d/theme.conf
else
    sudo cp -r "$REPO_DIR/sddm/themes/stellarium" /usr/share/sddm/themes/stellarium
    echo -e "[Theme]\nCurrent=stellarium" | sudo tee /etc/sddm.conf.d/theme.conf
fi

# 8. Install Custom Cursors
log "Installing Saturnian cursors..."
cp -r "$REPO_DIR/cursor/Saturnian-Day" ~/.icons/
cp -r "$REPO_DIR/cursor/Saturnian-Night" ~/.icons/

# 9. Configure 2.8K 90Hz Display in hyprland.lua
log "Configuring 2880x1800@90Hz display with 1.5x scaling..."
TARGET_OUTPUT="eDP-1"
TARGET_MODE="2880x1800@90"
TARGET_SCALE="1.5"

if [ -f ~/.config/hypr/hyprland.lua ]; then
    # Set 2880x1800 at 90Hz and 1.5x scaling
    sed -i "s|output   = \"eDP-1\"|output   = \"$TARGET_OUTPUT\"|g" ~/.config/hypr/hyprland.lua
    sed -i "s|2256x1504@60|$TARGET_MODE|g" ~/.config/hypr/hyprland.lua
    sed -i "s|scale    = 1,|scale    = $TARGET_SCALE,|g" ~/.config/hypr/hyprland.lua

    # Ensure opening the laptop lid doesn't reset the scale back to 1
    sed -i "s|eDP-1,preferred,auto,1|${TARGET_OUTPUT},preferred,auto,${TARGET_SCALE}|g" ~/.config/hypr/hyprland.lua
fi

# -------------------------------------------------------------------------
# Set ASUS Battery Charge Limit to 80%
# -------------------------------------------------------------------------
log "Configuring ASUS battery charge limit to 80%..."

sudo tee /etc/systemd/system/battery-charge-threshold.service > /dev/null << 'EOF'
[Unit]
Description=Set ASUS battery charge limit to 80%
After=multi-user.target
After=suspend.target
After=hibernate.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for b in /sys/class/power_supply/BAT*; do [ -f "$b/charge_control_end_threshold" ] && echo 80 > "$b/charge_control_end_threshold" || true; done'

[Install]
WantedBy=multi-user.target suspend.target hibernate.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable battery-charge-threshold.service

# 10. Enable System & User Services
log "Enabling systemd daemons..."
sudo systemctl enable NetworkManager.service
sudo systemctl enable bluetooth.service
sudo systemctl enable sddm.service

systemctl --user enable pipewire.service wireplumber.service pipewire-pulse.service 2>/dev/null || true

ok "Setup complete! Type 'sudo reboot' to start your system."