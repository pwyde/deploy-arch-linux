#!/usr/bin/env bash

# Install script for Arch Linux with ZFS on root and LUKS encryption.
# Copyright (C) 2019 Patrik Wyde <patrik@wyde.se>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Print commands and their arguments as they are executed.
#set -x
# Exit immediately if a command exits with a non-zero exit status.
set -e

# Configure script variables.
git_repo="deploy-arch-linux"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
install="false"
post_install="false"
## Disk drive IDs (symlinks in /dev/disk/by-id).
# Disks for ZFS root pool (rpool).
rdisk=""
# Location of EFI System Partition (ESP).
esp="/efi"
# Configure hostname on destination server/system.
hostname=""
# Configure locale to generate.
locale=("en_US.UTF-8" "en_GB.UTF-8" "sv_SE.UTF-8")
# Configure keymap.
keymap="sv-latin1"
## Colorize output.
# shellcheck disable=SC2034
red="\033[91m"
# shellcheck disable=SC2034
green="\033[92m"
# shellcheck disable=SC2034
blue="\033[94m"
# shellcheck disable=SC2034
yellow="\033[93m"
# shellcheck disable=SC2034
cyan="\033[96m"
# shellcheck disable=SC2034
magenta="\033[95m"
# shellcheck disable=SC2034
white="\033[1m"
# shellcheck disable=SC2034
no_color="\033[0m"
# Set a default locale during install to avoid mandb error when indexing man pages.
export LANG=C

