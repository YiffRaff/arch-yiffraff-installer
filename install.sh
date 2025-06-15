#!/bin/bash
#
# Arch Linux Dual-Boot Installer with Caelestia Shell
# WARNING: This script modifies disk partitions. Use at your own risk!
# Always backup important data before running.
#
# Quick install command:
# curl -fsSL https://raw.githubusercontent.com/your-repo/arch-caelestia-installer/main/install.sh | bash
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

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE} Arch Linux Dual-Boot Installer${NC}"
echo -e "${BLUE}================================${NC}"
echo
echo "This script will help you install Arch Linux alongside Windows"
echo "with Hyprland desktop environment and rEFInd boot manager."
echo
warn "IMPORTANT: This will modify your disk partitions!"
warn "Make sure you have backups of important data."
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

read -p "Select the disk to install Arch Linux on (1-${#DISKS[@]}): " DISK_CHOICE
SELECTED_DISK="${DISKS[$((DISK_CHOICE-1))]}"

if [[ -z "$SELECTED_DISK" ]]; then
    error "Invalid disk selection"
fi

log "Selected disk: $SELECTED_DISK"

# Check for existing EFI partition
EFI_PART=""
EXISTING_PARTS=($(lsblk -pno NAME "$SELECTED_DISK" | tail -n +2))

for part in "${EXISTING_PARTS[@]}"; do
    if [[ $(lsblk -no FSTYPE "$part" 2>/dev/null) == "vfat" ]] && [[ $(lsblk -no SIZE "$part" | grep -E "[0-9]+M|[0-9]G") ]]; then
        # Check if it's an EFI partition
        mkdir -p /tmp/efi_check
        if mount "$part" /tmp/efi_check 2>/dev/null; then
            if [[ -d "/tmp/efi_check/EFI" ]]; then
                EFI_PART="$part"
                log "Found existing EFI partition: $EFI_PART"
            fi
            umount /tmp/efi_check
        fi
        rmdir /tmp/efi_check 2>/dev/null || true
    fi
done

if [[ -z "$EFI_PART" ]]; then
    error "No EFI partition found. This script requires an existing EFI system."
fi

# Step 2: Get installation parameters
echo
log "Configuration setup..."

read -p "Enter desired Linux partition size (e.g., 50G, 100G): " LINUX_SIZE
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -s -p "Enter password for $USERNAME: " USER_PASSWORD
echo
read -s -p "Enter root password: " ROOT_PASSWORD
echo
echo

# Validate inputs
if [[ -z "$LINUX_SIZE" || -z "$HOSTNAME" || -z "$USERNAME" || -z "$USER_PASSWORD" || -z "$ROOT_PASSWORD" ]]; then
    error "All fields are required"
fi

# Step 3: Create partitions
log "Creating partitions..."
warn "This will create new partitions on $SELECTED_DISK"
if ! confirm "Continue with partitioning?"; then
    exit 1
fi

# Find free space and create partitions
sudo fdisk "$SELECTED_DISK" <<EOF
n
p


+${LINUX_SIZE}
n
p



t
$(sudo fdisk -l "$SELECTED_DISK" | grep "^$SELECTED_DISK" | tail -2 | head -1 | awk '{print $1}' | sed 's/.*[^0-9]//')
83
t
$(sudo fdisk -l "$SELECTED_DISK" | grep "^$SELECTED_DISK" | tail -1 | awk '{print $1}' | sed 's/.*[^0-9]//')
82
w
EOF

# Get the new partition names
ROOT_PART="${SELECTED_DISK}$(($(lsblk -no NAME "$SELECTED_DISK" | wc -l) - 1))"
SWAP_PART="${SELECTED_DISK}$(lsblk -no NAME "$SELECTED_DISK" | wc -l)"

log "Root partition: $ROOT_PART"
log "Swap partition: $SWAP_PART"

# Step 4: Format partitions
log "Formatting partitions..."
sudo mkfs.ext4 -F "$ROOT_PART"
sudo mkswap "$SWAP_PART"
sudo swapon "$SWAP_PART"

# Step 5: Mount partitions
log "Mounting partitions..."
sudo mount "$ROOT_PART" /mnt
sudo mkdir -p /mnt/boot
sudo mount "$EFI_PART" /mnt/boot

# Step 6: Install base system
log "Installing base system..."
sudo pacstrap /mnt base base-devel linux linux-firmware networkmanager grub efibootmgr os-prober

# Step 7: Generate fstab
log "Generating fstab..."
sudo genfstab -U /mnt >> /mnt/etc/fstab

# Step 8: Chroot configuration script
log "Creating chroot configuration script..."
sudo tee /mnt/setup_system.sh > /dev/null <<CHROOT_SCRIPT
#!/bin/bash
set -e

# Set timezone
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

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Install additional packages
pacman -S --noconfirm git vim wget curl

echo "Base system configuration completed!"
CHROOT_SCRIPT

# Step 9: Run chroot configuration
log "Configuring system in chroot..."
sudo arch-chroot /mnt bash /setup_system.sh
sudo rm /mnt/setup_system.sh

