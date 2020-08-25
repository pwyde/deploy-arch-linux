# Deploy Arch Linux

## About
A collection of scripts and configuration files used to quickly deploy a minimal [Arch Linux](https://www.archlinux.org/) installation with [ZFS](https://zfsonlinux.org/) on root and encryption using [dm-crypt/LUKS](https://wiki.archlinux.org/index.php/Dm-crypt).

## Disclaimer
Please note that these scripts are system specific and subject to change depending on hardware configuration of the destination computer.

Scripts are written for [Bash](https://www.gnu.org/software/bash/) and must be executed in this shell. They are designed for and tested on **Arch Linux** only!

Also note that these scripts are not designed to accommodate all types of hardware, installation and configuration options. Installation script is made to suite a specific use case and contain configuration options that are specific for the destination computer, i.e. locale. System hardening that is performed by configuration script is not official common best practices and are subject to debate and changes in the future.

## install-arch-zfs-root.sh
This script deploys a minimal [Arch Linux](https://www.archlinux.org/) installation base with [ZFS](https://zfsonlinux.org/) on root and encryption using [dm-crypt/LUKS](https://wiki.archlinux.org/index.php/Dm-crypt).

### Disk & Partition Scheme
Script only supports a single disk drive configuration and will automatically partition the disk with the following scheme.

```
+---------------------------------------------------------------------------+
| /dev/disk/by-id/ata|nvme-Manufacturer_Model_Number                        |
+-------------------+-------------------------------------------------------+
| ESP partition:    | Linux filesystem partition:                           |
+-------------------+-------------------------------------------------------+
| 550 MB            | Remaining disk space                                  |
|                   |                                                       |
| Not encrypted     | Encrypted                                             |
+-------------------+-------------------------------------------------------+
```

Script is designed to be used on a [UEFI](https://wiki.archlinux.org/index.php/Unified_Extensible_Firmware_Interface) system only. No legacy BIOS support, hence no Master Boot Record (MBR) will be created.

### Disk & dm-crypt/LUKS Encrypted ZFS Pool Configuration
The [EFI System Partition](https://wiki.archlinux.org/index.php/EFI_system_partition) (ESP) is mounted to `/efi`. The root partition (`/`) is a [ZFS pool](https://wiki.archlinux.org/index.php/ZFS#Creating_ZFS_pools) (`rpool`) encrypted with [dm-crypt/LUKS](https://wiki.archlinux.org/index.php/Dm-crypt) (`crypt-root`).

```
ata|nvme-Manufacturer_Model_Number-part1
 └─ ESP (/efi)
ata|nvme-Manufacturer_Model_Number-part2
 └─ crypt-root (/)
     └─ ZFS pool (rpool)
```

### ZFS Dataset Configuration
The following [ZFS datasets](https://wiki.archlinux.org/index.php/ZFS#Creating_datasets) will be automatically created during installation.

| **Name**                |  **Mountpoint**    |
| ---                     | ---                |
| `rpool`                 | `/`                |
| `rpool/ROOT`            | none               |
| `rpool/ROOT/arch`       | `/`                |
| `rpool/home`            | `/home`            |
| `rpool/home/root`       | `/root`            |
| `rpool/opt`             | `/opt`             |
| `rpool/srv`             | `/srv`             |
| `rpool/usr`             | `/usr`             |
| `rpool/usr/local`       | `/usr/local`       |
| `rpool/var`             | `/var`             |
| `rpool/var/cache`       | `/var/cache`       |
| `rpool/var/lib`         | `/var/lib`         |
| `rpool/var/lib/libvirt` | `/var/lib/libvirt` |
| `rpool/var/log`         | `/var/log`         |
| `rpool/var/tmp`         | `/var/tmp`         |

### Prerequisite
Installation is performed using the Arch Linux instalation image ([archiso](https://wiki.archlinux.org/index.php/Archiso)).

It must however be embedded with the [archzfs](https://github.com/archzfs/archzfs) packages. Consult the Arch wiki for [instructions](https://wiki.archlinux.org/index.php/ZFS#Embed_the_archzfs_packages_into_an_archiso) on creating a custom archiso image with archzfs packages.

An alternative to building a custom archiso image is to download the pre-built [image](https://github.com/danboid/ALEZ/releases) from the [ALEZ](https://github.com/danboid/ALEZ) project, as it already contains archzfs packages.

### Preperation
Prior to script execution, boot the **Arch Linux installation image** that has the **archzfs** packages embedded (see prerequisites above).

Update repositories in the Arch Linux live environment.
```
# pacman -Sy --noconfirm
```

Install **Git**.
```
# pacman -S --noconfirm git
```

Download Git repository.
```
# git clone https://github.com/pwyde/deploy-arch-linux.git
# cd deploy-arch-linux
```

### Usage
Start the scripted installation.
```
# bash install-arch-zfs-root.sh --install
```

### Options
| **Option**            | **Description**                                                |
| ---                   | ---                                                            |
| `-i`,`--install`      | Performs installation and configuration on destination system. |
| `-p`,`--post-install` | Performs post-installation configuration. This option is only used when performing configuration in the chroot environment. Should __NOT__ be used when executing script. |
| `-h`,`--help`         | Display help message including available options.              |

### Limitations
The resulting Arch Linux installation with ZFS on root contains a few configuration options that must be known and cannot or should not be changed in the future.
- The `encrypt` [hook](https://wiki.archlinux.org/index.php/mkinitcpio#Common_hooks) only allows for a [single encrypted disk](https://wiki.archlinux.org/index.php/Dm-crypt/Specialties#The_encrypt_hook_and_multiple_disks). Hence a ZFS pool mirror/raidz is not possible with two or more LUKS encrypted drives.
- The `systemd` hook [cannot be used](https://wiki.archlinux.org/index.php/Install_Arch_Linux_on_ZFS#Install_and_configure_Arch_Linux) when creating the initramfs image with `mkinitcpio` command. If systemd is used in the initramfs, the AUR package [`mkinitcpio-sd-zfs`](https://aur.archlinux.org/packages/mkinitcpio-sd-zfs/) must be installed and the `zfs` hook must be changed to `sd-zfs`. Keep in mind that this hook uses different kernel parameters than the default `zfs` hook. Also note that this package has not received any updates during the last couple of years. The developer has also stated on the GitHub [project page](https://github.com/dasJ/sd-zfs) that he is [not actively maintaining it anymore](https://github.com/dasJ/sd-zfs/issues/28#issuecomment-432738232).

There are also other considerations that should be taken into account on the resulting system.
- Due to limitations of the [ESP](https://wiki.archlinux.org/index.php/EFI_system_partition#Format_the_partition) and boot loader [(systemd-boot)](https://wiki.archlinux.org/index.php/Systemd-boot), a copy of the Linux kernel and initramfs image will be stored on the non-encrypted partition. The copy procedure is handled automoatically by the [custom systemd service unit](https://wiki.archlinux.org/index.php/EFI_system_partition#Using_systemd) named [`update-esp.path`](etc/systemd/system/update-esp.path). This makes the resulting system subject to [Evil Maid attacks](https://en.wikipedia.org/wiki/Evil_maid_attack) due to the exposed kernel and initramfs image. This should be mitigated by enabling [Secure Boot](https://wiki.archlinux.org/index.php/Secure_Boot) and preferably with [custom keys](https://wiki.archlinux.org/index.php/Secure_Boot#Using_your_own_keys). The AUR packages [`cryptboot`](https://aur.archlinux.org/packages/cryptboot/) and [`sbupdate`](https://aur.archlinux.org/packages/sbupdate-git/) can assist with this procedure.

## configure-arch-linux.sh
Script performs post-deployment configuration on a newly installed Arch Linux system. Used for installing utilities/tools and basic system hardening.

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
- Configure swappiness.
- Disable core dumps.
- Set a timeout for sudo sessions.
- TCP/IP stack hardening.
- Restrict access to kernel logs.
- Disable Speck kernel module.
- Secure kernel pointers in /proc filesystem.
- Restrict access to ptrace.
- Hide PIDs.

Script can also automatically install [`yay`](https://aur.archlinux.org/packages/yay/) as the preferred AUR helper if the `--aur-helper` option is specified (optional).

### Options
| **Option**          | **Description**                                               |
| ---                 | ---                                                           |
| `-c`,`--configure`  | Apply system configuration and hardening included in script.  |
| `-a`,`--aur-helper` | Install preferred AUR helper (yay).                           |
| `-h`,`--help`       | Display help message including available options.             |

## Credits
Script is based from and inspired by the following sources:
- [Arch Linux on an encrypted ZFS root system](https://aaronlauterer.com/blog/2017/04/arch-linux-on-an-encrypted-zfs-root-system/)
- [Arch Linux on ZFS - Part 1: Embed ZFS in Archiso](https://ramsdenj.com/2016/06/23/arch-linux-on-zfs-part-1-embed-zfs-in-archiso.html)
- [Arch Linux on ZFS - Part 2: Installation](https://ramsdenj.com/2016/06/23/arch-linux-on-zfs-part-2-installation.html)
- [Arch Linux on ZFS - Part 3: Backups, Snapshots and Other Features](https://ramsdenj.com/2016/08/29/arch-linux-on-zfs-part-3-followup.html)
- [Ubuntu 18.04 Root on ZFS](https://github.com/zfsonlinux/zfs/wiki/Ubuntu-18.04-Root-on-ZFS)

## References
- [Arch Linux Wiki: ZFS](https://wiki.archlinux.org/index.php/ZFS)
- [Arch Linux Wiki: Install Arch Linux on ZFS](https://wiki.archlinux.org/index.php/Install_Arch_Linux_on_ZFS)

## License
This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for more information.
