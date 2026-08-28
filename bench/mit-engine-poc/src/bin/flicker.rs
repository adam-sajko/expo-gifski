//! Measures the temporal flicker caused by quantizing each frame independently.
//!
//! The left half of every frame is byte-identical across the sequence; only the
//! right half animates. If per-frame quantization were temporally stable, the
//! decoded left half would come out identical every time. It does not: the
//! animated half shifts the color histogram, so k-means allocates a different
//! palette to the static half on each frame.
//!
//! Gate for any shared-palette work: the static region should stop moving.

use palette::Srgb;
use quantette::dither::FloydSteinberg;
use quantette::{IndexedImage, PaletteSize, Pipeline, QuantizeMethod};

const W: usize = 128;
const H: usize = 96;
const FRAMES: usize = 10;

fn make_frame(i: usize) -> Vec<Srgb<u8>> {
    let mut px = Vec::with_capacity(W * H);
    for y in 0..H {
        for x in 0..W {
            px.push(if x < W / 2 {
                // static: a smooth gradient, the kind of area that shimmers
                Srgb::new((x * 255 / (W / 2)) as u8, (y * 200 / H) as u8, 150)
            } else {
                // animated: strongly shifting hues move the color histogram
                let t = (i * 255 / FRAMES) as u8;
                Srgb::new(t, 255u8.wrapping_sub(t), ((x + y + i * 7) % 256) as u8)
            });
        }
    }
    px
}

fn quantize(px: &[Srgb<u8>]) -> Vec<Srgb<u8>> {
    let pipeline = Pipeline::new()
        .palette_size(PaletteSize::from_u8_clamped(255))
        .quantize_method(QuantizeMethod::kmeans())
        .ditherer(FloydSteinberg::with_error_diffusion(0.8).unwrap_or(FloydSteinberg::new()));

    let img = quantette::Image::new(W as u32, H as u32, px).expect("image");
    let indexed: IndexedImage<Srgb<u8>> = pipeline.input_image(img).output_srgb8_indexed_image();

    let pal = indexed.palette().to_vec();
    indexed.indices().iter().map(|&i| pal[i as usize]).collect()
}

fn main() {
    let mut prev: Option<Vec<Srgb<u8>>> = None;
    let mut changed_frames = 0;
    let mut worst = 0u32;

    println!("static left half, {FRAMES} frames, quantized independently\n");
    println!("frame  changed_px  max_delta  mean_delta");

    for i in 0..FRAMES {
        let decoded = quantize(&make_frame(i));

        if let Some(p) = &prev {
            let (mut changed, mut maxd, mut sum) = (0u32, 0u32, 0u64);
            for y in 0..H {
                for x in 0..W / 2 {
                    let idx = y * W + x;
                    let (a, b) = (p[idx], decoded[idx]);
                    let d = (a.red.abs_diff(b.red) as u32)
                        .max(a.green.abs_diff(b.green) as u32)
                        .max(a.blue.abs_diff(b.blue) as u32);
                    if d > 0 {
                        changed += 1;
                        sum += d as u64;
                        maxd = maxd.max(d);
                    }
                }
            }
            println!(
                "{i:>5}  {changed:>10}  {maxd:>9}  {:>10.2}",
                sum as f64 / (W / 2 * H) as f64
            );
            if changed > 0 {
                changed_frames += 1;
            }
            worst = worst.max(maxd);
        }
        prev = Some(decoded);
    }

    println!("\nstatic region = {} px per frame", W / 2 * H);
    println!(
        "frames where the static region changed: {changed_frames}/{}",
        FRAMES - 1
    );
    println!("worst per-channel delta in a pixel that never changed: {worst}");
}