print_help() {
echo -e "
${white}Description:${no_color}
  Script deploys a minimal Arch Linux installation base with ZFS on root and
  encryption using dm-crypt/LUKS.

  Script only supports a single disk drive configuration and will automatically
  partition the disk with the following scheme.

  +---------------------------------------------------------------------------+
  | /dev/disk/by-id/ata|nvme-Manufacturer_Model_Number                        |
  +-------------------+-------------------------------------------------------+
  | ESP partition:    | Linux filesystem partition:                           |
  +-------------------+-------------------------------------------------------+
  | 550 MB            | Remaining disk space                                  |
  |                   |                                                       |
  | Not encrypted     | Encrypted                                             |
  +-------------------+-------------------------------------------------------+

  Script is designed to be used on a UEFI system only. No legacy BIOS support,
  hence no Master Boot Record (MBR) will be created.

  The EFI System Partition (ESP) is mounted to /efi. The root partition (/) is
  a ZFS pool (rpool) encrypted with dm-crypt/LUKS (crypt-root).

  ata|nvme-Manufacturer_Model_Number-part1
   └─ ESP (/efi)
  ata|nvme-Manufacturer_Model_Number-part2
   └─ crypt-root (/)
       └─ ZFS pool (rpool)

  The following ZFS datasets will be automatically created during installation.

  Name:                  Mountpoint:
  rpool                  /
  rpool/ROOT             none
  rpool/ROOT/arch        /
  rpool/home             /home
  rpool/home/root        /root
  rpool/opt              /opt
  rpool/srv              /srv
  rpool/usr              /usr
  rpool/usr/local        /usr/local
  rpool/var              /var
  rpool/var/cache        /var/cache
  rpool/var/lib          /var/lib
  rpool/var/lib/libvirt  /var/lib/libvirt
  rpool/var/log          /var/log
  rpool/var/tmp          /var/tmp

${white}Prerequisite:${no_color}
  Installation is performed using the Arch Linux instalation image (archiso):
  https://wiki.archlinux.org/index.php/Archiso

  It must however be embedded with the archzfs packages. Consult the following
  Arch wiki page for instructions on creating a custom archiso image with
  archzfs packages:
  https://wiki.archlinux.org/index.php/ZFS#Embed_the_archzfs_packages_into_an_archiso

  An alternative to building a custom archiso image is to download the pre-
  built image from the ALEZ project (archlinx-alez), as it already contains
  archzfs packages: https://github.com/danboid/ALEZ/releases

${white}Preperation:${no_color}
  Prior to script execution, boot the Arch Linux installation image that
  has the archzfs packages embedded (see prerequisites above).

  Update repositories in the Arch Linux live environment.
  # pacman -Sy --noconfirm

  Install Git.
  # pacman -S --noconfirm git

  Download Git repository.
  # git clone https://gitlab.com/pwyde/$git_repo.git
  # cd $git_repo

${white}Usage:${no_color}
  Start the scripted installation.
  # bash $0 --install

${white}Limitations:${no_color}
  The resulting Arch Linux installation with ZFS on root contains a few config-
  uration options that must be known and cannot or should not be changed in the
  future.
    - The 'encrypt' hook only allows for a single encrypted disk. Hence a ZFS
      pool mirror/raidz is not possible with two or more LUKS encrypted drives.
    - The 'systemd' hook cannot be used when creating the initramfs image with
      'mkinitcpio' command. If systemd is used in the initramfs, the AUR
      package 'mkinitcpio-sd-zfs' must be installed and the 'zfs' hook must be
      changed to 'sd-zfs'. Keep in mind that this hook uses different kernel
      parameters than the default 'zfs' hook. Also note that this package has
      not received any updates during the last couple of years. The developer
      has also stated on the GitHub project page that he is not actively
      maintaining it anymore.

  There are also other considerations that should be taken into account on the
  resulting system.
   - Due to limitations of the ESP and boot loader (systemd-boot), a copy of
     the Linux kernel and initramfs image will be stored on the non-encrypted
     partition. The copy procedure is handled automoatically by the custom
     systemd service unit 'update-esp.path'. This makes the resulting system
     subject to Evil Maid attacks due to the exposed kernel and initramfs
     image. This should be mitigated by enabling Secure Boot and preferably
     with custom keys. The AUR packages 'cryptboot' and 'sbupdate' can assist
     with this procedure.

${white}Disclaimer:${no_color}
  Please note that this installation script is system specific and subject to
  change depending on hardware configuration of the destination computer.

  Script is written for Bash and must be executed in this shell. It is designed
  for and tested on Arch Linux. It also containes configuration variables that
  are specific for the destination system, such as locale, timezone and more...
  This MUST be changed prior to script execution!

  ${white}With the information stated above,${no_color} ${yellow}YOU HAVE BEEN WARNED!${no_color}

${white}Options:${no_color}
  ${cyan}-i${no_color}, ${cyan}--install${no_color}       Performs installation and configuration on destination
                      system.

  ${cyan}-p${no_color}, ${cyan}--post-install${no_color}  Performs post-installation configuration. This option
                      is only used when performing configuration in the chroot
                      environment. Should NOT be used when executing script.
" >&2
}

# Print help if no argument is specified.
if [ "${#}" -le 0 ]; then
    print_help
    exit 1
fi

# Loop as long as there is at least one more argument.
while [ "${#}" -gt 0 ]; do
    arg="${1}"
    case "${arg}" in
        # This is an arg value type option. Will catch both '-i' or
        # '--install' value.
        -i|--install) install="true" ;;
        # This arg value is only used when performing configuration
        # in the chroot environment.
        -p|--post-install) post_install="true" ;;
        # This is an arg value type option. Will catch both '-h' or
        # '--help' value.
        -h|--help) print_help; exit ;;
        *) echo "Invalid option '${arg}'." >&2; print_help; exit 1 ;;
    esac
    # Shift after checking all the cases to get the next option.
    shift
done

print_msg() {
    echo -e "$green=>$no_color$white" "$@" "$no_color" >&1
}

print_error() {
    echo -e "$red=> ERROR:$no_color$white" "$@" "$no_color" >&1
}

