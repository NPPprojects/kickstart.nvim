
#!/bin/bash

INPUT_FILE="$HOME/.config/nvim/lua/custom/plugins/mason-lsps.txt"

if [ ! -f "$INPUT_FILE" ]; then
  echo "LSP list file not found: $INPUT_FILE"
  exit 1
fi

echo "Installing Mason packages listed in $INPUT_FILE..."

while IFS= read -r package; do
  if [[ -n "$package" ]]; then
    echo "→ Installing $package"
    nvim --headless "+MasonInstall $package" +qa
  fi
done < "$INPUT_FILE"

echo "Done."
