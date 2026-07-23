#!/bin/sh
#!/bin/bash
set -euo pipefail

DEST="/Applications/${WRAPPER_NAME}"

echo "Installing ${WRAPPER_NAME}..."

rm -rf "$DEST"
ditto "${TARGET_BUILD_DIR}/${WRAPPER_NAME}" "$DEST"

echo "Installed successfully."