test_run_as_root() {
    # Verify that script is executed as the 'root' user.
    if [[ "${EUID}" -ne 0 ]]; then
        print_error "Script must be executed as the 'root' user!"
        exit 1
    fi
}

setup_variables() {
    echo -e "${white}""Select disk to partition:""${no_color}"
    echo
    for disk in /dev/disk/by-id/*; do
        disk="${disk##*/}"
        echo -e "${yellow}""${disk}""${no_color}"
    done
    echo
    # shellcheck disable=SC2162
    read -p "$(echo -e "${white}")Root disk (crypt-root): $(echo -e "${no_color}")" rdisk
    if ! [[ -e /dev/disk/by-id/"${rdisk}" ]]; then
        print_error "Invalid or non-existing disk: $rdisk"
        exit 1
    fi
    echo
    # shellcheck disable=SC2162
    read -p "$(echo -e "${white}")Enter hostname: $(echo -e "${no_color}")" hostname
    echo
    if [[ -z "${hostname}" ]]; then
        print_error "Invalid hostname!"
        exit 1
    fi
    # shellcheck disable=SC2162
    read -p "$(echo -e "${white}")Enter domain name (use '.local' if no specific): $(echo -e "${no_color}")" domain_name
    echo
    # Remove leading dot (.) in domain name string if it exists.
    domain_name="${domain_name##.}"
    if [[ -z "${domain_name}" ]]; then
        print_error "Invalid domain name!"
        exit 1
    fi
    # shellcheck disable=SC2162
    read -p "$(echo -e "${white}")Enter NTP server (leave blank for none): $(echo -e "${no_color}")" ntp_server
    echo
    # Dump disk variables to file that will be sourced in chroot environment.
    cat > "${script_dir}"/.variables <<EOF
## Disk drive IDs (symlinks in /dev/disk/by-id).
# Disk for ZFS root pool (rpool).
rdisk="$rdisk"
# Hostname.
hostname="$hostname"
# Domain name.
domain_name="$domain_name"
# NTP server.
ntp_server="$ntp_server"
EOF
}

update_live_repos() {
    # Update repositories in the Arch Linux live environment.
    pacman -Sy --noconfirm
}

partition() {
    echo
    echo -e "${red}""WARNING: Selected disk will be re-partitioned!""${no_color}"
    echo
    # shellcheck disable=SC2162
    read -p "$(echo -e "${white}")Press enter to continue or Ctrl + C to abort...$(echo -e "${no_color}")"
    echo
    print_msg "Deleting disk partitions..."
    # Clear all partitions and tables.
    for disk in $rdisk; do
        sgdisk --mbrtogpt --clear /dev/disk/by-id/"${disk}"
        sgdisk --mbrtogpt --zap-all /dev/disk/by-id/"${disk}"
    done
    print_msg "Creatinig new partitions..."
    # Partition root disk; EFI System Partition (part1)
    sgdisk --new=1:1M:+550M --typecode=1:EF00 /dev/disk/by-id/"${rdisk}"
    # Partition root disk; use remaining space for encrypted block device (part2).
    sgdisk --new=2:0:0 --typecode=2:8300 /dev/disk/by-id/"${rdisk}"
}

setup_encryption() {
    print_msg "Creating encrypted block device..."
    # Wait a few seconds for devices to be ready. This seems to be needed sometimes...
    sleep 3
    # Create LUKS container for ZFS root pool (rpool).
    cryptsetup luksFormat -c aes-xts-plain64 -h sha512 -s 512 --use-urandom --type luks2 /dev/disk/by-id/"${rdisk}"-part2
}

luks_open() {
    print_msg "Finalize crypt-root setup..."
    # Open LUKS container.
    cryptsetup status crypt-root || cryptsetup luksOpen /dev/disk/by-id/"${rdisk}"-part2 crypt-root
}

