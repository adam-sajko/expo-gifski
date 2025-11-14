use std::path::Path;
use std::sync::Arc;

uniffi::setup_scaffolding!("expo_gifski");

#[derive(uniffi::Record)]
pub struct GifskiOptions {
    pub width: u32,
    pub height: u32,
    pub quality: u8,
    pub repeat: i32,
    pub fast: bool,
    pub fps: f32,
}

#[derive(uniffi::Record)]
pub struct GifskiProgress {
    pub frames_processed: u32,
    pub total_frames: u32,
    pub progress: f32,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum GifskiError {
    #[error("No valid input paths provided")]
    NoInputPaths,
    #[error("Invalid options: {reason}")]
    InvalidOptions { reason: String },
    #[error("Invalid output path: {path}")]
    InvalidOutputPath { path: String },
    #[error("Failed to create gifski encoder: {reason}")]
    EncoderCreationFailed { reason: String },
    #[error("Failed to create output file: {path}")]
    OutputFileCreationFailed { path: String },
    #[error("Failed to write GIF data: {reason}")]
    WriteFailed { reason: String },
    #[error("No valid frames were added ({failed} of {total} frames failed)")]
    NoFramesAdded { failed: u32, total: u32 },
}

#[uniffi::export(callback_interface)]
pub trait GifskiProgressCallback: Send + Sync {
    fn on_progress(&self, progress: GifskiProgress);
}

#[uniffi::export]
pub fn encode_gif(
    input_paths: Vec<String>,
    output_path: String,
    options: GifskiOptions,
    progress_callback: Option<Box<dyn GifskiProgressCallback>>,
) -> Result<(), GifskiError> {
    let paths: Vec<String> = input_paths
        .into_iter()
        .filter(|p| Path::new(p).exists())
        .collect();

    if paths.is_empty() {
        return Err(GifskiError::NoInputPaths);
    }

    if options.quality < 1 || options.quality > 100 {
        return Err(GifskiError::InvalidOptions {
            reason: format!(
                "quality must be between 1 and 100, got {}",
                options.quality
            ),
        });
    }

    let mut settings = gifski::Settings::default();
    if options.width > 0 {
        settings.width = Some(options.width);
    }
    if options.height > 0 {
        settings.height = Some(options.height);
    }
    settings.quality = options.quality;
    settings.repeat = if options.repeat < 0 {
        gifski::Repeat::Infinite
    } else {
        let clamped = options.repeat.clamp(0, u16::MAX as i32) as u16;
        gifski::Repeat::Finite(clamped)
    };
    settings.fast = options.fast;

    let (collector, writer) = gifski::new(settings).map_err(|e| {
        GifskiError::EncoderCreationFailed {
            reason: format!("{e:?}"),
        }
    })?;

    let fps = if options.fps > 0.0 { options.fps } else { 10.0 };
    let frame_duration = 1.0 / fps as f64;
    let total_frames = paths.len() as u32;

    let progress_cb: Option<Arc<dyn GifskiProgressCallback>> =
        progress_callback.map(|cb| Arc::from(cb));

    // Collector + writer MUST be on separate threads or the bounded channel deadlocks.
    // https://docs.rs/gifski/latest/gifski/struct.Collector.html
    let collector_thread = std::thread::spawn(move || {
        let mut failed_count: u32 = 0;

        for (frame_num, input_path) in paths.iter().enumerate() {
            let presentation_timestamp = frame_num as f64 * frame_duration;
            if let Err(e) = collector.add_frame_png_file(
                frame_num,
                Path::new(input_path).to_path_buf(),
                presentation_timestamp,
            ) {
                eprintln!(
                    "[expo-gifski] Frame {} failed to add: {:?} (path: {})",
                    frame_num, e, input_path
                );
                failed_count += 1;
                continue;
            }

            if let Some(ref cb) = progress_cb {
                cb.on_progress(GifskiProgress {
                    frames_processed: (frame_num + 1) as u32,
                    total_frames,
                    progress: (frame_num + 1) as f32 / total_frames as f32,
                });
            }
        }

        drop(collector); // signals "no more frames"

        failed_count
    });

    let mut file = std::fs::File::create(&output_path).map_err(|_| {
        GifskiError::OutputFileCreationFailed {
            path: output_path.clone(),
        }
    })?;

    let mut progress = gifski::progress::NoProgress {};
    let write_result = writer.write(&mut file, &mut progress);

    let failed_count = collector_thread.join().map_err(|_| GifskiError::WriteFailed {
        reason: "collector thread panicked".to_string(),
    })?;

    if failed_count == total_frames {
        return Err(GifskiError::NoFramesAdded {
            failed: failed_count,
            total: total_frames,
        });
    }

    write_result.map_err(|e| GifskiError::WriteFailed {
        reason: format!("{e:?}"),
    })?;

    Ok(())
}

#[uniffi::export]
pub fn get_module_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[uniffi::export]
pub fn get_gifski_version() -> String {
    env!("GIFSKI_CRATE_VERSION").to_string()
}
