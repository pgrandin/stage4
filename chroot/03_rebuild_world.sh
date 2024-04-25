#!/bin/bash
export FEATURES="-collision-protect"
export MAKEOPTS="-j$(nproc)"
emerge -eq @world --jobs 64