initialize_zfs() {
    # Create zpool for / (rpool).
    if zpool status rpool > /dev/null 2>&1; then
        zpool destroy rpool
    fi
    zpool create -o ashift=12 \
        -o cachefile=/etc/zfs/zpool.cache \
        -O acltype=posixacl -O canmount=off -O compression=lz4 \
        -O dnodesize=auto -O normalization=formD -O relatime=on -O xattr=sa \
        -O mountpoint=/ -R /mnt \
        rpool /dev/mapper/crypt-root
    zfs create -o canmount=off -o mountpoint=none rpool/ROOT
    # Create filesystem datasets for the root and boot filesystems.
    zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT/arch
    zfs mount rpool/ROOT/arch
    # Create remaining datasets.
    zfs create                                 rpool/home
    zfs create -o mountpoint=/root             rpool/home/root
    zfs create -o canmount=off                 rpool/var
    zfs create -o canmount=off                 rpool/var/lib
    zfs create                                 rpool/var/log
    # If libvirtd will be used.
    zfs create                                 rpool/var/lib/libvirt
    # Exclude /var/cashe and /var/tmp from snapshots.
    zfs create -o com.sun:auto-snapshot=false  rpool/var/cache
    zfs create -o com.sun:auto-snapshot=false  rpool/var/tmp
    # If optional packages will be installed in the /opt directory.
    zfs create                                 rpool/opt
    # If services will share data using the /srv directory.
    zfs create                                 rpool/srv
    # If local scripts/binaries will be installed in the /usr/local directory.
    zfs create -o canmount=off                 rpool/usr
    zfs create                                 rpool/usr/local
    print_msg "Created ZFS data structure..."
}

initialize_esp() {
    # Format the EFI system partition.
    mkfs.vfat -F 32 /dev/disk/by-id/"${rdisk}"-part1
    # Mount the EFI system partition.
    test -d /mnt"${esp}" || mkdir /mnt"${esp}"
    mount /dev/disk/by-id/"${rdisk}"-part1 /mnt"${esp}"
    print_msg "Created EFI system partition..."
}

setup_initial_system() {
    # Fix warning message during 'pacstrap':
    # "warning: directory permissions differ on /mnt/root/
    # filesystem: 755  package: 750"
    chmod 750 /mnt/root
    print_msg "Installing base packages..."
    # Install minimal system.
    # Package 'base-devel' will be needed later to install pacman helpers such as 'yay'.
    pacstrap /mnt base base-devel linux linux-headers linux-firmware man-db man-pages nano vim bash-completion git
    # Configure filesystem mount ordering (fstab).
    echo "# <file system>         <dir>           <type>          <options>                                                          <dump> <pass>" > /mnt/etc/fstab
    genfstab -U -p /mnt | grep efi >> /mnt/etc/fstab
    print_msg "Installed base packages..."
}

dest_system_basic_config() {
    test -e "/root/$git_repo/$(basename "${0}")"
    # Configure hostname.
    echo "${hostname}" > /etc/hostname
    echo "127.0.0.1       $hostname" >> /etc/hosts
    # Configure domain name.
    echo "$hostname.$domain_name" > /etc/hostname
    cat > /etc/hosts <<EOF
# <ip-address>  <hostname.domain.tld>          <hostname>
127.0.0.1       $hostname.$domain_name         $hostname
::1             $hostname.$domain_name         $hostname
EOF
    print_msg "Configured hostname..."
    # Configure the keyboard layout.
    echo "KEYMAP=$keymap" > /etc/vconsole.conf
    print_msg "Configured console keymap..."
    # Configure locale.
    for item in "${locale[@]}"; do
        sed -i "s/#$item/$item/" /etc/locale.gen
    done
    cp --force "${script_dir}"/etc/locale.conf /etc/locale.conf
    locale-gen
    # Configure the system clock.
    ln -s /usr/share/zoneinfo/Europe/Stockholm /etc/localtime
    hwclock --systohc --utc
    if [[ -n "${ntp_server}" ]]; then
        # Configure NTP server.
        sed -i "s/#NTP=/NTP=$ntp_server/" /etc/systemd/timesyncd.conf
    fi
    timedatectl set-ntp true
    timedatectl set-timezone Europe/Stockholm
    systemctl enable systemd-timesyncd.service
    print_msg "Updated the system clock..."
}

