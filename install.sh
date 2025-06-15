#!/bin/bash
#
# Arch Linux First Dual-Boot Installer with Caelestia Shell
# This version installs Arch Linux first, then allows Windows installation later
# WARNING: This script modifies disk partitions. Use at your own risk!
# Always backup important data before running.
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

confirm() {
    read -p "$(echo -e ${YELLOW}$1${NC}) [y/N]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    error "Don't run this script as root! Run as regular user, it will ask for sudo when needed."
fi

# Check if we're in the Arch Linux live environment
if ! grep -q "archiso" /proc/cmdline 2>/dev/null; then
    warn "This script is designed for the Arch Linux live environment."
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Arch Linux First Dual-Boot Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo "This script will install Arch Linux first, leaving space for Windows later."
echo "It will:"
echo "• Create a proper EFI partition"
echo "• Install Arch Linux with Hyprland + Caelestia Shell"
echo "• Reserve space for Windows installation"
echo "• Set up GRUB to detect Windows when you install it later"
echo
warn "IMPORTANT: This will erase the selected disk completely!"
warn "Make sure you have backups of any important data."
echo

if ! confirm "Do you want to continue?"; then
    exit 0
fi

# Step 1: Analyze current disk layout
log "Analyzing disk layout..."
echo
lsblk -f
echo

# Get available disks
DISKS=($(lsblk -dpno NAME | grep -E "sd[a-z]|nvme[0-9]n[0-9]" | grep -v "loop"))
echo "Available disks:"
for i in "${!DISKS[@]}"; do
    SIZE=$(lsblk -dpno SIZE "${DISKS[$i]}")
    echo "$((i+1)). ${DISKS[$i]} ($SIZE)"
done
echo

read -p "Select the disk to install on (1-${#DISKS[@]}): " DISK_CHOICE
SELECTED_DISK="${DISKS[$((DISK_CHOICE-1))]}"

if [[ -z "$SELECTED_DISK" ]]; then
    error "Invalid disk selection"
fi

log "Selected disk: $SELECTED_DISK"
DISK_SIZE=$(lsblk -dpno SIZE "$SELECTED_DISK" | tr -d ' ')

warn "This will COMPLETELY ERASE $SELECTED_DISK ($DISK_SIZE)"
if ! confirm "Are you absolutely sure?"; then
    exit 1
fi

# Step 2: Get installation parameters
echo
log "Configuration setup..."

echo "Partition size recommendations for dual boot:"
echo "• EFI: 512MB (will be created automatically)"
echo "• Linux Root: 40-80GB (for OS and programs)"
echo "• Linux Home: 20-40GB (for your files)"
echo "• Windows: Rest of disk (will be left as free space)"
echo

read -p "Enter Linux root partition size (e.g., 60G): " ROOT_SIZE
read -p "Enter Linux home partition size (e.g., 30G): " HOME_SIZE
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -s -p "Enter password for $USERNAME: " USER_PASSWORD
echo
read -s -p "Enter root password: " ROOT_PASSWORD
echo
echo

# Validate inputs
if [[ -z "$ROOT_SIZE" || -z "$HOME_SIZE" || -z "$HOSTNAME" || -z "$USERNAME" || -z "$USER_PASSWORD" || -z "$ROOT_PASSWORD" ]]; then
    error "All fields are required"
fi

# Step 3: Create partition table and partitions
log "Creating partition table and partitions..."
warn "Erasing disk and creating new partition table..."

# Unmount any existing partitions
sudo umount ${SELECTED_DISK}* 2>/dev/null || true

# Create GPT partition table
sudo parted -s "$SELECTED_DISK" mklabel gpt

# Create partitions
log "Creating EFI partition (512MB)..."
sudo parted -s "$SELECTED_DISK" mkpart "EFI" fat32 1MiB 513MiB
sudo parted -s "$SELECTED_DISK" set 1 esp on

log "Creating Linux root partition ($ROOT_SIZE)..."
sudo parted -s "$SELECTED_DISK" mkpart "Linux-Root" ext4 513MiB $((513 + ${ROOT_SIZE%G} * 1024))MiB

log "Creating Linux home partition ($HOME_SIZE)..."
START_HOME=$((513 + ${ROOT_SIZE%G} * 1024))
END_HOME=$((START_HOME + ${HOME_SIZE%G} * 1024))
sudo parted -s "$SELECTED_DISK" mkpart "Linux-Home" ext4 ${START_HOME}MiB ${END_HOME}MiB

log "Creating swap partition (4GB)..."
sudo parted -s "$SELECTED_DISK" mkpart "Linux-Swap" linux-swap ${END_HOME}MiB $((END_HOME + 4096))MiB

log "The rest of the disk is left free for Windows installation later"

# Wait for kernel to recognize partitions
sleep 2
sudo partprobe "$SELECTED_DISK"
sleep 2

# Determine partition naming scheme
if [[ "$SELECTED_DISK" == *"nvme"* ]]; then
    EFI_PART="${SELECTED_DISK}p1"
    ROOT_PART="${SELECTED_DISK}p2"
    HOME_PART="${SELECTED_DISK}p3"
    SWAP_PART="${SELECTED_DISK}p4"
else
    EFI_PART="${SELECTED_DISK}1"
    ROOT_PART="${SELECTED_DISK}2"
    HOME_PART="${SELECTED_DISK}3"
    SWAP_PART="${SELECTED_DISK}4"
fi

log "Partition layout:"
echo "  EFI:  $EFI_PART (512MB)"
echo "  Root: $ROOT_PART ($ROOT_SIZE)"
echo "  Home: $HOME_PART ($HOME_SIZE)"
echo "  Swap: $SWAP_PART (4GB)"
echo "  Free space reserved for Windows"

# Step 4: Format partitions
log "Formatting partitions..."
sudo mkfs.fat -F32 "$EFI_PART"
sudo mkfs.ext4 -F "$ROOT_PART"
sudo mkfs.ext4 -F "$HOME_PART"
sudo mkswap "$SWAP_PART"

# Step 5: Mount partitions
log "Mounting partitions..."
sudo swapon "$SWAP_PART"
sudo mount "$ROOT_PART" /mnt
sudo mkdir -p /mnt/boot/efi
sudo mkdir -p /mnt/home
sudo mount "$EFI_PART" /mnt/boot/efi
sudo mount "$HOME_PART" /mnt/home

# Step 6: Install base system
log "Updating package database..."
sudo pacman -Sy

log "Installing base system..."
sudo pacstrap /mnt base base-devel linux linux-firmware networkmanager grub efibootmgr os-prober ntfs-3g

# Step 7: Generate fstab
log "Generating fstab..."
sudo genfstab -U /mnt >> /mnt/etc/fstab

# Step 8: Chroot configuration script
log "Creating chroot configuration script..."
sudo tee /mnt/setup_system.sh > /dev/null <<CHROOT_SCRIPT
#!/bin/bash
set -e

# Set timezone (you can change this)
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user
useradd -m -G wheel,audio,video,optical,storage -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configure sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Enable NetworkManager
systemctl enable NetworkManager

# Configure GRUB for dual boot
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
echo "GRUB_TIMEOUT=10" >> /etc/default/grub

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH --recheck

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg

# Install additional packages
pacman -S --noconfirm git vim wget curl firefox

echo "Base system configuration completed!"
CHROOT_SCRIPT

# Step 9: Run chroot configuration
log "Configuring system in chroot..."
sudo arch-chroot /mnt bash /setup_system.sh
sudo rm /mnt/setup_system.sh

# Step 10: Install Hyprland with Caelestia Shell
log "Installing Hyprland with Caelestia Shell desktop environment..."
sudo tee /mnt/install_hyprland.sh > /dev/null <<HYPRLAND_SCRIPT
#!/bin/bash
set -e

# Add multilib repository for some packages
echo "" >> /etc/pacman.conf
echo "[multilib]" >> /etc/pacman.conf
echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf

# Update package database
pacman -Sy

# Install Hyprland and essential packages
pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland kitty thunar \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
    brightnessctl playerctl pamixer grim slurp wl-clipboard \
    ttf-font-awesome ttf-jetbrains-mono noto-fonts noto-fonts-emoji \
    polkit-kde-agent qt5-wayland qt6-wayland \
    sddm rofi-wayland swww dunst waybar

# Enable SDDM
systemctl enable sddm

# Create basic Hyprland config
sudo -u $USERNAME mkdir -p /home/$USERNAME/.config/hypr
sudo -u $USERNAME tee /home/$USERNAME/.config/hypr/hyprland.conf > /dev/null <<EOF
# Hyprland Configuration
monitor=,preferred,auto,auto

# Autostart
exec-once = waybar
exec-once = /usr/lib/polkit-kde-authentication-agent-1
exec-once = swww-daemon
exec-once = dunst

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = false
    }
    sensitivity = 0
}

