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
- Binary Package Management: Integrated with S3 for efficient package storage and reuse
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
- Builds each target in parallel
- Stores binary packages in S3
- Creates new Stage4 tarballs for quick and easy paving of systems

# Build checkpoints

Each target has an active checkpoint at `/scratch/builds/.checkpoints/<target>/active`
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

# License
This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.
