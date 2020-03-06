#!/usr/bin/env bash

# Configuration script for Arch Linux.
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
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
configure="false"
aur_helper="false"
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

print_help() {
echo -e "
${white}Description:${no_color}
  Script performs post-deployment configuration on a newly installed Arch
  Linux system. Used for installing utilities/tools and basic system hardening.

  Script performs the following configuration changes:
    - Configure pacman.
      - Initializing and refresh the keyring.
    - Configure makepkg.
    - Update packages.
    - Create a regular user.
    - Configure SSH.
      - SSH daemon and client hardening.
      - Creates dedicated SSH user group and adds specified user to group.
    - Configure hostname.
    - Configure console colors.
    - Configure file and inode limits.
    - Configure journal size limit.
    - Disable core dumps.
    - Set a timeout for sudo sessions.
    - Set lockout after failed login attempts.
    - TCP/IP stack hardening.
    - Restrict access to kernel logs.
    - Disable Speck kernel module.
    - Secure kernel pointers in /proc filesystem.
    - Restrict access to ptrace.
    - Hide PIDs.
    - Disable the root password.

Script can also automatically install 'yay' as the preferred AUR helper if the
'--aur-helper' option is specified (optional).

${white}Disclaimer:${no_color}
  Script is written for Bash and must be executed in this shell. It is designed
  for and tested on Arch Linux. It contains configuration variables and other
  configuration files that are specific for the destination system, i.e. SSH
  daemon/client, ZFS on root filesystem and EFI System Partition (ESP) mounted
  to /efi.

  System hardening performed by this script is not official common best
  practices and are subject to debate and changes in the future.

  ${white}With the information stated above,${no_color} ${yellow}YOU HAVE BEEN WARNED!${no_color}

${white}Options:${no_color}
  ${cyan}-c${no_color}, ${cyan}--configure${no_color}       Apply system configuration and hardening included in script.

  ${cyan}-a${no_color}, ${cyan}--aur-helper${no_color}      Install preferred AUR helper (yay).
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
        # This is an arg value type option. Will catch both '-c' or
        # '--configure' value.
        -c|--configure) configure="true" ;;
        # This is an arg value type option. Will catch both '-a' or
        # '--aur-helper' value.
        -a|--aur-helper) aur_helper="true" ;;
        # This is an arg value type option. Will catch both '-h' or
        # '--help' value.
        -h|--help) print_help; exit ;;
        *) echo "Invalid option '${arg}'." >&2; print_help; exit 1 ;;
    esac
    # Shift after checking all the cases to get the next option.
    shift > /dev/null 2>&1;
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
    # shellcheck disable=SC2162
    read -p "$(echo -e "${white}")Enter username to create: $(echo -e "${no_color}")" username
    echo
    if [[ -z "${username}" ]]; then
        print_error "Invalid username!"
        exit 1
    elif [[ $(getent passwd "$username") ]]; then
        print_error "User '$username' already exist!"
        exit 1
    fi
    # Dump disk variables to file that will be sourced in chroot environment.
    cat >> "${script_dir}"/.variables <<EOF
# Regular user.
username="$username"
EOF
}

config_pacman() {
    # Copy custom pacman mirror list.
    mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    cp --force "${script_dir}"/etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist
    # Enable multilib repo.
    sed -i "s/#\[multilib\]/[multilib]/" /etc/pacman.conf
    sed -i "/\[multilib\]$/{n;s/^#//;}" /etc/pacman.conf
    print_msg "Configured pacman..."
    print_msg "initializing and refreshing the pacman keyring..."
    pacman-key --init > /dev/null 2>&1
    pacman-key --populate archlinux > /dev/null 2>&1
    pacman-key --refresh-keys > /dev/null 2>&1
    pacman -Sy --noconfirm > /dev/null 2>&1
    print_msg "Initialized and refreshed the pacman keyring..."
}

config_makepkg() {
    mv /etc/makepkg.conf /etc/makepkg.conf.bak
    cp --force "${script_dir}"/etc/makepkg.conf /etc/makepkg.conf
    print_msg "Configured makepkg..."
}

update_system() {
    print_msg "Updating system..."
    pacman -Syu --noconfirm > /dev/null 2>&1
    print_msg "Updated system..."
}

config_regular_user() {
    # Create regular user.
    zfs create rpool/home/"${username}"
    useradd "${username}" -M -g users -G wheel,storage,video,audio,lp -s /bin/bash
    cp -a /etc/skel/.[!.]* /home/"${username}"/
    chown -R "$username":users /home/"${username}"
    chmod 0700 /home/"${username}"
    echo -e "${white}""Enter password for new user: ""${no_color}""$username"
    passwd "${username}"
}

