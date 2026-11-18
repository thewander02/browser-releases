# OS Browser releases

Downloadable builds of [Browser](https://github.com/thewander02/browser) — a CEF-based Chromium browser.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/thewander02/browser-releases/main/install.sh | sh
```

Picks the right build for your platform (Linux x64, macOS arm64), installs to
`~/.local/share/os-browser/installs/` (`~/Library/Application Support/os-browser/installs` on macOS),
and puts `os-browser` on `~/.local/bin`. macOS also gets `~/Applications/Browser.app`
(unsigned for now — quarantine is stripped automatically).

```sh
sh -s -- -c nightly    # install the nightly channel instead of main
```

## Channels

- **main** — stable, published from `v*` tags
- **nightly** — rebuilt on every push to `main` in thewander02/browser

The app updates itself: it checks the channel's manifest at launch and every 4 h, downloads in
the background, and applies on restart. Switch channels in Settings → About.

Releases ship stock CEF — no H.264/AAC/Widevine.
