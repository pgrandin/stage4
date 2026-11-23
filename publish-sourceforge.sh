#!/bin/bash
# Publish a prepared XPS release and advance the installer's pointer last.
set -euo pipefail

target=${1:?target required}
root=${2:?audited stage4 root required}
release=${3:?release directory required}
revision=${4:?run ID and attempt required}
[[ $target == XPS-9730 && $revision =~ ^[0-9]+-[0-9]+$ ]]
[[ -f $root/etc/stage4-public && -s $root/usr/share/stage4/installed-packages.json ]]
: "${SOURCEFORGE_SSH_KEY:?configure the SourceForge environment secret}"

umask 077
key=$(mktemp /dev/shm/stage4-sourceforge.XXXXXX)
trap 'rm -f "$key"' EXIT
printf '%s\n' "$SOURCEFORGE_SSH_KEY" > "$key"
unset SOURCEFORGE_SSH_KEY
umask 022
known_hosts=$(realpath "$(dirname -- "$0")/sourceforge-known-hosts")
ssh_options=(-i "$key" -o IdentitiesOnly=yes -o BatchMode=yes
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts"
    -o ConnectTimeout=20 -o ServerAliveInterval=30)
printf -v rsync_ssh '%q ' ssh "${ssh_options[@]}"
host=kazer_@frs.sourceforge.net
project=/home/frs/project/stage4-gentoo
downloads=https://downloads.sourceforge.net/project/stage4-gentoo
image_path=images/$target/$revision
binhost_path=binpkgs/$target
staged=$release/binpkgs
image=$target-public-stage4.tgz
bundle=$release/$revision
mkdir -p "$bundle"

# SourceForge requires files to be under 10 GB for mirror downloads.
tar --xattrs --acls --numeric-owner -czf "$bundle/$image.part" -C "$root" .
if (( $(stat -c %s "$bundle/$image.part") >= 10000000000 )); then
    echo 'Stage4 archive exceeds SourceForge mirror size limit' >&2
    exit 1
fi
mv "$bundle/$image.part" "$bundle/$image"
cp "$root/usr/share/stage4/installed-packages.json" "$bundle/"
commit=$(git rev-parse HEAD)
git archive --format=tar.gz --prefix=stage4/ -o "$bundle/stage4-source.tar.gz" "$commit"
printf 'Build source %s\nRun https://github.com/pgrandin/stage4/actions/runs/%s\n' \
    "$commit" "${revision%-*}" > "$bundle/README.txt"
(cd "$bundle" && sha256sum "$image" stage4-source.tar.gz > SHA256SUMS &&
    sha256sum "$image" > "$image.sha256" && md5sum "$image" > "$image.md5")

sftp "${ssh_options[@]}" -b - "$host" <<EOF
-mkdir $project/$image_path
EOF

upload=(rsync -rt --partial-dir=.rsync-partial -e "$rsync_ssh")
"${upload[@]}" --relative --files-from="$staged/upload-files.txt" "$staged/" "$host:$project/$binhost_path/"
"${upload[@]}" "$bundle/" "$root"/kernel-*.tgz "$host:$project/$image_path/"

wait_for_size() {
    local file=$1 url=$2 size attempt
    size=$(stat -c %s "$file")
    for ((attempt=1; attempt<=40; attempt++)); do
        if [[ $(curl -fsSLI --max-time 20 -o /dev/null -w '%header{content-length}' "$url") == "$size" ]]; then
            return
        fi
        sleep 15
    done
    echo "SourceForge did not serve $url ($size bytes)" >&2
    return 1
}

# Readers of a cached index must still be able to fetch the bytes it names.
while IFS= read -r pkg; do
    wait_for_size "$staged/$pkg" "$downloads/$binhost_path/$pkg"
done < "$staged/upload-files.txt"
for file in "$bundle"/* "$root"/kernel-*.tgz; do
    wait_for_size "$file" "$downloads/$image_path/${file##*/}"
done

"${upload[@]}" "$staged/excluded-packages.json" "$host:$project/$binhost_path/"
"${upload[@]}" --checksum "$staged/Packages" "$host:$project/$binhost_path/"
for ((attempt=1; attempt<=40; attempt++)); do
    if curl -fsSL --max-time 20 "$downloads/$binhost_path/Packages?run=$revision-$attempt" \
        -o "$release/Packages.remote" && cmp -s "$staged/Packages" "$release/Packages.remote"; then
        printf '%s\n' "$revision" > "$release/latest.txt"
        "${upload[@]}" --checksum "$release/latest.txt" "$host:$project/images/$target/"
        break
    fi
    sleep 15
done
if (( attempt > 40 )); then
    echo 'SourceForge did not serve the updated package index' >&2
    exit 1
fi
for ((attempt=1; attempt<=40; attempt++)); do
    if [[ $(curl -fsSL --max-time 20 "$downloads/images/$target/latest.txt?run=$revision-$attempt") == "$revision" ]]; then
        rm "$bundle/$image"
        while IFS= read -r pkg; do
            rm "$staged/$pkg"
        done < "$staged/upload-files.txt"
        echo "Published $downloads/$image_path/$image"
        exit 0
    fi
    sleep 15
done
echo 'SourceForge did not serve the latest-image pointer' >&2
exit 1
