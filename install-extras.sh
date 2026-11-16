#!/bin/bash
# Explicitly opt an installed public edition into one optional proprietary application.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
case ${1:-} in
    slack) atom=net-im/slack; license=all-rights-reserved ;;
    spotify) atom=media-sound/spotify; license=Spotify ;;
    cuda) atom=dev-util/nvidia-cuda-toolkit; license=NVIDIA-CUDA ;;
    *) echo "usage: install-stage4-extras <slack|spotify|cuda>" >&2; exit 1 ;;
esac
echo "Installing $atom under its $license license; this installation will no longer match the public image audit."
mask=/etc/portage/package.mask/stage4-public
if [[ -f $mask ]]; then
    awk -v atom="$atom" '$0 != atom' "$mask" > "$mask.new"
    mv "$mask.new" "$mask"
fi
mkdir -p /etc/portage/package.license
printf '%s %s\n' "$atom" "$license" > "/etc/portage/package.license/stage4-extra-${1}"
# Fetch from upstream and leave these applications out of binary package production.
emerge --ask --accept-restrict='*' --buildpkg=n --getbinpkg=n --usepkg=n "$atom"
