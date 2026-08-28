# bench

Throwaway-but-kept measurement crates. Neither is part of the published package
(`publish = false`), and neither is a yarn workspace — run them with cargo.

## `mit-engine-poc`

Validates the MIT engine pivot described in `.cursor/plans/mit-engine-pivot.md`
before any of it touches `packages/expo-gifski/rust`.

```bash
cd bench/mit-engine-poc
cargo run --release              # full chain -> out/poc.gif
cargo run --release --bin flicker  # temporal flicker measurement
```

`main.rs` compiles the whole Phase 1 pipeline (lodepng -> resize Lanczos3 ->
quantette k-means + Floyd-Steinberg -> gif 0.14). If it builds, the API the plan
documents matches the crates.

`flicker.rs` quantifies the main quality regression the pivot would introduce.
It renders frames whose left half never changes, quantizes each frame
independently, and reports how much that static half moves anyway:

```
frames where the static region changed: 9/9
worst per-channel delta in a pixel that never changed: 59
```

Use it as the regression gate when adding a shared or reused palette.

## `encode-bench`

Times the real `encode_gif` against the current encoder. Cargo only honours
profile settings from the root package, so changing `[profile.release]` in this
crate's `Cargo.toml` propagates to `expo-gifski` and lets you A/B the shipped
profile without editing the library.

```bash
cd bench/encode-bench
cargo run --release
```

Reference point on 24 frames at 480x360: `opt-level = "z"` runs at 285 ms and
`opt-level = 3` at 117 ms, for byte-identical output.
