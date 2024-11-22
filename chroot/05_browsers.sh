#!/bin/bash

set -e

target=$1
[[ -z ${target} ]] && exit 1

if yq '.features[] | select(. == "X")' /config.yml >/dev/null 2>&1; then
    echo "X is present in features, building browsers"
    emerge -q www-client/firefox
    emerge -q www-client/chromium
else
    echo "X is not present in features, not building browsers"
fi