config_sudo() {
    # Configure sudo.
    sed -i "/%wheel ALL=(ALL) ALL/s/^# //" /etc/sudoers
    print_msg "Configured sudo..."
}

config_ssh() {
    print_msg "Configuring OpenSSH..."
    # Create group for SSH access.
    groupadd sshusers
    # Add user to SSH group.
    usermod -aG sshusers "${username}"
    systemctl enable sshd.service > /dev/null 2>&1
    systemctl restart sshd.service > /dev/null 2>&1
    # Enable diffie-hellman-group-exchange-sha256 key exchange protocol.
    awk '$5 > 2000' /etc/ssh/moduli > "${HOME}/moduli"
    wc -l "${HOME}/moduli" > /dev/null 2>&1
    mv "${HOME}/moduli" /etc/ssh/moduli
    # Generate new SSH keys.
    rm /etc/ssh/ssh_host_*key*
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" < /dev/null
    ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" < /dev/null
    # Copy SSH daemon configuration file.
    cp --force "${script_dir}"/etc/ssh/sshd_config /etc/ssh/sshd_config
    # Copy SSH client configuration file.
    cp --force "${script_dir}"/etc/ssh/ssh_config /etc/ssh/ssh_config
    print_msg "Configured OpenSSH..."
}

config_welcome_msg() {
    cat > /etc/issue <<EOF
Arch Linux on \n

EOF
    print_msg "Configured welcome message/banner..."
}

config_console_colors() {
    mv /etc/bash.bashrc /etc/bash.bashrc.bak
    cp --force "${script_dir}"/etc/bash.bashrc /etc/bash.bashrc
    cp --force "${script_dir}"/etc/DIR_COLORS /etc/DIR_COLORS
    print_msg "Configured console colors..."
}

config_file_inode_limits() {
    # Configure inode limits.
    cp --force "${script_dir}"/etc/sysctl.d/30-fs.conf /etc/sysctl.d/30-fs.conf
    # Configure file limits.
    cat >> /etc/security/limits.conf <<EOF

# Start of custom configuration.

# Increase file limits.
*               soft    nofile          100000
*               hard    nofile          100000
EOF
    print_msg "Configured file and inode limits..."
}

config_journal_size() {
    # Configure journal size limit.
    mkdir -p /etc/systemd/journald.conf.d
    cp --force "${script_dir}"/etc/systemd/journald.conf.d/00-journal-size.conf /etc/systemd/journald.conf.d/00-journal-size.conf
    systemctl daemon-reload
    print_msg "Configured journal size limit..."
}

config_core_dumps() {
    ## Disable core dumps.
    # Using systemd
    mkdir -p /etc/systemd/coredump.conf.d
    cp --force "${script_dir}"/etc/systemd/coredump.conf.d/00-core-dumps.conf /etc/systemd/coredump.conf.d/00-core-dumps.conf
    systemctl daemon-reload
    # Using ulimit
    cat >> /etc/security/limits.conf <<EOF

# Disable core dumps.
*               hard    core            0
EOF
    # Using sysctl.
    cp --force "${script_dir}"/etc/sysctl.d/50-coredump.conf /etc/sysctl.d/50-coredump.conf
    print_msg "Disabled core dumps..."
}

secure_sudo_timeout() {
    cat >> /etc/sudoers <<EOF

# Set default sudo session timeout.
Defaults env_reset,timestamp_timeout=15
EOF
    print_msg "Configured sudo session timeout..."
}

secure_pam() {
    # Lockout user after three failed login attempts
    sed -i "s:onerr=succeed file=/var/log/tallylog:deny=3 unlock_time=600 onerr=succeed file=/var/log/tallylog:" /etc/pam.d/system-login
}

secure_tcpip_stack() {
    # TCP/IP stack hardening.
    cp --force "${script_dir}"/etc/sysctl.d/40-ipv4.conf /etc/sysctl.d/40-ipv4.conf
    cp --force "${script_dir}"/etc/sysctl.d/41-net.conf /etc/sysctl.d/41-net.conf
    cp --force "${script_dir}"/etc/sysctl.d/40-ipv6.conf /etc/sysctl.d/40-ipv6.conf
    print_msg "Performed TCP/IP stack hardening..."
}

