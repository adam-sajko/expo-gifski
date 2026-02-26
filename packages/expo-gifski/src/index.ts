import ExpoGifskiModule from "./ExpoGifskiModule";

export interface GifskiOptions {
  width?: number;
  height?: number;
  quality?: number; // 1-100
  repeat?: number; // -1 for infinite, 0 for no repeat, >0 for repeat count
  fast?: boolean;
  fps?: number; // frames per second (default: 10)
  startTime?: number; // seconds from video start (default: 0)
  duration?: number; // seconds to capture (default: full video)
}

export interface GifskiProgress {
  framesProcessed: number;
  totalFrames: number;
  progress: number; // 0-1
}

export async function encodeGifFromVideo(
  videoUri: string,
  outputPath: string,
  options: GifskiOptions = {},
): Promise<string> {
  return await ExpoGifskiModule.encodeGifFromVideo(
    videoUri,
    outputPath,
    options,
  );
}

export function getModuleVersion(): string {
  return ExpoGifskiModule.getModuleVersion();
}

export function getGifskiVersion(): string {
  return ExpoGifskiModule.getGifskiVersion();
}

export interface VideoThumbnailResult {
  uri: string;
  width: number;
  height: number;
}

export async function getVideoThumbnail(
  videoUri: string,
  timeMs: number = 0,
): Promise<VideoThumbnailResult> {
  return await ExpoGifskiModule.getVideoThumbnail(videoUri, timeMs);
}

export function addProgressListener(
  callback: (progress: GifskiProgress) => void,
): { remove: () => void } {
  return ExpoGifskiModule.addListener("onProgress", callback);
}

export default {
  encodeGifFromVideo,
  getVideoThumbnail,
  getModuleVersion,
  getGifskiVersion,
  addProgressListener,
};