# General settings
general {
    gaps_in = 8
    gaps_out = 12
    border_size = 2
    col.active_border = rgba(89b4faee) rgba(cba6f7ee) 45deg
    col.inactive_border = rgba(313244aa)
    layout = dwindle
    allow_tearing = false
}

# Decoration
decoration {
    rounding = 12
    
    blur {
        enabled = true
        size = 6
        passes = 2
    }
    
    drop_shadow = true
    shadow_range = 20
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
    
    active_opacity = 0.98
    inactive_opacity = 0.85
}

# Animations
animations {
    enabled = true
    
    bezier = wind, 0.05, 0.9, 0.1, 1.05
    bezier = winIn, 0.1, 1.1, 0.1, 1.1
    bezier = winOut, 0.3, -0.3, 0, 1
    bezier = liner, 1, 1, 1, 1
    
    animation = windows, 1, 6, wind, slide
    animation = windowsIn, 1, 6, winIn, slide
    animation = windowsOut, 1, 5, winOut, slide
    animation = windowsMove, 1, 5, wind, slide
    animation = border, 1, 1, liner
    animation = borderangle, 1, 30, liner, loop
    animation = fade, 1, 10, default
    animation = workspaces, 1, 5, wind
}

# Layout
dwindle {
    pseudotile = true
    preserve_split = true
}

