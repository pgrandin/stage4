#!/bin/bash
export FEATURES="-collision-protect"

# Update portage first. emerge -e @world rebuilds sys-apps/portage too, and
# when a newer portage has landed in the tree, portage upgrading itself
# mid-run aborts the whole emerge ("exiting unsuccessfully with status 1")
# — which killed the rebuild at ~616/877. Bringing portage current up front
# means the @world pass rebuilds the same version and doesn't self-upgrade.
emerge -1uq sys-apps/portage

# MAKEOPTS is resource-aware now: the CI step sizes it to the runner's real
# memory limit in make.conf, and package.env caps known memory-hog packages
# (e.g. media-gfx/blender) further. Don't override it here with a core-only
# -j$(nproc), which oversubscribes RAM and OOM-kills heavy compiles.
emerge -eq @world --jobs 4 --load-average "$(nproc)"
