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
    ttf-inter \
    ttf-manrope \
    ttf-plus-jakarta-sans

# 4. Clone surface-dots
REPO_DIR="/tmp/surface-dots"
rm -rf "$REPO_DIR"
log "Cloning surface-dots repository..."
git clone --depth=1 https://github.com/snes19xx/surface-dots.git "$REPO_DIR"

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

# 9. Auto-Detect Laptop Screen & Patch hyprland.lua
log "Detecting laptop display..."
INTERNAL_MONITOR=$(ls /sys/class/drm/ | grep -E '^card[0-9]+-eDP-[0-9]+' | sed 's/^card[0-9]*-//' | head -n 1 || echo "eDP-1")

if [ -f "/sys/class/drm/card0-$INTERNAL_MONITOR/modes" ]; then
    DETECTED_RES=$(head -n 1 "/sys/class/drm/card0-$INTERNAL_MONITOR/modes")
else
    DETECTED_RES="1920x1080"
fi

SCALE="1"
HEIGHT=$(echo "$DETECTED_RES" | cut -d'x' -f2)
if [ "$HEIGHT" -gt 1200 ]; then
    SCALE="1.25"
fi

log "Applying monitor settings ($INTERNAL_MONITOR: $DETECTED_RES@60, scale $SCALE)..."
sed -i "s|output   = \"eDP-1\"|output   = \"$INTERNAL_MONITOR\"|g" ~/.config/hypr/hyprland.lua
sed -i "s|2256x1504@60|${DETECTED_RES}@60|g" ~/.config/hypr/hyprland.lua
sed -i "s|scale    = 1,|scale    = $SCALE,|g" ~/.config/hypr/hyprland.lua

# 10. Enable System & User Services
log "Enabling systemd daemons..."
sudo systemctl enable NetworkManager.service
sudo systemctl enable bluetooth.service
sudo systemctl enable sddm.service

systemctl --user enable pipewire.service wireplumber.service pipewire-pulse.service 2>/dev/null || true

ok "Setup complete! Type 'sudo reboot' to start your system."