secure_kernel_log_access() {
    # Restrict access to kernel logs.
    cp --force "${script_dir}"/etc/sysctl.d/50-dmesg-restrict.conf /etc/sysctl.d/50-dmesg-restrict.conf
    print_msg "Restricted access to kernel logs..."
}

secure_speck_module() {
    # Disable Speck kernel module.
    cat >> /etc/modprobe.d/blacklist.conf <<EOF

# Disable the Speck kernel module (cipher developed by the NSA).
install speck /bin/false
EOF
    print_msg "Disabled Speck kernel module..."
}

secure_kernel_pointers() {
    # Secure kernel pointers in /proc filesystem.
    cp --force "${script_dir}"/etc/sysctl.d/50-kptr-restrict.conf /etc/sysctl.d/50-kptr-restrict.conf
    print_msg "Secured access to kernel pointers..."
}

secure_ptrace_scope() {
    # Restrict access to ptrace.
    cp --force "${script_dir}"/etc/sysctl.d/50-ptrace_scope-restrict.conf /etc/sysctl.d/50-ptrace_scope-restrict.conf
    print_msg "Secured ptrace scope..."
}

secure_pid() {
    # Hide PIDs.
    echo "proc                    /proc           proc            nosuid,nodev,noexec,hidepid=2,gid=proc                                  0 0" >> /etc/fstab
    mkdir -p /etc/systemd/system/systemd-logind.service.d
    cp --force "${script_dir}"/etc/systemd/system/systemd-logind.service.d/hidepid.conf /etc/systemd/system/systemd-logind.service.d/hidepid.conf
    usermod -aG proc "${username}"
    print_msg "Secured PIDs..."
}

secure_root_login() {
    # Disable the root password.
    usermod -p '*' root
    print_msg "Disabled root password..."
}

install_aur_helper() {
    # Install AUR helper.
    print_msg "Installing dependencies..."
    pacman -S --noconfirm git go > /dev/null 2>&1
    print_msg "Installing AUR helper as user '${username}'..."
    sudo --set-home --user "${username}" --shell /bin/bash <<'EOF'
cd "${HOME}"
git clone https://aur.archlinux.org/yay.git
cd "${HOME}"/yay
makepkg PKGBUILD --skippgpcheck --install --noconfirm
cd "${HOME}"
rm -rf "${HOME}"/yay
EOF
}

if [[ "${configure}" == true ]]; then
    test_run_as_root
    echo
    echo -e "${cyan}""Performing basic system configuration...""${no_color}"
    echo
    setup_variables
    config_regular_user
    config_sudo
    config_pacman
    config_makepkg
    update_system
    config_ssh
    config_welcome_msg
    config_console_colors
    echo
    echo -e "${cyan}""Performing system optimization configuration...""${no_color}"
    echo
    config_file_inode_limits
    config_journal_size
    config_core_dumps
    echo
    echo -e "${cyan}""Performing security configuration...""${no_color}"
    echo
    secure_sudo_timeout
    secure_pam
    secure_tcpip_stack
    secure_kernel_log_access
    secure_speck_module
    secure_kernel_pointers
    secure_ptrace_scope
    secure_pid
    secure_root_login
    if [[ "${aur_helper}" == true ]]; then
        echo
        echo -e "${cyan}""Installing AUR helper...""${no_color}"
        echo
        install_aur_helper
    fi
    echo
    echo -e "${green}""System configuration completed!""${no_color}"
    echo
    echo -e "${yellow}""System is ready to reboot!""${no_color}"
    echo
    # shellcheck disable=SC2162
    read -p "$(echo -e "${white}")Press enter to continue or Ctrl + C to abort...$(echo -e "${no_color}")"
    reboot --force
elif [[ "${configure}" == false && "${aur_helper}" == true ]]; then
    echo
    echo -e "${cyan}""Installing AUR helper...""${no_color}"
    echo
    echo -e "${yellow}""WARNING: Running 'makepkg' as root is not allowed!""${no_color}"
    echo
    echo -e "${white}""Please specify an existing regular username to execute 'makepkg' with.""${no_color}"
    echo
    # shellcheck disable=SC2162
    read -p "$(echo -e "${white}")Enter regular user: $(echo -e "${no_color}")" username
    if [[ -z "${username}" ]]; then
        print_error "Invalid username!"
        exit 1
    elif [[ -z $(getent passwd "$username") ]]; then
        print_error "User '$username' does not exist!"
        exit 1
    fi
    install_aur_helper
    echo
    echo -e "${green}""Installation completed!""${no_color}"
    echo
else
    print_error "Missing or invalid options, see help below."
    print_help
    exit 1
fi
