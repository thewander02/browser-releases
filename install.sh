#!/bin/sh
# OS Browser installer.
#
#   curl -fsSL https://raw.githubusercontent.com/thewander02/browser-releases/main/install.sh | sh
#
# Options:  -c main|nightly   channel to install (default: main)
#
# Also runs inside an extracted release tarball (os-browser-*/), where it
# installs that build directly.
#
# Installs to ~/.local/share/os-browser/installs (macOS: ~/Library/Application
# Support/os-browser/installs), drops `os-browser` on ~/.local/bin, and adds a
# .desktop entry on Linux or ~/Applications/Browser.app on macOS (with the
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
  Darwin) base="$HOME/Library/Application Support/os-browser" ;;
  Linux)  base="${XDG_DATA_HOME:-$HOME/.local/share}/os-browser" ;;
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
  sh "$tmp"/os-browser-*/install.sh
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
[ "$OS" = "Darwin" ] || chmod +x "$dest/host/os-browser"

# Stable launcher: reads installs/current and execs that install's run.sh. $0 may
# be the ~/.local/bin symlink, so resolve it (macOS readlink has no -f).
cat > "$installs/os-browser" <<'EOF'
#!/bin/sh
self=$0
while [ -L "$self" ]; do
  d=$(cd -P "$(dirname "$self")" && pwd)
  self=$(readlink "$self")
  case "$self" in /*) ;; *) self="$d/$self" ;; esac
done
here=$(dirname "$self")
dir=$(cat "$here/current" 2>/dev/null) || { echo "os-browser: no installed build" >&2; exit 1; }
exec "$here/$dir/run.sh" "$@"
EOF
chmod +x "$installs/os-browser"
echo "$name" > "$installs/current"
ln -sf "$installs/os-browser" "$HOME/.local/bin/os-browser"

if [ "$OS" = "Darwin" ]; then
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
  app="$HOME/Applications/Browser.app"
  mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Browser</string>
  <key>CFBundleIdentifier</key><string>io.github.thewander02.os-browser.launcher</string>
  <key>CFBundleExecutable</key><string>Browser</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
</dict></plist>
EOF
  cat > "$app/Contents/MacOS/Browser" <<EOF
#!/bin/sh
exec "$installs/os-browser" "\$@"
EOF
  chmod +x "$app/Contents/MacOS/Browser"
  echo "Installed $name"
  echo "Run: os-browser   (also ~/Applications/Browser.app)"
else
  apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  mkdir -p "$apps"
  cat > "$apps/os-browser.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Browser
Exec=$installs/os-browser %U
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
EOF
  echo "Installed $name"
  echo "Run: os-browser   (make sure ~/.local/bin is on your PATH)"
fi