dest_system_mkinitcpio() {
    test -e "/root/$git_repo/$(basename "${0}")"
    # Configure mkinitcpio.
    sed -i "s/HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap encrypt zfs filesystems)/g" /etc/mkinitcpio.conf
    print_msg "Configured mkinitcpio..."
}

dest_system_config_pacman() {
    test -e "/root/$git_repo/$(basename "${0}")"
    # Configure package manager.
    sed -i "/Color/s/^#//" /etc/pacman.conf
    print_msg "Configured pacman..."
}

dest_system_zfs() {
    test -e "/root/$git_repo/$(basename "${0}")"
    print_msg "Installing ZFS..."
    # Configure Arch ZFS repository.
    echo -e "\n[archzfs]\nServer = https://archzfs.com/\$repo/x86_64" >> /etc/pacman.conf
    pacman-key -r F75D9D76
    pacman-key --lsign-key F75D9D76
    pacman -Sy
    ## Install ZFS.
    # Linux kernel with ZFS from archzfs repo.
    #pacman -S --noconfirm zfs-linux
    # DKMS (Dynamic Kernel Module Support).
    pacman -S --noconfirm zfs-dkms
    # Using zfs-mount.service.
    #systemctl enable zfs.target
    #systemctl enable zfs-import-cache
    #systemctl enable zfs-mount
    #systemctl enable zfs-import.target
    # Using zfs-mount-generator.
    ln -s /usr/lib/zfs-*/zfs/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d
    systemctl enable zfs-zed.service
    systemctl enable zfs.target
    mkdir -p /etc/zfs/zfs-list.cache
    mkdir -p /etc/zfs/zfs-list.cache && touch /etc/zfs/zfs-list.cache/rpool
    # Populate zfs-list.cache file manually using 'zed' since we are in a chroot environment.
    /usr/bin/zed -f
    print_msg "Installed ZFS..."
}

dest_system_install_bootctl() {
    test -e "/root/$git_repo/$(basename "${0}")"
    print_msg "Installing systemd-boot..."
    # Install systemd-boot to ESP.
    /usr/bin/bootctl --path="${esp}" install
    # Create basic loader configuration file.
    cat > "${esp}"/loader/loader.conf <<EOF
default arch
timeout 5
console-mode max
editor no
EOF
    # Create default boot loader entry.
    cat > "${esp}"/loader/entries/arch.conf <<EOF
title       Arch Linux
linux       /EFI/Linux/vmlinuz-linux
initrd      /EFI/Linux/initramfs-linux.img
options     cryptdevice=/dev/disk/by-id/$rdisk-part2:crypt-root:allow-discards root=ZFS=rpool/ROOT/arch rw
EOF
    # Copy kernel and initramfs images to ESP.
    cp -a /boot/vmlinuz-linux* "${esp}"/EFI/Linux
    cp -a /boot/initramfs-linux* "${esp}"/EFI/Linux
    # Enable custom systemd service unit to update ESP with new kernel and initramfs image.
    cp --force "${script_dir}"/etc/systemd/system/update-esp.path /etc/systemd/system/update-esp.path
    cp --force "${script_dir}"/etc/systemd/system/update-esp.service /etc/systemd/system/update-esp.service
    systemctl enable update-esp.path
    print_msg "Installed systemd-boot..."
}

