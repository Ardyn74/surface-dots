#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
LOCK_THEME="stellarium"          # SDDM & Hyprlock theme ("stellarium" or "pixel")
TARGET_OUTPUT="eDP-1"            # Laptop internal display
TARGET_MODE="2880x1800@90"       # Native 2.8K 90Hz resolution
TARGET_SCALE="1.5"               # Optimal scale for 16:10 2.8K screen

GREEN="\e[32m"; BLUE="\e[34m"; YELLOW="\e[33m"; RED="\e[31m"; RESET="\e[0m"
log() { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

# Sanity Check
if [ "$EUID" -eq 0 ]; then
    err "Do NOT run this script as root. Run as standard user with sudo permissions."
fi

# 1. Update Package Database & Set Hardware Permissions
log "Updating package database and granting hardware permissions..."
sudo pacman -Syu --needed --noconfirm
sudo usermod -aG video,input "$USER"

# 2. Install Official Dependencies
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
    ttf-nerd-fonts-symbols ttf-jetbrains-mono-nerd inter-font git base-devel

# 3. Ensure AUR Helper (paru) & AUR Packages
if ! command -v paru &>/dev/null; then
    log "Installing paru..."
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
    rm -rf /tmp/paru
fi

log "Installing AUR packages and fonts (conflict-free)..."
paru -S --needed --noconfirm \
    grimblast-git \
    ttf-cm-unicode \
    evercal \
    otf-manrope \
    ttf-plus-jakarta-sans

# 4. Locate surface-dots Repository Files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/.config" ]; then
    REPO_DIR="$SCRIPT_DIR"
    log "Using local repository files from $REPO_DIR"
else
    REPO_DIR="/tmp/surface-dots"
    rm -rf "$REPO_DIR"
    log "Cloning repository..."
    git clone --depth=1 https://github.com/Ardyn74/surface-dots.git "$REPO_DIR"
fi

# 5. Create Core Directories & State Paths
log "Creating system directories, cache, and state paths..."
mkdir -p ~/.config ~/.local/bin ~/.icons ~/.local/share/icons ~/.themes
mkdir -p ~/.cache/quickshell ~/.local/state/theme

# Copy all .config trees
log "Deploying user configurations to ~/.config..."
cp -r "$REPO_DIR/.config/"* ~/.config/

# Ensure no default hyprland.conf overrides hyprland.lua
rm -f ~/.config/hypr/hyprland.conf

# Patch author's hardcoded /home/snes paths to the active user's $HOME
log "Patching hardcoded paths to $HOME..."
grep -rl "/home/snes" ~/.config/ 2>/dev/null | while read -r file; do
    sed -i "s|/home/snes|$HOME|g" "$file" 2>/dev/null || true
done

# Initialize Kitty terminal theme state
ln -sf ~/.config/kitty/themes/everforest.conf ~/.local/state/theme/kitty_theme.conf

# Link Kvantum case-sensitivity fallback
ln -s ~/.config/kvantum ~/.config/Kvantum 2>/dev/null || true

# Extract GTK themes into ~/.themes
log "Extracting GTK themes..."
if [ -d ~/.config/gtk-theme ]; then
    tar -xzf ~/.config/gtk-theme/green-dark.tar.gz -C ~/.themes/ 2>/dev/null || true
    tar -xzf ~/.config/gtk-theme/green-light.tar.gz -C ~/.themes/ 2>/dev/null || true
fi

# Make ALL configuration shell scripts executable
find ~/.config -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

# 6. Install Saturnian Cursors (to both ~/.local/share/icons and ~/.icons)
log "Installing Saturnian cursor themes..."
cp -r "$REPO_DIR/cursor/Saturnian-Day" ~/.local/share/icons/ 2>/dev/null || true
cp -r "$REPO_DIR/cursor/Saturnian-Night" ~/.local/share/icons/ 2>/dev/null || true
cp -r "$REPO_DIR/cursor/Saturnian-Day" ~/.icons/ 2>/dev/null || true
cp -r "$REPO_DIR/cursor/Saturnian-Night" ~/.icons/ 2>/dev/null || true

# 7. Configure Lock Screen (Hyprlock & Hypridle)
log "Configuring Hyprlock theme: $LOCK_THEME..."
cp "$REPO_DIR/.config/hypr/hyprlock/$LOCK_THEME/hyprlock.conf" ~/.config/hypr/hyprlock.conf
cp "$REPO_DIR/.config/hypr/hyprlock/$LOCK_THEME/background.jpg" ~/.config/hypr/background.jpg
cp "$REPO_DIR/.config/hypr/hypridle.conf" ~/.config/hypr/hypridle.conf
# Fix username in hyprlock welcome text
sed -i "s|>snes<|>$USER<|g" ~/.config/hypr/hyprlock.conf 2>/dev/null || true

# 8. Configure SDDM Login Theme & FIX THE "snes" USERNAME BUG
log "Configuring SDDM theme: $LOCK_THEME..."
sudo mkdir -p /usr/share/sddm/themes /etc/sddm.conf.d

if [ "$LOCK_THEME" = "pixel" ]; then
    sudo cp -r "$REPO_DIR/sddm/themes/pixel/no_faceanimation" /usr/share/sddm/themes/pixel
    echo -e "[Theme]\nCurrent=pixel" | sudo tee /etc/sddm.conf.d/theme.conf
    sudo sed -i "s|\"snes\"|\"$USER\"|g" /usr/share/sddm/themes/pixel/Main.qml 2>/dev/null || true
else
    sudo cp -r "$REPO_DIR/sddm/themes/stellarium" /usr/share/sddm/themes/stellarium
    echo -e "[Theme]\nCurrent=stellarium" | sudo tee /etc/sddm.conf.d/theme.conf
    # Patch hardcoded "snes" in Stellarium so it authenticates as YOUR user
    sudo sed -i "s|\"snes\"|\"$USER\"|g" /usr/share/sddm/themes/stellarium/Login.qml 2>/dev/null || true
    sudo sed -i "s|\"snes\"|\"$USER\"|g" /usr/share/sddm/themes/stellarium/Main.qml 2>/dev/null || true
fi

# 9. Configure 2.8K 90Hz Display & Prevent GDK Double-Scaling
log "Configuring 2880x1800@90Hz display with 1.5x scaling in hyprland.lua..."
if [ -f ~/.config/hypr/hyprland.lua ]; then
    # Set display output, 90Hz refresh rate, and 1.5x scale
    sed -i "s|output   = \"eDP-1\"|output   = \"$TARGET_OUTPUT\"|g" ~/.config/hypr/hyprland.lua
    sed -i "s|2256x1504@60|$TARGET_MODE|g" ~/.config/hypr/hyprland.lua
    sed -i "s|scale    = 1,|scale    = $TARGET_SCALE,|g" ~/.config/hypr/hyprland.lua

    # Prevent lid switch from resetting scale to 1 on lid open
    sed -i "s|eDP-1,preferred,auto,1|${TARGET_OUTPUT},preferred,auto,${TARGET_SCALE}|g" ~/.config/hypr/hyprland.lua

    # Set GDK_SCALE to 1 to prevent GTK apps from double-scaling (1.5 * 2 = 3x)
    sed -i 's|hl\.env("GDK_SCALE",       "2")|hl.env("GDK_SCALE",       "1")|g' ~/.config/hypr/hyprland.lua
fi

# 10. Configure ASUS Battery Charge Limit (80%)
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

# 11. Enable System & User Daemons
log "Enabling systemd daemons..."
sudo systemctl enable NetworkManager.service
sudo systemctl enable bluetooth.service
sudo systemctl enable sddm.service

systemctl --user enable pipewire.service wireplumber.service pipewire-pulse.service 2>/dev/null || true

ok "Setup completed successfully! Run 'sudo reboot' to launch your desktop."
