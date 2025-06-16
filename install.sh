#!/bin/bash

# Arch Linux + Caelestia Rice Installation Script
# This script automates the installation of Arch Linux with the Caelestia desktop setup
# Make sure to run this on a fresh Arch installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Get user input
read -p "Enter your username: " USERNAME
read -p "Enter your hostname: " HOSTNAME
read -s -p "Enter your password: " PASSWORD
echo

print_status "Starting Arch Linux + Caelestia Rice setup..."

# Update system
print_status "Updating system..."
sudo pacman -Syu --noconfirm

# Install base packages
print_status "Installing base packages..."
sudo pacman -S --noconfirm base-devel git wget curl unzip

# Install AUR helper (yay)
print_status "Installing yay AUR helper..."
if ! command -v yay &> /dev/null; then
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
fi

# Install Hyprland and dependencies
print_status "Installing Hyprland and dependencies..."
yay -S --noconfirm \
    hyprland \
    hyprpaper \
    hyprlock \
    hypridle \
    xdg-desktop-portal-hyprland \
    waybar \
    rofi-wayland \
    dunst \
    alacritty \
    thunar \
    thunar-volman \
    thunar-archive-plugin \
    file-roller \
    firefox \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    pavucontrol \
    brightnessctl \
    grim \
    slurp \
    wl-clipboard \
    cliphist \
    polkit-gnome \
    qt5-wayland \
    qt6-wayland \
    nwg-look \
    ttf-jetbrains-mono-nerd \
    ttf-font-awesome \
    ttf-fira-code \
    noto-fonts \
    noto-fonts-emoji

# Install Quickshell (required for Caelestia)
print_status "Installing Quickshell..."
yay -S --noconfirm quickshell-git

# Create necessary directories
print_status "Creating configuration directories..."
mkdir -p ~/.config/{hypr,quickshell,waybar,rofi,dunst,alacritty,gtk-3.0,gtk-4.0}
mkdir -p ~/.local/share/themes
mkdir -p ~/.local/share/icons
mkdir -p ~/Pictures/wallpapers

# Install Caelestia scripts
print_status "Installing Caelestia scripts..."
if [ ! -d "~/.local/bin" ]; then
    mkdir -p ~/.local/bin
fi

cd /tmp
git clone https://github.com/caelestia-dots/scripts.git caelestia-scripts
cd caelestia-scripts
chmod +x caelestia
sudo cp caelestia /usr/local/bin/
cd ~

# Install Caelestia shell configuration
print_status "Installing Caelestia shell configuration..."
cd ~/.config/quickshell
git clone https://github.com/caelestia-dots/shell.git caelestia

# Install additional theme components
print_status "Installing theme components..."
yay -S --noconfirm \
    catppuccin-gtk-theme-mocha \
    catppuccin-cursors-mocha \
    papirus-icon-theme

# Create basic Hyprland config
print_status "Creating basic Hyprland configuration..."
cat > ~/.config/hypr/hyprland.conf << 'EOF'
# Caelestia Hyprland Configuration

# Monitor configuration
monitor=,preferred,auto,1

# Execute your favorite apps at launch
exec-once = waybar
exec-once = hyprpaper
exec-once = dunst
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = qs -c caelestia

# Environment variables
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt5ct

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = no
    }
    sensitivity = 0
}

# General settings
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
    allow_tearing = false
}

# Decoration
decoration {
    rounding = 10
    blur {
        enabled = true
        size = 3
        passes = 1
    }
    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

# Animations
animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = borderangle, 1, 8, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# Layouts
dwindle {
    pseudotile = yes
    preserve_split = yes
}

master {
    new_is_master = true
}

# Key bindings
$mainMod = SUPER

bind = $mainMod, Q, exec, alacritty
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, thunar
bind = $mainMod, V, togglefloating,
bind = $mainMod, R, exec, rofi -show drun
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,

# Move focus
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Switch workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Move active window to workspace
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

# Mouse bindings
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Volume and brightness controls
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bind = , XF86MonBrightnessUp, exec, brightnessctl set 10%+
bind = , XF86MonBrightnessDown, exec, brightnessctl set 10%-

# Screenshot
bind = $mainMod, PRINT, exec, grim -g "$(slurp)" - | wl-copy
EOF

# Create basic waybar config
print_status "Creating Waybar configuration..."
mkdir -p ~/.config/waybar
cat > ~/.config/waybar/config << 'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,
    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["hyprland/window"],
    "modules-right": ["pulseaudio", "network", "cpu", "memory", "temperature", "backlight", "battery", "clock", "tray"],
    "hyprland/workspaces": {
        "disable-scroll": true,
        "all-outputs": true,
        "format": "{icon}",
        "format-icons": {
            "1": "",
            "2": "",
            "3": "",
            "4": "",
            "5": "",
            "urgent": "",
            "focused": "",
            "default": ""
        }
    },
    "tray": {
        "spacing": 10
    },
    "clock": {
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>",
        "format-alt": "{:%Y-%m-%d}"
    },
    "cpu": {
        "format": "{usage}% ",
        "tooltip": false
    },
    "memory": {
        "format": "{}% "
    },
    "battery": {
        "states": {
            "warning": 30,
            "critical": 15
        },
        "format": "{capacity}% {icon}",
        "format-charging": "{capacity}% ",
        "format-plugged": "{capacity}% ",
        "format-alt": "{time} {icon}",
        "format-icons": ["", "", "", "", ""]
    },
    "network": {
        "format-wifi": "{essid} ({signalStrength}%) ",
        "format-ethernet": "{ipaddr}/{cidr} ",
        "tooltip-format": "{ifname} via {gwaddr} ",
        "format-linked": "{ifname} (No IP) ",
        "format-disconnected": "Disconnected ⚠",
        "format-alt": "{ifname}: {ipaddr}/{cidr}"
    },
    "pulseaudio": {
        "format": "{volume}% {icon} {format_source}",
        "format-bluetooth": "{volume}% {icon} {format_source}",
        "format-bluetooth-muted": " {icon} {format_source}",
        "format-muted": " {format_source}",
        "format-source": "{volume}% ",
        "format-source-muted": "",
        "format-icons": {
            "headphone": "",
            "hands-free": "",
            "headset": "",
            "phone": "",
            "portable": "",
            "car": "",
            "default": ["", "", ""]
        },
        "on-click": "pavucontrol"
    }
}
EOF

