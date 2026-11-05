#!/bin/bash
set -eu
root=${1:-/}

missing=0
while read -r atom; do
    [[ -z "$atom" || "$atom" == \#* ]] && continue
    if ! portageq has_version "$root" "$atom"; then
        echo "Required world package is missing: $atom" >&2
        missing=1
    fi
done < "$root/var/lib/portage/world"
[[ "$missing" == 0 ]] || exit 1

for browser in www-client/firefox www-client/chromium; do
    if portageq has_version "$root" "$browser"; then
        echo "Unexpected browser in browser-free build: $browser" >&2
        exit 1
    fi
done

shopt -s nullglob
kernels=("$root"/kernel-*.tgz)
[[ ${#kernels[@]} -gt 0 ]] || { echo "Kernel archive is missing" >&2; exit 1; }
for kernel in "${kernels[@]}"; do
    tar -tzf "$kernel" > "$root/var/tmp/kernel-contents.txt"
    grep -q '/boot/bzImage$' "$root/var/tmp/kernel-contents.txt"
    grep -q '^lib/modules/' "$root/var/tmp/kernel-contents.txt"
done
echo "Validated world packages, browser exclusions, and kernel archive"
