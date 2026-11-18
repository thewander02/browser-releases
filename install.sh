#!/bin/sh
# Sprout installer.
#
#   curl -fsSL https://raw.githubusercontent.com/thewander02/browser-releases/main/install.sh | sh
#
# Options:  -c main|nightly   channel to install (default: main)
#
# Also runs inside an extracted release tarball (sprout-*/), where it
# installs that build directly.
#
# Installs to ~/.local/share/sprout/installs (macOS: ~/Library/Application
# Support/sprout/installs), drops `sprout` on ~/.local/bin, and adds a
# .desktop entry on Linux or ~/Applications/Sprout.app on macOS (with the
# Gatekeeper quarantine flag removed, since builds are unsigned).
set -eu

channel=main
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--channel) channel=$2; shift 2 ;;
    *) channel=$1; shift ;;
  esac
done
case "$channel" in main|nightly) ;; *) echo "install.sh: unknown channel '$channel' (main|nightly)" >&2; exit 1 ;; esac

OS="$(uname -s)"
case "$OS" in
  Darwin) base="$HOME/Library/Application Support/sprout" ;;
  Linux)  base="${XDG_DATA_HOME:-$HOME/.local/share}/sprout" ;;
  *) echo "install.sh: unsupported OS $OS" >&2; exit 1 ;;
esac
installs="$base/installs"

here=$(cd -P "$(dirname "$0")" 2>/dev/null && pwd || pwd)

# --- Standalone mode: fetch the channel's manifest, download, extract, re-run inside.
# (An extracted artifact is identified by run.sh + dist/main.cjs, not run.sh alone —
# the script also lives next to run.sh in the source repo.)
if [ ! -f "$here/run.sh" ] || [ ! -f "$here/dist/main.cjs" ]; then
  case "$(uname -m)" in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) echo "install.sh: unsupported arch $(uname -m)" >&2; exit 1 ;;
  esac
  case "$OS" in
    Darwin) [ "$arch" = arm64 ] || { echo "install.sh: no macOS Intel build" >&2; exit 1; }; plat=macos-arm64 ;;
    Linux)  [ "$arch" = x64 ]   || { echo "install.sh: no Linux ARM build" >&2; exit 1; };  plat=linux-x64 ;;
  esac

  repo="https://github.com/thewander02/browser-releases"
  echo "==> fetching $channel manifest"
  manifest=$(curl -fsSL "$repo/releases/download/$channel/manifest.json") || {
    echo "install.sh: no '$channel' release yet (or network error)" >&2; exit 1; }
  file=$(printf '%s' "$manifest" | grep -o "\"$plat\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4)
  [ -n "$file" ] || { echo "install.sh: no $plat build on $channel" >&2; exit 1; }

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "==> downloading $file"
  curl -fSL --progress-bar "$repo/releases/download/$channel/$file" -o "$tmp/release.tar.gz"
  tar -xzf "$tmp/release.tar.gz" -C "$tmp"
  # The extracted dir contains its own copy of this script in local mode.
  # (Not exec: the EXIT trap must still remove $tmp afterwards.)
  sh "$tmp"/sprout-*/install.sh
  exit
fi

# --- Local mode: $here is the extracted release directory.
name=$(basename "$here")
mkdir -p "$installs" "$HOME/.local/bin"

dest="$installs/$name"
rm -rf "$dest"
mkdir -p "$dest"
cp -R "$here"/. "$dest"/
chmod +x "$dest/run.sh" "$dest/node" 2>/dev/null || true
[ "$OS" = "Darwin" ] || chmod +x "$dest/host/sprout"

# Stable launcher: reads installs/current and execs that install's run.sh. $0 may
# be the ~/.local/bin symlink, so resolve it (macOS readlink has no -f).
cat > "$installs/sprout" <<'EOF'
#!/bin/sh
self=$0
while [ -L "$self" ]; do
  d=$(cd -P "$(dirname "$self")" && pwd)
  self=$(readlink "$self")
  case "$self" in /*) ;; *) self="$d/$self" ;; esac
done
here=$(dirname "$self")
dir=$(cat "$here/current" 2>/dev/null) || { echo "sprout: no installed build" >&2; exit 1; }
exec "$here/$dir/run.sh" "$@"
EOF
chmod +x "$installs/sprout"
echo "$name" > "$installs/current"
ln -sf "$installs/sprout" "$HOME/.local/bin/sprout"
# Point the old `os-browser` command at the new install too (it's our symlink).
if [ -L "$HOME/.local/bin/os-browser" ] && readlink "$HOME/.local/bin/os-browser" | grep -q "os-browser/installs/os-browser$"; then
  ln -sf "$installs/sprout" "$HOME/.local/bin/os-browser"
fi

if [ "$OS" = "Darwin" ]; then
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
  app="$HOME/Applications/Sprout.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Sprout</string>
  <key>CFBundleIdentifier</key><string>io.github.thewander02.sprout.launcher</string>
  <key>CFBundleExecutable</key><string>Sprout</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
</dict></plist>
EOF
  cat > "$app/Contents/MacOS/Sprout" <<EOF
#!/bin/sh
exec "$installs/sprout" "\$@"
EOF
  chmod +x "$app/Contents/MacOS/Sprout"
  # Every colorway ships, so Settings → Appearance can swap AppIcon.icns later.
  cp "$dest/sprout.app/Contents/Resources/AppIcon-"*.icns "$app/Contents/Resources/" 2>/dev/null || true
  cp "$app/Contents/Resources/AppIcon-moss.icns" "$app/Contents/Resources/AppIcon.icns" 2>/dev/null || true
  # Remove the pre-rename launcher: it execs into os-browser installs and has no icon.
  if grep -q "os-browser.launcher" "$HOME/Applications/Browser.app/Contents/Info.plist" 2>/dev/null; then
    rm -rf "$HOME/Applications/Browser.app"
  fi
  echo "Installed $name"
  echo "Run: sprout   (also ~/Applications/Sprout.app)"
else
  apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  mkdir -p "$apps"
  icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/512x512/apps"
  mkdir -p "$icons"
  cp "$here"/host/icons/sprout-*.png "$icons/" 2>/dev/null || true
  # Default colorway is moss; sprout.png is the icon the .desktop entry points at.
  cp "$icons/sprout-moss.png" "$icons/sprout.png" 2>/dev/null || cp "$here/host/sprout.png" "$icons/sprout.png" 2>/dev/null || true
  cat > "$apps/sprout.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sprout
Exec=$installs/sprout %U
Icon=sprout
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
EOF
  echo "Installed $name"
  echo "Run: sprout   (make sure ~/.local/bin is on your PATH)"
fi