# Window rules
windowrule = float, ^(pavucontrol)$
windowrule = float, ^(blueman-manager)$
windowrule = float, ^(nm-connection-editor)$

# Keybindings
\$mainMod = SUPER

# Applications
bind = \$mainMod, Q, exec, kitty
bind = \$mainMod, W, exec, firefox
bind = \$mainMod, E, exec, thunar
bind = \$mainMod, R, exec, rofi -show drun
bind = \$mainMod, period, exec, rofi -show emoji

# Window management
bind = \$mainMod, C, killactive
bind = \$mainMod, M, exit
bind = \$mainMod, V, togglefloating
bind = \$mainMod, P, pseudo
bind = \$mainMod, J, togglesplit
bind = \$mainMod, F, fullscreen

# Focus movement
bind = \$mainMod, left, movefocus, l
bind = \$mainMod, right, movefocus, r
bind = \$mainMod, up, movefocus, u
bind = \$mainMod, down, movefocus, d

# Workspace switching
bind = \$mainMod, 1, workspace, 1
bind = \$mainMod, 2, workspace, 2
bind = \$mainMod, 3, workspace, 3
bind = \$mainMod, 4, workspace, 4
bind = \$mainMod, 5, workspace, 5
bind = \$mainMod, 6, workspace, 6
bind = \$mainMod, 7, workspace, 7
bind = \$mainMod, 8, workspace, 8
bind = \$mainMod, 9, workspace, 9
bind = \$mainMod, 0, workspace, 10

# Move windows to workspace
bind = \$mainMod SHIFT, 1, movetoworkspace, 1
bind = \$mainMod SHIFT, 2, movetoworkspace, 2
bind = \$mainMod SHIFT, 3, movetoworkspace, 3
bind = \$mainMod SHIFT, 4, movetoworkspace, 4
bind = \$mainMod SHIFT, 5, movetoworkspace, 5
bind = \$mainMod SHIFT, 6, movetoworkspace, 6
bind = \$mainMod SHIFT, 7, movetoworkspace, 7
bind = \$mainMod SHIFT, 8, movetoworkspace, 8
bind = \$mainMod SHIFT, 9, movetoworkspace, 9
bind = \$mainMod SHIFT, 0, movetoworkspace, 10

# Media keys
bind = , XF86AudioRaiseVolume, exec, pamixer -i 5
bind = , XF86AudioLowerVolume, exec, pamixer -d 5
bind = , XF86AudioMute, exec, pamixer -t
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

# Screenshot
bind = \$mainMod, PRINT, exec, grim -g "\$(slurp)" - | wl-copy
bind = , PRINT, exec, grim ~/Pictures/screenshot_\$(date +%Y%m%d_%H%M%S).png

# Mouse bindings
bindm = \$mainMod, mouse:272, movewindow
bindm = \$mainMod, mouse:273, resizewindow
EOF

# Create basic waybar config
sudo -u $USERNAME mkdir -p /home/$USERNAME/.config/waybar
sudo -u $USERNAME tee /home/$USERNAME/.config/waybar/config > /dev/null <<EOF
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,
    
    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["hyprland/window"],
    "modules-right": ["pulseaudio", "network", "cpu", "memory", "temperature", "battery", "clock", "tray"],
    
    "hyprland/workspaces": {
        "disable-scroll": true,
        "all-outputs": true,
        "format": "{name}: {icon}",
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
    
    "temperature": {
        "critical-threshold": 80,
        "format": "{temperatureC}°C {icon}",
        "format-icons": ["", "", ""]
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

# Create waybar style
sudo -u $USERNAME tee /home/$USERNAME/.config/waybar/style.css > /dev/null <<EOF
* {
    border: none;
    border-radius: 0;
    font-family: "JetBrains Mono", monospace;
    font-size: 13px;
    min-height: 0;
}

window#waybar {
    background-color: rgba(43, 48, 59, 0.9);
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

#workspaces button.urgent {
    background-color: #eb4d4b;
}

#clock,
#battery,
#cpu,
#memory,
#temperature,
#network,
#pulseaudio,
#tray {
    padding: 0 10px;
    color: #ffffff;
}

