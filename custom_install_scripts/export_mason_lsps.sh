#!/bin/bash

# Path to output file in your kickstart fork
OUTPUT_FILE="$HOME/.config/nvim/lua/custom/plugins/mason-lsps.txt"

# Mason registry location (default)
REGISTRY_DIR="$HOME/.local/share/nvim/mason/packages"

if [ ! -d "$REGISTRY_DIR" ]; then
  echo "Mason registry not found at $REGISTRY_DIR"
  exit 1
fi

echo "Exporting installed Mason packages to $OUTPUT_FILE..."

ls "$REGISTRY_DIR" | sort > "$OUTPUT_FILE"

echo "Done."

