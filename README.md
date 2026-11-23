# stage4
This repository contains my automated build system for creating customized Gentoo Linux Stage4 tarballs. I built this to maintain reproducible Gentoo installations across my various systems. While the configurations are specific to my hardware, the build system is designed to be easily expandable for other targets.

# Purpose
The main goals of this project are:

- Automate the build process for my personal Gentoo systems
- Ensure reproducible builds across different machines, and allow consistent settings between hosts that share similar purposes
- Make it easy to add new systems to the automation
- Maintain a central repository of binary packages for faster deployment (and not having to deal with emerge issues on the target system)
- Track all configuration changes in version control

# Features

- Automated Build Pipeline: GitHub Actions workflow handles regular rebuilds
- Binary Package Management: Shared runner cache backed by the public SourceForge binhost
- Custom Kernel Configurations: Hardware-specific kernel configs for each of my machines
- Flexible Configuration: Uses Jinja2 templating for make.conf generation
- Modular Design: Easy to add new systems or modify existing ones

# Project Structure
```
.
├── chroot/            # Chroot environment scripts
├── files/            # Target-specific configurations
│   ├── common/       # Shared configuration files
│   └── [target]/     # Target-specific files
├── packages/         # Package-specific configurations
└── dockr/            # Docker build environment
```

# Hardware Related Features
Configure hardware support through:

- CPU flags in make.conf
- USE flags for specific features
- Kernel configuration fragments (see also [kernel-configs](https://github.com/pgrandin/kernel-configs) repository)
- Package-specific settings

# GitHub Actions Build
The repository includes a GitHub Actions workflow that automatically builds Stage4 images. The workflow:

- Runs daily to ensure packages stay updated, and new breakages are caught early
- Runs script checks for pull requests and builds the public XPS-9730 image from `master`
- Reuses compatible binary packages from the shared runner cache and SourceForge
- Publishes the image, kernel archive and audited binary packages to SourceForge

# Build checkpoints

Each target has an active checkpoint at `/scratch/builds/sourceforge/.checkpoints/<target>/active`
on shared NFS storage, outside the runner's disposable filesystem. Scheduled
builds, new commits, and retries select the unfinished checkpoint even when the
GitHub run ID or runner changes. Builds for a target run one at a time.

The checkpoint retains the installed filesystem, package database, binary cache,
Portage's saved merge list, and completed stage markers. Bootstrap, kernel, and
quirks stages are skipped after success; an interrupted world build uses
`emerge --resume`. An interrupted package may need to restart, while completed
packages remain installed. Missing or damaged resume data fails visibly instead
of silently starting another empty-tree rebuild.

The checkpoint remains active until validation and image/checksum uploads succeed.
The following run then starts a fresh image. Build configuration changes also
require an explicit fresh build; workflow and script fixes can resume existing
state. To intentionally start over while retaining the old checkpoint:

```
gh workflow run main.yml --repo pgrandin/stage4 -f fresh=true
```

`build_checkpoint.py --adopt <existing-build-directory>` can register a legacy
build that has already reached the world stage (also pass its target and run ID).
Checkpoint tests run with `python3 -m unittest discover -s tests`.

# Installing on a fresh machine

1. Write the [Gentoo minimal install ISO](https://distfiles.gentoo.org/releases/amd64/autobuilds/current-install-amd64-minimal/)
   to a USB key (`dd if=install-amd64-minimal-*.iso of=/dev/sdX bs=4M`) and boot it in UEFI mode.
2. Bring the network up: `dhcpcd`, or `net-setup` for Wi-Fi.
3. Install. This erases the whole disk:
   ```sh
   curl -fsSLO https://raw.githubusercontent.com/pgrandin/stage4/master/install.sh
   bash install.sh /dev/nvme0n1          # optional 2nd argument: target, default XPS-9730
   ```
4. Set a root password when the installer prompts, then remove the USB key and reboot.

The disk gets a 1 GiB ESP and an ext4 root. The kernel boots from the ESP as an
EFI stub (no GRUB, no initramfs) and finds root through the `root=PARTUUID=`
built into its config, so `install.sh` gives the root partition that PARTUUID.

# Chromium and Blender via Flatpak

The XPS-9730 image includes native Firefox and the system-wide Chromium Flatpak
from Flathub (`org.chromium.Chromium`). Each image build installs or updates
Chromium, and validation requires it. Chromium updates on an installed system
come from Flathub:

```sh
flatpak run org.chromium.Chromium
sudo flatpak update --system org.chromium.Chromium
```

Chromium's Flatpak listing: https://flathub.org/apps/org.chromium.Chromium

Native Chromium and Blender packages are excluded. Flatpak and the GTK desktop
portal are included for the i3 desktop. After booting the image, install Blender
for your desktop user:

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.blender.Blender
flatpak run org.blender.Blender
```

Blender's Flatpak listing: https://flathub.org/en/apps/org.blender.Blender

# License
This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.

# Public distribution

SourceForge hosts the nightly images and individual binary packages:
https://sourceforge.net/projects/stage4-gentoo/files/

The public edition excludes Slack, Spotify and the NVIDIA CUDA toolkit. Its
Portage configuration disables CUDA consumers and masks the optional applications.
After installation, explicitly add an application with
`install-stage4-extras slack`, `install-stage4-extras spotify`, or
`install-stage4-extras cuda`. These commands fetch from upstream, prompt before
installing, and do not produce binary packages for redistribution. Installing the
CUDA toolkit does not enable CUDA globally for other packages.

The nightly applies the public policy before building and audits every installed
package before archiving. To convert an older personal image, run
`sudo bash make-public.sh /path/to/public-copy` on a separate copy with `/proc`,
`/dev`, `/var/cache` and `/var/tmp` mounted. A manifest is saved as
`/usr/share/stage4/installed-packages.json` inside the image. The audit uses
Gentoo's `@FREE` licenses without personal license overrides, rejects `bindist`
packages, and permits redistributable firmware for hardware support. Firmware
retains its individual licenses; this is not a firmware-free distribution.

Portage's binhost is https://downloads.sourceforge.net/project/stage4-gentoo/binpkgs/XPS-9730/.
Each nightly uploads newly audited packages, then advances the `Packages` index
after SourceForge serves those files. Older indexes can still use their original
package files. Build logs and retry state stay on the shared runner volume.
The publish step uses `SOURCEFORGE_SSH_KEY` from the `sourceforge` GitHub environment,
which allows deployments from `master`.

The installer reads the current image revision from
https://downloads.sourceforge.net/project/stage4-gentoo/images/XPS-9730/latest.txt
and checks the archive's SHA-256. Use `STAGE4_URL` with a direct tarball URL and
its matching `.md5` to install a specific revision. The public image locks root
and clears machine identity. The installer generates a fresh machine ID and
prompts for a root password before unmounting the installation.
