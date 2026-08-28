//! Times `expo_gifski::encode_gif` so release profile changes can be compared A/B.
//!
//! Edit `opt-level` (or add `panic`) in this crate's Cargo.toml and re-run: the
//! settings propagate to expo-gifski because this is the root package.

use std::time::Instant;

use expo_gifski::GifskiOptions;

const W: usize = 480;
const H: usize = 360;
const FRAMES: usize = 24;
const RUNS: usize = 3;

fn out_dir() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("out")
}

fn opts() -> GifskiOptions {
    GifskiOptions {
        width: W as u32,
        height: H as u32,
        quality: 90,
        repeat: -1,
        fast: false,
        fps: 20.0,
    }
}

fn write_frames(dir: &std::path::Path) -> Vec<String> {
    std::fs::create_dir_all(dir).unwrap();
    let mut paths = Vec::new();
    for i in 0..FRAMES {
        let mut buf = Vec::with_capacity(W * H * 4);
        let off = i * W / FRAMES;
        for y in 0..H {
            for x in 0..W {
                let moving = (x + off) % W < W / 4 && y > H / 5 && y < 4 * H / 5;
                let (r, g, b) = if moving {
                    (240u8, 40, 90)
                } else {
                    ((x * 255 / W) as u8, (y * 255 / H) as u8, 150)
                };
                buf.extend_from_slice(&[r, g, b, 255]);
            }
        }
        let p = dir.join(format!("f{i}.png"));
        lodepng::encode32_file(&p, &buf, W, H).unwrap();
        paths.push(p.to_string_lossy().into_owned());
    }
    paths
}

fn main() {
    let dir = out_dir();
    let paths = write_frames(&dir.join("frames"));

    // Warm up so filesystem cache is not part of the measurement.
    expo_gifski::encode_gif(
        paths.clone(),
        dir.join("warmup.gif").to_string_lossy().into_owned(),
        opts(),
        None,
    )
    .expect("warmup encode failed");

    let mut times = Vec::new();
    for run in 0..RUNS {
        let out = dir.join(format!("out{run}.gif"));
        let started = Instant::now();
        expo_gifski::encode_gif(
            paths.clone(),
            out.to_string_lossy().into_owned(),
            opts(),
            None,
        )
        .expect("encode failed");
        let ms = started.elapsed().as_millis();
        println!(
            "run {run}: {ms} ms, {} bytes",
            std::fs::metadata(&out).unwrap().len()
        );
        times.push(ms);
    }

    times.sort_unstable();
    println!(
        "\n{FRAMES} frames @ {W}x{H} -> median {} ms",
        times[times.len() / 2]
    );
}