cat > ~/.config/waybar/style.css << 'EOF'
* {
    border: none;
    border-radius: 0;
    font-family: "JetBrains Mono Nerd Font";
    font-size: 13px;
    min-height: 0;
}

window#waybar {
    background-color: rgba(43, 48, 59, 0.5);
    border-bottom: 3px solid rgba(100, 114, 125, 0.5);
    color: #ffffff;
    transition-property: background-color;
    transition-duration: .5s;
}

button {
    box-shadow: inset 0 -3px transparent;
    border: none;
    border-radius: 0;
}

#workspaces button {
    padding: 0 5px;
    background-color: transparent;
    color: #ffffff;
}

#workspaces button:hover {
    background: rgba(0, 0, 0, 0.2);
}

#workspaces button.focused {
    background-color: #64727D;
    box-shadow: inset 0 -3px #ffffff;
}

#clock,
#battery,
#cpu,
#memory,
#temperature,
#backlight,
#network,
#pulseaudio,
#tray {
    padding: 0 10px;
    color: #ffffff;
}
EOF

# Create alacritty config
print_status "Creating Alacritty configuration..."
cat > ~/.config/alacritty/alacritty.yml << 'EOF'
window:
  opacity: 0.9
  padding:
    x: 10
    y: 10

font:
  normal:
    family: "JetBrains Mono Nerd Font"
    style: Regular
  bold:
    family: "JetBrains Mono Nerd Font"
    style: Bold
  italic:
    family: "JetBrains Mono Nerd Font"
    style: Italic
  size: 11

colors:
  primary:
    background: '#1e1e2e'
    foreground: '#cdd6f4'
  cursor:
    text: '#1e1e2e'
    cursor: '#f5e0dc'
  normal:
    black: '#45475a'
    red: '#f38ba8'
    green: '#a6e3a1'
    yellow: '#f9e2af'
    blue: '#89b4fa'
    magenta: '#f5c2e7'
    cyan: '#94e2d5'
    white: '#bac2de'
  bright:
    black: '#585b70'
    red: '#f38ba8'
    green: '#a6e3a1'
    yellow: '#f9e2af'
    blue: '#89b4fa'
    magenta: '#f5c2e7'
    cyan: '#94e2d5'
    white: '#a6adc8'
EOF

# Enable services
print_status "Enabling services..."
sudo systemctl enable --now pipewire
sudo systemctl enable --now pipewire-pulse
sudo systemctl enable --now wireplumber

# Add user to necessary groups
print_status "Adding user to necessary groups..."
sudo usermod -aG audio,video,input,wheel $USERNAME

# Install additional rice components
print_status "Installing additional rice components..."
yay -S --noconfirm \
    cava \
    neofetch \
    htop \
    ranger \
    fzf \
    zsh \
    oh-my-zsh-git

# Setup zsh
print_status "Setting up zsh..."
chsh -s /usr/bin/zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Create .zshrc
cat > ~/.zshrc << 'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Custom prompt
autoload -U colors && colors
PS1="%{$fg[cyan]%}%n%{$reset_color%}@%{$fg[blue]%}%m %{$fg[yellow]%}%~ %{$reset_color%}%% "

# Neofetch on terminal start
neofetch
EOF

# Download some wallpapers
print_status "Downloading wallpapers..."
cd ~/Pictures/wallpapers
wget -O wallpaper1.jpg "https://w.wallhaven.cc/full/6o/wallhaven-6oxgqm.jpg" 2>/dev/null || true
wget -O wallpaper2.jpg "https://w.wallhaven.cc/full/pk/wallhaven-pkd6q7.jpg" 2>/dev/null || true

# Create hyprpaper config
cat > ~/.config/hypr/hyprpaper.conf << 'EOF'
preload = ~/Pictures/wallpapers/wallpaper1.jpg
wallpaper = ,~/Pictures/wallpapers/wallpaper1.jpg
splash = false
EOF

# Final setup
print_status "Running final setup..."
# Run caelestia install script
caelestia install shell 2>/dev/null || print_warning "Caelestia install script failed, continuing..."

# Set GTK theme
mkdir -p ~/.config/gtk-3.0
cat > ~/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Catppuccin-Mocha-Standard-Blue-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Cantarell 11
gtk-cursor-theme-name=catppuccin-mocha-dark-cursors
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_BOTH
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
EOF

print_success "Installation completed!"
print_status "Please reboot your system and log into Hyprland"
print_status "After login, run 'qs -c caelestia' to start the Caelestia shell"
print_warning "Make sure to select Hyprland from your display manager"

echo
print_status "Key bindings:"
echo "  Super + Q: Terminal"
echo "  Super + R: Application launcher"
echo "  Super + E: File manager"
echo "  Super + C: Close window"
echo "  Super + M: Exit Hyprland"
echo "  Super + 1-0: Switch workspaces"
echo "  Super + Shift + 1-0: Move window to workspace"
echo

print_success "Enjoy your new Caelestia rice setup!"
