#!/usr/bin/env bash
# Run from the draft_sim project root: bash install_launcher.sh
# Builds the release binary and adds Draft Sim to the app menu so it can be pinned to the taskbar
set -e

PROJECT_DIR="$(pwd)"
if [ ! -f "$PROJECT_DIR/pubspec.yaml" ]; then
  echo "Run this from the draft_sim project root"
  exit 1
fi

flutter build linux --release
BIN="$PROJECT_DIR/build/linux/x64/release/bundle/draft_sim"

# Icon goes into the user icon theme, expects draft_sim.png next to this script
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
mkdir -p "$ICON_DIR"
cp "$PROJECT_DIR/draft_sim.png" "$ICON_DIR/draft_sim.png"

# Desktop entry makes the app show up in the Zorin menu
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/draft-sim.desktop" << DESKTOP
[Desktop Entry]
Name=Draft Sim
Comment=17lands draft practice
Exec=$BIN
Icon=draft_sim
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=draft_sim
DESKTOP

update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo "Installed. Find 'Draft Sim' in the Zorin menu, then right-click it and pin it to the taskbar."