dest_system_enable_scrubbing() {
    test -e "/root/$git_repo/$(basename "${0}")"
    # Enable scrubbing using systemd service and timer units.
    cp --force "${script_dir}"/etc/systemd/system/zfs-scrub@.timer /etc/systemd/system/zfs-scrub@.timer
    cp --force "${script_dir}"/etc/systemd/system/zfs-scrub@.service /etc/systemd/system/zfs-scrub@.service
    systemctl enable zfs-scrub@rpool.timer
    print_msg "Enabled ZFS scrubbing..."
}

dest_system_networking() {
    test -e "/root/$git_repo/$(basename "${0}")"
    print_msg "Installing networking tools/utilities/services..."
    # Install networking tools/utilities/services.
    pacman -S --noconfirm networkmanager net-tools inetutils openssh
    systemctl enable NetworkManager.service
    print_msg "Installed networking tools/utilities/services..."
}

dest_system_final_config_before_reboot() {
    test -e "/root/$git_repo/$(basename "${0}")"
    # Set root password.
    set +x
    root_pw=$(getent shadow root | cut -f 2 -d :)
    if [[ "${root_pw}" == '*' ]] || [[ -z "${root_pw}" ]]; then
        echo
        echo -e "${white}""Set root password for system.""${no_color}"
        echo
        passwd
        echo
    fi
    # Create snapshots.
    for snap in rpool/ROOT/arch@install; do
        if zfs list -t snap | grep -q $snap; then
            zfs destroy $snap > /dev/null 2>&1
        fi
        zfs snapshot $snap
    done
}

config_zfs_mount_generator() {
    # Remove and replace the '/mnt' path in the mountpoints of the zfs-list.cache file.
    # This must be performed outside the chroot environment.
    sed -i "s:mnt/::" /mnt/etc/zfs/zfs-list.cache/rpool
    sed -i "s:/mnt:/:" /mnt/etc/zfs/zfs-list.cache/rpool
    print_msg "Configured ZFS mount generator for destination system..."
}

if [[ "${install}" == true && "${post_install}" == false ]]; then
    test_run_as_root
    echo
    echo -e "${cyan}""Performing pre-installation configuration...""${no_color}"
    echo
    #set -x
    setup_variables
    update_live_repos
    partition
    setup_encryption
    luks_open
    initialize_zfs
    initialize_esp
    echo
    echo -e "${cyan}""Performing minimal installation...""${no_color}"
    echo
    setup_initial_system
    # Copy script to destination system and execute via 'arch-chroot'.
    cp -r "${script_dir}" /mnt/root
    arch-chroot /mnt /bin/bash -c "/root/$git_repo/$(basename "$0") --post-install"
    set +x
    config_zfs_mount_generator
    print_msg "System installation completed!"
    echo
    echo -e "${yellow}""System is ready to reboot!""${no_color}"
    echo
    echo -e "${white}""The following commands will be executed.""${no_color}"
    echo -e "${white}""# umount /mnt${esp}""${no_color}"
    echo -e "${white}""# zfs umount -a""${no_color}"
    echo -e "${white}""# zpool export rpool""${no_color}"
    echo -e "${white}""# reboot --force""${no_color}"
    echo
    # shellcheck disable=SC2162
    read -p "$(echo -e "${white}")Press enter to continue or Ctrl + C to abort...$(echo -e "${no_color}")"
    /usr/bin/umount /mnt"${esp}"
    zfs umount -a
    zpool export rpool
    reboot --force
elif [[ "${install}" == false && "${post_install}" == true ]]; then
    echo
    echo -e "${cyan}""Performing post-install configuration...""${no_color}"
    echo
    #set -x
    # Source disk variables that were dumped to file during '--install'.
    # shellcheck source=/dev/null
    source /root/"${git_repo}"/.variables
    dest_system_basic_config
    dest_system_mkinitcpio
    dest_system_config_pacman
    dest_system_zfs
    dest_system_install_bootctl
    dest_system_enable_scrubbing
    dest_system_networking
    dest_system_final_config_before_reboot
    set +x
else
    print_error "Missing or invalid options, see help below."
    print_help
    exit 1
fi
