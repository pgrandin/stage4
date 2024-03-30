#!/bin/bash

MAKEOPTS="-j$(nproc)" emerge -eq @world --jobs 64
