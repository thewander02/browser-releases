#!/bin/sh
# Sprout iOS installer (no Apple Developer membership or Xcode required).
#
#   curl -fsSL https://raw.githubusercontent.com/thewander02/browser-releases/main/install-ios.sh | sh
#
# Options:
#   -c, --channel <main|nightly>   Release channel to install (default: main)
#   -f, --file <path.ipa>          Install a local .ipa instead of downloading
#       --udid <udid>              Target a specific iPhone UDID
#       --no-extensions            Strip Live Activity extension (uses 1 of 3 free app slots instead of 2)
#       --relogin                  Prompt for Apple ID login even if already signed in
#   -h, --help                     Show this help
#
# Signs the unsigned Sprout .ipa using your free Apple ID via plumesign
# (https://github.com/claration/impactor) and installs it to a USB-connected iPhone.
set -eu

REPO="https://github.com/thewander02/browser-releases"
PLUMESIGN_VERSION="v2.7.3"
PLUMESIGN_URL="https://github.com/claration/impactor/releases/download/$PLUMESIGN_VERSION/plumesign-macos-universal"
PLUMESIGN_SHA256="24bdc78f334f7db324d0d3ae35b1fc67d69f3f8f4a354d10b9967bc3fc261a08"

channel="main"
local_ipa=""
udid=""
no_extensions=0
relogin=0

usage() {
  cat <<'EOF'
Usage: install-ios.sh [options]

Options:
  -c, --channel <main|nightly>   Release channel to install (default: main)
  -f, --file <path.ipa>          Install a local .ipa instead of downloading
      --udid <udid>              Target a specific iPhone UDID
      --no-extensions            Strip Live Activity extension (saves 1 free app slot)
      --relogin                  Sign in to Apple ID again
  -h, --help                     Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--channel) channel="$2"; shift 2 ;;
    -f|--file) local_ipa="$2"; shift 2 ;;
    --udid) udid="$2"; shift 2 ;;
    --no-extensions) no_extensions=1; shift ;;
    --relogin) relogin=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install-ios.sh: unknown option '$1'" >&2; usage >&2; exit 1 ;;
  esac
done

case "$channel" in
  main|nightly) ;;
  *) echo "install-ios.sh: unknown channel '$channel' (main|nightly)" >&2; exit 1 ;;
esac

[ "$(uname -s)" = "Darwin" ] || { echo "install-ios.sh: macOS is required" >&2; exit 1; }

if ! [ -r /dev/tty ]; then
  echo "install-ios.sh: an interactive terminal is required (for Apple ID sign-in / device selection)" >&2
  exit 1
fi

tools_dir="$HOME/Library/Application Support/sprout/tools"
plumesign="$tools_dir/plumesign-$PLUMESIGN_VERSION"
tmp=$(mktemp -d)
cleanup() {
  stty echo </dev/tty 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

# --- 1. Fetch & verify plumesign (cached across runs) ---
if [ ! -x "$plumesign" ]; then
  mkdir -p "$tools_dir"
  echo "==> downloading plumesign $PLUMESIGN_VERSION (one-time)"
  curl -fSL --progress-bar "$PLUMESIGN_URL" -o "$tmp/plumesign"
  actual=$(shasum -a 256 "$tmp/plumesign" | awk '{print $1}')
  if [ "$actual" != "$PLUMESIGN_SHA256" ]; then
    echo "install-ios.sh: plumesign checksum mismatch (got $actual)" >&2
    exit 1
  fi
  chmod +x "$tmp/plumesign"
  xattr -d com.apple.quarantine "$tmp/plumesign" 2>/dev/null || true
  mv "$tmp/plumesign" "$plumesign"
fi

# --- 2. Obtain Sprout.ipa ---
if [ -n "$local_ipa" ]; then
  [ -f "$local_ipa" ] || { echo "install-ios.sh: file not found: $local_ipa" >&2; exit 1; }
  ipa="$local_ipa"
  echo "==> using local build: $ipa"
else
  tag="ios-$channel"
  echo "==> fetching $tag manifest"
  manifest=$(curl -fsSL "$REPO/releases/download/$tag/manifest.json") || {
    echo "install-ios.sh: no '$tag' release yet (or network error)" >&2
    exit 1
  }
  file=$(printf '%s' "$manifest" | grep -o '"ios"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
  [ -n "$file" ] || { echo "install-ios.sh: no iOS build listed in $tag manifest" >&2; exit 1; }
  ipa="$tmp/$file"
  echo "==> downloading $file"
  curl -fSL --progress-bar "$REPO/releases/download/$tag/$file" -o "$ipa"
fi

if [ "$no_extensions" -eq 1 ]; then
  echo "==> stripping app extensions (--no-extensions)"
  mkdir -p "$tmp/stripped"
  unzip -q "$ipa" -d "$tmp/stripped"
  rm -rf "$tmp/stripped"/Payload/*.app/PlugIns
  ipa="$tmp/sprout-no-ext.ipa"
  (cd "$tmp/stripped" && zip -qry "$ipa" Payload)
fi

# --- 3. Sign into free Apple ID (cached in ~/.config/PlumeImpactor) ---
logged_in=0
if [ "$relogin" -eq 0 ] && RUST_LOG=info "$plumesign" account list 2>&1 | grep -q "(selected)"; then
  logged_in=1
fi

if [ "$logged_in" -eq 0 ]; then
  echo ""
  echo "Sign in with a free Apple ID to sign Sprout for your iPhone."
  echo "(Credentials are sent only to Apple and cached locally so refreshes skip login.)"
  printf "Apple ID email: " >/dev/tty
  IFS= read -r apple_email </dev/tty
  printf "Apple ID password: " >/dev/tty
  stty -echo </dev/tty
  IFS= read -r apple_pass </dev/tty
  stty echo </dev/tty
  printf "\n" >/dev/tty
  RUST_LOG=info "$plumesign" account login -u "$apple_email" -p "$apple_pass" </dev/tty
  unset apple_pass
fi

# --- 4. Sign & install over USB ---
echo ""
echo "==> signing and installing Sprout to your iPhone"
echo "    Make sure your iPhone is plugged in via USB, unlocked, and trusts this Mac."

while true; do
  set +e
  if [ -n "$udid" ]; then
    RUST_LOG=info "$plumesign" sign -p "$ipa" --apple-id --register-and-install --udid "$udid" </dev/tty
  else
    RUST_LOG=info "$plumesign" sign -p "$ipa" --apple-id --register-and-install </dev/tty
  fi
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    break
  fi

  echo "" >&2
  echo "Install did not complete (exit $status)." >&2
  echo "  - Make sure your iPhone is plugged in via USB, unlocked, and trusts this Mac." >&2
  echo "  - If you hit Apple's 3-app free limit, re-run with --no-extensions." >&2
  printf "Press Enter to retry, or Ctrl-C to cancel: " >/dev/tty
  IFS= read -r _ </dev/tty
done

echo ""
echo "Sprout is installed on your iPhone!"
echo ""
echo "First time installing a sideloaded app on this iPhone?"
echo "  1. Settings -> General -> VPN & Device Management -> trust your Apple ID"
echo "  2. Settings -> Privacy & Security -> Developer Mode -> turn on (reboots once)"
echo ""
echo "Free Apple ID installs last 7 days. Plug in and re-run this command anytime to refresh."
