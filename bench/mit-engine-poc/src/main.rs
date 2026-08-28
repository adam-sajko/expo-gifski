//! Proof of concept for the MIT engine pivot (see .cursor/plans/mit-engine-pivot.md).
//!
//! Exercises the exact API surface Phase 1 depends on:
//! lodepng decode -> resize (Lanczos3) -> quantette quantize+dither -> gif encode.
//! If this compiles, the API the plan documents is accurate.

use std::borrow::Cow;

use palette::Srgb;
use quantette::dither::FloydSteinberg;
use quantette::{IndexedImage, PaletteSize, Pipeline, QuantizeMethod};

const SRC: usize = 96;
const DST: usize = 64;
const FRAMES: usize = 8;

fn out_dir() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("out")
}

/// Gradient background with a moving block, so quantization and dithering see
/// both smooth ramps and hard edges.
fn make_frame(i: usize) -> Vec<rgb::RGBA8> {
    let mut px = Vec::with_capacity(SRC * SRC);
    let offset = i * SRC / FRAMES;
    for y in 0..SRC {
        for x in 0..SRC {
            let in_block = (x + offset) % SRC < SRC / 3 && y > SRC / 4 && y < 3 * SRC / 4;
            px.push(if in_block {
                rgb::RGBA8::new(240, 40, 90, 255)
            } else {
                rgb::RGBA8::new((x * 255 / SRC) as u8, (y * 255 / SRC) as u8, 160, 255)
            });
        }
    }
    px
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let dir = out_dir().join("frames");
    std::fs::create_dir_all(&dir)?;

    // 1. Write PNG frames, standing in for what the native modules produce.
    let mut paths = Vec::new();
    for i in 0..FRAMES {
        let px = make_frame(i);
        let flat: Vec<u8> = px.iter().flat_map(|p| [p.r, p.g, p.b, p.a]).collect();
        let path = dir.join(format!("frame{i}.png"));
        lodepng::encode32_file(&path, &flat, SRC, SRC)?;
        paths.push(path);
    }
    println!("wrote {} PNG frames", paths.len());

    // 2. Encode them into a GIF.
    let gif_path = out_dir().join("poc.gif");
    let mut file = std::fs::File::create(&gif_path)?;
    let mut encoder = gif::Encoder::new(&mut file, DST as u16, DST as u16, &[])?;
    encoder.set_repeat(gif::Repeat::Infinite)?;

    let mut resizer = resize::new(
        SRC,
        SRC,
        DST,
        DST,
        resize::Pixel::RGBA8,
        resize::Type::Lanczos3,
    )?;

    for (i, path) in paths.iter().enumerate() {
        let image = lodepng::decode32_file(path)?;
        let src: Vec<rgb::RGBA8> = image
            .buffer
            .iter()
            .map(|p| rgb::RGBA8::new(p.r, p.g, p.b, p.a))
            .collect();

        let mut dst = vec![rgb::RGBA8::new(0, 0, 0, 0); DST * DST];
        resizer.resize(&src, &mut dst)?;

        // Phase 2 frame trimming will need a reserved transparent index instead.
        let srgb_pixels: Vec<Srgb<u8>> = dst.iter().map(|p| Srgb::new(p.r, p.g, p.b)).collect();

        let pipeline = Pipeline::new()
            .palette_size(PaletteSize::from_u8_clamped(255))
            .quantize_method(QuantizeMethod::kmeans())
            .ditherer(FloydSteinberg::with_error_diffusion(0.8).unwrap_or(FloydSteinberg::new()));

        // A &[Srgb<u8>] container yields an ImageRef, which input_image takes directly.
        let quant_image = quantette::Image::new(DST as u32, DST as u32, srgb_pixels.as_slice())
            .map_err(|_| "failed to build quantette image")?;

        let indexed: IndexedImage<Srgb<u8>> =
            pipeline.input_image(quant_image).output_srgb8_indexed_image();

        let palette_flat: Vec<u8> = indexed
            .palette()
            .iter()
            .flat_map(|c| [c.red, c.green, c.blue])
            .collect();
        let indices = indexed.indices().to_vec();

        if i == 0 {
            println!(
                "frame 0: {} palette colors, {} indices (expected {})",
                palette_flat.len() / 3,
                indices.len(),
                DST * DST
            );
        }

        let mut frame = gif::Frame::default();
        frame.width = DST as u16;
        frame.height = DST as u16;
        frame.delay = 10;
        frame.palette = Some(palette_flat);
        frame.buffer = Cow::Owned(indices);
        encoder.write_frame(&frame)?;
    }

    drop(encoder);
    println!(
        "wrote {} ({} bytes)",
        gif_path.display(),
        std::fs::metadata(&gif_path)?.len()
    );
    Ok(())
}
