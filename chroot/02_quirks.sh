#!/bin/bash

# Still needed as of 2024-11-04
USE="-udev" emerge -q1 sys-apps/util-linux

# ----- block for libvpx build issues
declare -a packages=(
  "dev-qt/qtwebengine"
  "mail-client/thunderbird"
  "media-libs/avidemux-plugins"
  "media-video/ffmpeg"
  "www-client/firefox"
)

world_file="/var/lib/portage/world"

found=false
for package in "${packages[@]}"; do
  if grep -q "$package" "$world_file"; then
    echo "Found $package in $world_file."
    found=true
  fi
done

# If any package was found, run the emerge command with a minimal environment
if [ "$found" = true ]; then
  echo "Running env -i emerge command for libvpx..."
  env -i HOSTNAME=localhost HOME=$HOME TERM=$TERM PATH=$PATH FEATURES=$FEATURES emerge -q1 media-libs/libvpx
else
  echo "No target packages found in $world_file. Skipping libvpx build."
fi
# ----- block for libvpx build issues

# dev-lang/go circular dependency
emerge -q1 dev-lang/go-bootstrap
