#!/bin/bash
export FEATURES="-collision-protect"

# MAKEOPTS is resource-aware now: the CI step sizes it to the runner's real
# memory limit in make.conf, and package.env caps known memory-hog packages
# (e.g. media-gfx/blender) further. Don't override it here with a core-only
# -j$(nproc), which oversubscribes RAM and OOM-kills heavy compiles.
OPTS="--jobs 4 --load-average $(nproc)"

# emerge -e @world rebuilds sys-apps/portage in-place (emptytree rebuilds even
# the same version). Portage re-merging itself mid-run makes emerge exit with
# status 1 and save a resume list so the rest of @world runs under the new
# portage — this killed the build at 616/877. The standard handling is to
# --resume: it continues from the package after portage and finishes the set.
# (--exclude doesn't work: portage is a hard system dep, so excluding it makes
# the -e dep graph unsatisfiable and emerge bails at resolution.) A genuine
# build failure resumes once and re-fails, so the real error still surfaces.
emerge -eq @world $OPTS || emerge --resume $OPTS
