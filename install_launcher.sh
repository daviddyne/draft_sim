#!/usr/bin/env bash
# Run from the draft_sim project root: bash install_launcher.sh
# Rebuilds the app, installs the icon, desktop entry and the launch script Heroic uses
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

# Launch script: raises the running window instead of starting a second copy
LAUNCH="$HOME/.local/bin/draft-sim-launch"
mkdir -p "$HOME/.local/bin"
cat > "$LAUNCH" << LAUNCHER
#!/usr/bin/env bash
# Starts Draft Sim, or focuses it if it is already running
if pgrep -x draft_sim > /dev/null; then
  if command -v wmctrl > /dev/null; then
    wmctrl -x -a com.example.draft_sim || wmctrl -a "Draft Sim" || true
  fi
  exit 0
fi
nohup "$BIN" > /dev/null 2>&1 &
disown
exit 0
LAUNCHER
chmod +x "$LAUNCH"

# GNOME matches a window to its launcher by the app id, which xprop reports as
# WM_CLASS, so both the file name and StartupWMClass must be that id
APP_ID=$(grep -oP 'APPLICATION_ID\s+"\K[^"]+' linux/CMakeLists.txt || echo draft_sim)
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
# Remove earlier attempts so only one launcher claims the app
rm -f "$DESKTOP_DIR/draft-sim.desktop" "$DESKTOP_DIR/draft_sim.desktop"
cat > "$DESKTOP_DIR/$APP_ID.desktop" << DESKTOP
[Desktop Entry]
Name=Draft Sim
Comment=17lands draft practice
Exec=$LAUNCH
Icon=draft_sim
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=$APP_ID
SingleMainWindow=true
DESKTOP

update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo "Installed as $DESKTOP_DIR/$APP_ID.desktop (StartupWMClass=$APP_ID)"
echo "Unpin the old icon, launch from the Zorin menu, then pin the running window."
echo "Heroic: set the wrapper command to $LAUNCH"