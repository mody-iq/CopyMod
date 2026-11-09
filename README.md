# CopyMod

Clipboard history for the stock iOS keyboard. Records every text you copy and
shows the history in a panel inside the keyboard, with search, pin, delete and
export.

## Requirements

- iOS 15.0+ on arm64 / arm64e
- A **RootHide-based jailbreak** (the package is built with the `roothide`
  Theos scheme and links `libroothide`). It will not load on rootful or plain
  rootless (e.g. Dopamine) setups.
- mobilesubstrate and preferenceloader

## Usage

- Open the panel with the clipboard button at the top-right of the keyboard,
  or with a two-finger swipe up (configurable in Settings > CopyMod).
- Tap an entry to insert it into the focused text field.
- Long-press an entry to copy, pin or delete it.
- Password fields and very long texts are ignored by default.

## Build

Requires [Theos](https://github.com/roothide/theos) (roothide fork) with an
iOS SDK installed:

```sh
make package FINALPACKAGE=1
```

GitHub Actions builds the `.deb` automatically on every push to `main`.