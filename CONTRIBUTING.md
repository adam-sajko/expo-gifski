# Contributing

## Structure

```
packages/expo-gifski/   # Expo module (Rust FFI + Swift + Kotlin + TS)
apps/gifski-example/    # Example app
scripts/                # Build helpers
```

## Prerequisites

- [Rust](https://rustup.rs/)
- Xcode CLI tools (iOS) / Android NDK (Android)

## Setup

```bash
yarn install
./packages/expo-gifski/ios/build.sh
./packages/expo-gifski/android/build.sh
yarn ios          # or yarn android
```

## Dev workflow

| Changed           | Command                      |
| ----------------- | ---------------------------- |
| JS/TS only        | Reload Metro                 |
| Swift/Kotlin      | `yarn ios` or `yarn android` |
| Rust              | `yarn build`                 |
| Everything broken | `yarn build:clean`           |

## Scripts

| Command                  | What it does                         |
| ------------------------ | ------------------------------------ |
| `yarn build`             | Rust + app build (both platforms)    |
| `yarn build ios`         | Rust + iOS only                      |
| `yarn build android`     | Rust + Android only                  |
| `yarn build --clean ios` | Clean everything, then rebuild iOS   |
| `yarn open-gif`          | Open latest GIF in Preview (iOS sim) |
| `yarn open-gif --folder` | Open cache folder in Finder          |
| `yarn open-gif --list`   | List generated GIFs                  |

## Architecture

```
TS API  ->  Native module (Swift / Kotlin)  ->  UniFFI bindings  ->  Rust (gifski crate)
```

The native layer extracts video frames (AVAssetImageGenerator / MediaMetadataRetriever) or loads images, resizes to target dimensions, writes temp PNGs. Those paths go to Rust via [UniFFI](https://mozilla.github.io/uniffi-rs/)-generated bindings. gifski encodes the GIF with concurrent frame reading + writing. Progress propagates back through UniFFI callbacks to JS events.
