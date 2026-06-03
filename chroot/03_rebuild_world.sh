#!/bin/bash
export FEATURES="-collision-protect"
# MAKEOPTS is resource-aware now: the CI step sizes it to the runner's real
# memory limit in make.conf, and package.env caps known memory-hog packages
# (e.g. media-gfx/blender) further. Don't override it here with a core-only
# -j$(nproc), which oversubscribes RAM and OOM-kills heavy compiles.
emerge -eq @world --jobs 4 --load-average "$(nproc)"
