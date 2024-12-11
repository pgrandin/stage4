#!/bin/bash

if yq '.features[] | select(. == "X")' /config.yml | grep -q X; then
    echo "X is present in features, building browsers"
    emerge -q www-client/firefox
    emerge -q www-client/chromium
else
    echo "X is not present in features, not building browsers"
fi
