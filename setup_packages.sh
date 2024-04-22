#!/bin/bash

# get world_file from arg 1
world_file=$1

if [ ! -f "$world_file" ]; then
    echo "The world file does not exist."
    exit 1
fi

# Navigate to the packages directory
cd packages

# Loop through each folder and its first-level subfolder
for folder in */*; do
    # Check if the folder is a directory
    if [ -d "$folder" ]; then
        echo -n "$folder: "
        # Check if the line is present in the world file
        if grep -qx "$folder" "$world_file"; then
            echo "$folder is present in the world file, installing portage config"
            rsync -vrtza $folder/ /etc/portage/
        else
            echo "$folder is not present in the world file, skipping."
        fi
    fi
done
