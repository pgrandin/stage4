#!/bin/bash

set -e

target=$1
[[ -z ${target} ]] && exit 1

if yq '.features | any(. == "X")' /config.yml >/dev/null; then
    echo "X is present in features, building browsers"
    emerge -q www-client/firefox
    emerge -q www-client/chromium
else
    echo "X is not present in features, not building browsers"
fi