# Step 10: Install Hyprland with Caelestia Shell (Quickshell)
log "Installing Hyprland with Caelestia Shell desktop environment..."
sudo tee /mnt/install_hyprland.sh > /dev/null <<HYPRLAND_SCRIPT
#!/bin/bash
set -e

# Install Hyprland and essential packages
pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland kitty thunar firefox \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
    brightnessctl playerctl pamixer grim slurp wl-clipboard \
    ttf-font-awesome ttf-jetbrains-mono noto-fonts noto-fonts-emoji \
    polkit-kde-agent qt5-wayland qt6-wayland qt6-declarative \
    sddm git cmake make gcc pkgconf \
    rofi-wayland swww dunst

# Install Quickshell from AUR (we'll build it)
cd /tmp
git clone https://aur.archlinux.org/quickshell.git
cd quickshell
sudo -u $USERNAME makepkg -si --noconfirm
cd ..

# Enable SDDM
systemctl enable sddm

# Install Caelestia Scripts and Shell
log "Installing Caelestia Shell..."
cd /home/$USERNAME
sudo -u $USERNAME git clone https://github.com/caelestia-dots/scripts.git caelestia-scripts
cd caelestia-scripts
sudo -u $USERNAME chmod +x install.sh
sudo -u $USERNAME ./install.sh

# Install Caelestia Shell dotfiles
sudo -u $USERNAME mkdir -p /home/$USERNAME/.config/quickshell
cd /home/$USERNAME/.config/quickshell
sudo -u $USERNAME git clone https://github.com/caelestia-dots/shell.git caelestia

# Create Hyprland config for Caelestia
sudo -u $USERNAME mkdir -p /home/$USERNAME/.config/hypr
sudo -u $USERNAME tee /home/$USERNAME/.config/hypr/hyprland.conf > /dev/null <<EOF
# Caelestia Hyprland Configuration
monitor=,preferred,auto,auto

# Autostart
exec-once = quickshell -c caelestia
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
        new_optimizations = true
        xray = true
        ignore_opacity = true
    }
    
    drop_shadow = true
    shadow_range = 20
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
    col.shadow_inactive = rgba(1a1a1a77)
    
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
    smart_split = false
    smart_resizing = false
}

# Window rules
windowrule = float, ^(pavucontrol)$
windowrule = float, ^(blueman-manager)$
windowrule = float, ^(nm-connection-editor)$
windowrule = float, ^(firefox)$ # for popups
windowrulev2 = float,class:^(firefox)$,title:^(Picture-in-Picture)$

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

# Set up wallpaper directory
sudo -u $USERNAME mkdir -p /home/$USERNAME/Pictures/Wallpapers

# Create a simple startup script for the user
sudo -u $USERNAME tee /home/$USERNAME/.config/hypr/autostart.sh > /dev/null <<EOF
#!/bin/bash
# Set a default wallpaper if available
if command -v caelestia &> /dev/null; then
    caelestia wallpaper --random 2>/dev/null || swww img /usr/share/pixmaps/archlinux-logo.png 2>/dev/null || true
else
    swww img /usr/share/pixmaps/archlinux-logo.png 2>/dev/null || true
fi
EOF
sudo -u $USERNAME chmod +x /home/$USERNAME/.config/hypr/autostart.sh

echo "Caelestia Shell installation completed!"
HYPRLAND_SCRIPT

sudo arch-chroot /mnt bash /install_hyprland.sh
sudo rm /mnt/install_hyprland.sh

# Step 11: Install rEFInd (optional)
if confirm "Do you want to install rEFInd boot manager for a prettier boot menu?"; then
    log "Installing rEFInd..."
    sudo tee /mnt/install_refind.sh > /dev/null <<REFIND_SCRIPT
#!/bin/bash
pacman -S --noconfirm refind
refind-install
REFIND_SCRIPT
    
    sudo arch-chroot /mnt bash /install_refind.sh
    sudo rm /mnt/install_refind.sh
fi

# Step 12: Cleanup and finish
log "Cleaning up..."
sudo umount -R /mnt
sudo swapoff "$SWAP_PART"

echo
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} Installation completed!${NC}"
echo -e "${GREEN}================================${NC}"
echo
log "System Summary:"
echo "  • Hostname: $HOSTNAME"
echo "  • Username: $USERNAME"
echo "  • Root partition: $ROOT_PART"
echo "  • Swap partition: $SWAP_PART"
echo "  • EFI partition: $EFI_PART"
echo
log "Next steps:"
echo "  1. Remove the installation media"
echo "  2. Reboot your system"
echo "  3. Select Arch Linux from the boot menu"
echo "  4. Log in with your username and password"
echo "  5. Start Hyprland with: Hyprland"
echo "  6. Enjoy the beautiful Caelestia Shell!"
echo
warn "First-time setup tips:"
echo "  • Use 'caelestia wallpaper' to set wallpapers"
echo "  • Super+R for app launcher (rofi)"
echo "  • Super+Q for terminal, Super+W for Firefox"
echo "  • The Quickshell widgets provide a gorgeous interface!"
echo
warn "Remember to update your system after first boot:"
echo "  sudo pacman -Syu"
echo
log "Enjoy your new Arch Linux + Hyprland setup!"

if confirm "Reboot now?"; then
    sudo reboot
fi