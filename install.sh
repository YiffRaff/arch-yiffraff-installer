#!/bin/bash

# Easy Arch Linux Dual Boot Installer
# This script helps you install Arch Linux alongside Windows
# Run this from an Arch Linux USB/ISO

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
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root. Use: sudo $0"
fi

# Check if we're in UEFI mode
if [ ! -d "/sys/firmware/efi/efivars" ]; then
    error "This script requires UEFI mode. Please boot in UEFI mode, not Legacy/BIOS."
fi

clear
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  Easy Arch Linux Dual Boot Installer${NC}"
echo -e "${BLUE}================================${NC}"
echo
echo "This script will help you install Arch Linux alongside Windows."
echo "It assumes you already have Windows installed."
echo
warn "IMPORTANT: Make sure you have:"
echo "1. Backed up your important data"
echo "2. At least 50GB of free space on your drive"
echo "3. Disabled Fast Startup and Secure Boot in Windows"
echo
read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Update system clock
log "Updating system clock..."
timedatectl set-ntp true

# Show available disks
log "Available disks:"
lsblk -dp | grep -E '^/dev/[a-z]+' | while read disk; do
    disk_name=$(echo $disk | awk '{print $1}')
    disk_size=$(lsblk -d -n -o SIZE $disk_name | tr -d ' ')
    echo "  $disk_name ($disk_size)"
done

echo
read -p "Enter the disk where Windows is installed (e.g., /dev/sda): " DISK

if [ ! -b "$DISK" ]; then
    error "Disk $DISK does not exist!"
fi

# Show current partitions
log "Current partitions on $DISK:"
lsblk $DISK

# Detect Windows EFI partition
EFI_PART=$(fdisk -l $DISK | grep -i "EFI System" | awk '{print $1}' | head -1)
if [ -z "$EFI_PART" ]; then
    error "Could not find Windows EFI System Partition. Make sure Windows is installed in UEFI mode."
fi

log "Found Windows EFI partition: $EFI_PART"

# Get user preferences
echo
echo "=== Configuration ==="
read -p "Enter your username: " USERNAME
read -s -p "Enter password for $USERNAME: " USER_PASSWORD
echo
read -s -p "Enter root password: " ROOT_PASSWORD
echo
read -p "Enter hostname (computer name): " HOSTNAME
read -p "Enter your timezone (e.g., America/New_York): " TIMEZONE

# Size selection
echo
echo "How much space do you want for Arch Linux?"
echo "1) 50GB (minimum recommended)"
echo "2) 100GB (good for most users)"
echo "3) 200GB (lots of space)"
echo "4) Custom size"
read -p "Choose (1-4): " SIZE_CHOICE

case $SIZE_CHOICE in
    1) ARCH_SIZE="50G" ;;
    2) ARCH_SIZE="100G" ;;
    3) ARCH_SIZE="200G" ;;
    4) 
        read -p "Enter size (e.g., 75G): " ARCH_SIZE
        ;;
    *) ARCH_SIZE="50G" ;;
esac

log "Will create $ARCH_SIZE partition for Arch Linux"

# Create partitions
log "Creating partitions..."
warn "This will modify your disk partitions!"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Find the last partition number
LAST_PART_NUM=$(parted -s $DISK print | tail -n 1 | awk '{print $1}' | grep -o '[0-9]*')
ROOT_PART_NUM=$((LAST_PART_NUM + 1))
SWAP_PART_NUM=$((LAST_PART_NUM + 2))

# Create Arch root partition
log "Creating Arch Linux root partition..."
parted -s $DISK mkpart primary ext4 -- -$(echo $ARCH_SIZE | sed 's/G/GB/') -8GB

# Create swap partition (8GB)
log "Creating swap partition..."
parted -s $DISK mkpart primary linux-swap -- -8GB -0

# Set partition variables
ROOT_PART="${DISK}${ROOT_PART_NUM}"
SWAP_PART="${DISK}${SWAP_PART_NUM}"

log "Created partitions:"
log "  Root: $ROOT_PART"
log "  Swap: $SWAP_PART"

# Format partitions
log "Formatting partitions..."
mkfs.ext4 -F $ROOT_PART
mkswap $SWAP_PART

# Mount partitions
log "Mounting partitions..."
mount $ROOT_PART /mnt
mkdir -p /mnt/boot
mount $EFI_PART /mnt/boot
swapon $SWAP_PART

# Install base system
log "Installing base system (this may take a while)..."
pacstrap /mnt base base-devel linux linux-firmware intel-ucode amd-ucode

# Generate fstab
log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Create chroot configuration script
log "Creating system configuration..."
cat > /mnt/setup_system.sh << 'CHROOT_EOF'
#!/bin/bash

# Set timezone
ln -sf /usr/share/zoneinfo/TIMEZONE_PLACEHOLDER /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "HOSTNAME_PLACEHOLDER" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   HOSTNAME_PLACEHOLDER.localdomain HOSTNAME_PLACEHOLDER
EOF

# Set root password
echo "root:ROOT_PASSWORD_PLACEHOLDER" | chpasswd

# Create user
useradd -m -G wheel,audio,video,optical,storage USERNAME_PLACEHOLDER
echo "USERNAME_PLACEHOLDER:USER_PASSWORD_PLACEHOLDER" | chpasswd

# Enable sudo for wheel group
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Install essential packages
pacman -S --noconfirm grub efibootmgr os-prober ntfs-3g networkmanager network-manager-applet wpa_supplicant dialog mtools dosfstools reflector xdg-utils xdg-user-dirs

# Enable NetworkManager
systemctl enable NetworkManager

# Configure GRUB
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
grub-mkconfig -o /boot/grub/grub.cfg

CHROOT_EOF

# Replace placeholders in chroot script
sed -i "s/TIMEZONE_PLACEHOLDER/$TIMEZONE/g" /mnt/setup_system.sh
sed -i "s/HOSTNAME_PLACEHOLDER/$HOSTNAME/g" /mnt/setup_system.sh
sed -i "s/ROOT_PASSWORD_PLACEHOLDER/$ROOT_PASSWORD/g" /mnt/setup_system.sh
sed -i "s/USERNAME_PLACEHOLDER/$USERNAME/g" /mnt/setup_system.sh
sed -i "s/USER_PASSWORD_PLACEHOLDER/$USER_PASSWORD/g" /mnt/setup_system.sh

# Make script executable and run it
chmod +x /mnt/setup_system.sh
arch-chroot /mnt ./setup_system.sh

# Clean up
rm /mnt/setup_system.sh

# Final setup
log "Performing final setup..."

# Enable os-prober to detect Windows
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Unmount and finish
log "Cleaning up..."
umount -R /mnt
swapoff $SWAP_PART

echo
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo
log "Arch Linux has been installed alongside Windows!"
echo
echo "Next steps:"
echo "1. Remove the USB drive"
echo "2. Reboot your computer"
echo "3. You should see a GRUB menu with both Windows and Arch Linux options"
echo "4. Select Arch Linux to boot into your new system"
echo
echo "Login credentials:"
echo "  Username: $USERNAME"
echo "  Root access: Use 'sudo' command"
echo
warn "After first boot, consider installing a desktop environment like:"
echo "  sudo pacman -S gnome gnome-extra gdm"
echo "  sudo systemctl enable gdm"
echo
read -p "Press Enter to reboot now, or Ctrl+C to stay in live environment..."
reboot
