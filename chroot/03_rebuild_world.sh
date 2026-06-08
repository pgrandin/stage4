#!/bin/bash
export FEATURES="-collision-protect"

# Build portage up front, then rebuild @world EXCLUDING it. emerge -e @world
# rebuilds sys-apps/portage in-place (emptytree rebuilds everything, even the
# same version), and portage re-merging itself mid-run aborts the whole emerge
# ("exiting unsuccessfully with status 1", "terminating") at ~616/877 — it
# wants you to restart under the new portage. Building portage separately and
# excluding it from the -e pass keeps it current without the self-rebuild abort.
emerge -1uq sys-apps/portage

# MAKEOPTS is resource-aware now: the CI step sizes it to the runner's real
# memory limit in make.conf, and package.env caps known memory-hog packages
# (e.g. media-gfx/blender) further. Don't override it here with a core-only
# -j$(nproc), which oversubscribes RAM and OOM-kills heavy compiles.
emerge -eq @world --jobs 4 --load-average "$(nproc)" --exclude sys-apps/portage