#window {
    margin: 0 4px;
}

#battery.charging, #battery.plugged {
    color: #ffffff;
    background-color: #26A65B;
}

#battery.critical:not(.charging) {
    background-color: #f53c3c;
    color: #ffffff;
    animation-name: blink;
    animation-duration: 0.5s;
    animation-timing-function: linear;
    animation-iteration-count: infinite;
    animation-direction: alternate;
}

@keyframes blink {
    to {
        background-color: #ffffff;
        color: #000000;
    }
}
EOF

# Set up wallpaper directory
sudo -u $USERNAME mkdir -p /home/$USERNAME/Pictures/Wallpapers

echo "Hyprland desktop environment installation completed!"
HYPRLAND_SCRIPT

sudo arch-chroot /mnt bash /install_hyprland.sh
sudo rm /mnt/install_hyprland.sh

# Step 11: Create post-installation instructions
log "Creating post-installation instructions..."
sudo tee /mnt/home/$USERNAME/README_DUAL_BOOT.txt > /dev/null <<README
=====================================
DUAL BOOT SETUP INSTRUCTIONS
=====================================

Your Arch Linux installation is complete! Here's how to add Windows:

STEP 1: Install Windows
-----------------------
1. Boot from Windows installation media
2. When selecting where to install Windows, choose the unallocated space
3. Windows will automatically create its own partitions in the free space
4. Complete Windows installation normally

STEP 2: Fix Boot After Windows Installation
-------------------------------------------
Windows will overwrite the boot loader. To fix this:

1. Boot back into Arch Linux using the installation media
2. Mount your Linux partitions:
   sudo mount $ROOT_PART /mnt
   sudo mount $EFI_PART /mnt/boot/efi
   sudo mount $HOME_PART /mnt/home

3. Reinstall GRUB:
   sudo arch-chroot /mnt
   grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH --recheck
   grub-mkconfig -o /boot/grub/grub.cfg
   exit

4. Reboot - you should now see both Arch Linux and Windows in GRUB

STEP 3: Update GRUB After Windows Installation
----------------------------------------------
After installing Windows, run this command in Arch Linux:
sudo grub-mkconfig -o /boot/grub/grub.cfg

This will detect Windows and add it to the boot menu.

CURRENT PARTITION LAYOUT:
-------------------------
EFI:  $EFI_PART (512MB) - Shared by both OS
Root: $ROOT_PART ($ROOT_SIZE) - Arch Linux system
Home: $HOME_PART ($HOME_SIZE) - Your files
Swap: $SWAP_PART (4GB) - Virtual memory
Free space: Available for Windows

USEFUL COMMANDS:
----------------
- Start Hyprland: Type 'Hyprland' after logging in
- Super+Q: Terminal
- Super+W: Firefox
- Super+R: Application launcher
- Super+E: File manager

TIPS:
-----
- Windows will be able to read your Linux home partition if you install ntfs-3g
- Keep your files in the home partition to access them from both systems
- Always update GRUB after Windows updates: sudo grub-mkconfig -o /boot/grub/grub.cfg

Enjoy your dual boot setup!
README

sudo chown $USERNAME:$USERNAME /mnt/home/$USERNAME/README_DUAL_BOOT.txt

# Step 12: Cleanup and finish
log "Cleaning up..."
sudo umount -R /mnt
sudo swapoff "$SWAP_PART"

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Installation completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
log "System Summary:"
echo "  • Hostname: $HOSTNAME"
echo "  • Username: $USERNAME"
echo "  • EFI partition: $EFI_PART (512MB)"
echo "  • Root partition: $ROOT_PART ($ROOT_SIZE)"
echo "  • Home partition: $HOME_PART ($HOME_SIZE)"
echo "  • Swap partition: $SWAP_PART (4GB)"
echo "  • Free space: Available for Windows"
echo
log "Next steps:"
echo "  1. Remove the installation media and reboot"
echo "  2. Boot into your new Arch Linux system"
echo "  3. Install Windows in the free space (see README_DUAL_BOOT.txt)"
echo "  4. Fix GRUB after Windows installation"
echo
log "After first boot:"
echo "  • Log in with your username and password"
echo "  • Type 'Hyprland' to start the desktop environment"
echo "  • Read ~/README_DUAL_BOOT.txt for dual boot instructions"
echo "  • Update system: sudo pacman -Syu"
echo
warn "Remember:"
echo "  • The free space is reserved for Windows"
echo "  • Windows will overwrite GRUB - follow the README to fix it"
echo "  • Keep the Arch Linux installation media for GRUB recovery"
echo

if confirm "Reboot now?"; then
    sudo reboot
fi
