#!/usr/bin/env bash
# Idempotent bootstrap for the Token Runner (Godot) project.
# - Installs the pinned Godot engine if it is missing.
# - Generates procedural assets and imports resources so the project is runnable.
set -euo pipefail

GODOT_VERSION="4.7.2"
GODOT_BIN="/usr/local/bin/godot"
GODOT_NAME="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${GODOT_NAME}.zip"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

current_version() {
  command -v godot >/dev/null 2>&1 || return 1
  godot --version 2>/dev/null | cut -d. -f1-3
}

# Runtime libraries needed for OpenGL/X11 rendering (e.g. computer-use, xvfb).
# Headless smoke tests work without these, so failure here is non-fatal.
echo ">> Ensuring Godot runtime libraries are present..."
sudo apt-get update -y >/dev/null 2>&1 || true
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl unzip \
  libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libxext6 \
  libgl1 libglu1-mesa libxkbcommon0 libfontconfig1 libudev1 \
  libasound2t64 xvfb >/dev/null 2>&1 || \
  echo "   (apt install of optional libs failed; headless mode will still work)"

if [ "$(current_version || true)" != "${GODOT_VERSION}" ]; then
  echo ">> Installing Godot ${GODOT_VERSION}..."
  tmp="$(mktemp -d)"
  curl -fL --retry 4 --retry-delay 4 -o "${tmp}/godot.zip" "${GODOT_URL}"
  unzip -q -o "${tmp}/godot.zip" -d "${tmp}"
  chmod +x "${tmp}/${GODOT_NAME}"
  sudo mv "${tmp}/${GODOT_NAME}" "${GODOT_BIN}"
  rm -rf "${tmp}"
else
  echo ">> Godot ${GODOT_VERSION} already installed."
fi

godot --version

cd "${PROJECT_DIR}"

echo ">> Generating procedural assets..."
godot --headless --path . --script scripts/tools/run_generate.gd

echo ">> Importing project resources..."
godot --headless --path . --import

echo ">> Install complete."
