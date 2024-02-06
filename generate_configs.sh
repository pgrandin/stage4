#!/bin/bash

# Path to the config.yml file
CONFIG_FILE="config.yml"

# Path to the Jinja2 template
TEMPLATE_FILE="make.conf.j2"

# Extract keys (hostnames) from the YAML file
# The following command gets the top-level keys in the YAML file
KEYS=$(yq e '. | keys | .[]' "${CONFIG_FILE}")

# Iterate over each key and process it
for key in ${KEYS}; do
    if [[ "${key}" != "null" && ! -z "${key}" ]]; then
        # Generate temporary YAML file for the current key
        TEMP_YAML_FILE="temp_${key}.yml"
        yq e ".${key}" "${CONFIG_FILE}" > "${TEMP_YAML_FILE}"

        # Define the output file path
        OUTPUT_FILE="files/${key}/etc/portage/make.conf"

        # Ensure the output directory exists
        mkdir -p "$(dirname "${OUTPUT_FILE}")"

        # Run j2 using the temporary YAML file
        j2 "${TEMPLATE_FILE}" "${TEMP_YAML_FILE}" > "${OUTPUT_FILE}"

        echo "Generated configuration for ${key} in ${OUTPUT_FILE}"

        # Clean up the temporary file
        rm -f "${TEMP_YAML_FILE}"
    fi
done
