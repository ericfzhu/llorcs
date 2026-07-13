# llorcs

A small native macOS menu-bar utility that controls scroll direction independently for a trackpad and mouse. Conventional wheel mice can also have per-device rules.

## Run it

Requires macOS 13 or later and Xcode Command Line Tools.

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "build/llorcs.app"
```

On first launch, choose **Open Permission Prompt**, allow llorcs under **System Settings → Privacy & Security → Accessibility**, then return to the menu-bar app. For individual-mouse rules, also allow **Input Monitoring** when prompted; the general mouse and trackpad settings work without it.

## How device detection works

- Trackpad vs mouse uses the continuity and phase metadata on macOS scroll events.
- Per-device mouse rules correlate a scroll event with the latest raw HID wheel report.
- Standard physical mouse wheels work best.
- Magic Mouse and other gesture surfaces can look like a trackpad to macOS. Public event-tap APIs do not expose a definitive source-device identifier, so their per-device behavior cannot be guaranteed.

## Develop

```sh
swift test
swift run llorcs
```

Running via `swift run` associates Accessibility permission with your terminal. Build and run the `.app` for normal use.
