import * as Clipboard from "expo-clipboard";
import { File, Paths } from "expo-file-system";
import {
  addProgressListener,
  encodeGifFromVideo,
  getGifskiVersion,
  getModuleVersion,
  type GifskiProgress,
} from "expo-gifski";
import * as ImagePicker from "expo-image-picker";
import * as Sharing from "expo-sharing";
import { StatusBar } from "expo-status-bar";
import * as VideoThumbnails from "expo-video-thumbnails";
import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Animated,
  Image,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from "react-native-safe-area-context";

const MAX_DIMENSION = 800;
const ACCENT = "#5e60ce";
const ACCENT_LIGHT = "#8b8fcf";

function computeScaledSize(
  origWidth: number,
  origHeight: number,
  maxDim: number = MAX_DIMENSION,
): { width: number; height: number } {
  if (origWidth <= maxDim && origHeight <= maxDim) {
    return { width: origWidth, height: origHeight };
  }
  const scale = Math.min(maxDim / origWidth, maxDim / origHeight);
  return {
    width: Math.max(1, Math.round(origWidth * scale)),
    height: Math.max(1, Math.round(origHeight * scale)),
  };
}

function SettingsFields({
  fps,
  onFpsChange,
  width,
  onWidthChange,
  height,
  onHeightChange,
  quality,
  onQualityChange,
  fast,
  onFastToggle,
  showAdvanced,
  onToggleAdvanced,
  extra,
}: {
  fps: string;
  onFpsChange: (t: string) => void;
  width: string;
  onWidthChange: (t: string) => void;
  height: string;
  onHeightChange: (t: string) => void;
  quality: string;
  onQualityChange: (t: string) => void;
  fast: boolean;
  onFastToggle: () => void;
  showAdvanced: boolean;
  onToggleAdvanced: () => void;
  extra?: React.ReactNode;
}) {
  return (
    <View style={s.settingsCard}>
      {extra}

      <View style={s.settingsRow}>
        <View style={s.settingsField}>
          <Text style={s.fieldLabel}>FPS</Text>
          <TextInput
            style={s.fieldInput}
            value={fps}
            onChangeText={onFpsChange}
            keyboardType="decimal-pad"
            placeholder="10"
            placeholderTextColor="#ced4da"
          />
        </View>
        <View style={s.settingsField}>
          <Text style={s.fieldLabel}>Width</Text>
          <TextInput
            style={s.fieldInput}
            value={width}
            onChangeText={onWidthChange}
            keyboardType="number-pad"
            placeholder="480"
            placeholderTextColor="#ced4da"
          />
        </View>
        <View style={s.settingsField}>
          <Text style={s.fieldLabel}>Height</Text>
          <TextInput
            style={s.fieldInput}
            value={height}
            onChangeText={onHeightChange}
            keyboardType="number-pad"
            placeholder="360"
            placeholderTextColor="#ced4da"
          />
        </View>
      </View>

      <Pressable style={s.advancedHeader} onPress={onToggleAdvanced}>
        <Text style={s.advancedHeaderText}>Advanced</Text>
        <Text style={s.advancedChevron}>
          {showAdvanced ? "\u25B2" : "\u25BC"}
        </Text>
      </Pressable>

      {showAdvanced && (
        <View style={s.advancedContent}>
          <View style={s.settingsField}>
            <Text style={s.fieldLabel}>Quality (1-100)</Text>
            <TextInput
              style={s.fieldInput}
              value={quality}
              onChangeText={onQualityChange}
              keyboardType="number-pad"
              placeholder="90"
              placeholderTextColor="#ced4da"
            />
          </View>
          <Pressable style={s.toggleRow} onPress={onFastToggle}>
            <View style={s.toggleLabelGroup}>
              <Text style={s.fieldLabel}>Fast mode</Text>
              <Text style={s.fieldHint}>Faster encoding, lower quality</Text>
            </View>
            <View style={[s.toggle, fast && s.toggleActive]}>
              <View style={[s.toggleThumb, fast && s.toggleThumbActive]} />
            </View>
          </Pressable>
        </View>
      )}
    </View>
  );
}

function EncodingModal({
  visible,
  progress,
}: {
  visible: boolean;
  progress: GifskiProgress | null;
}) {
  const animValue = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (progress) {
      Animated.timing(animValue, {
        toValue: progress.progress,
        duration: 200,
        useNativeDriver: false,
      }).start();
    } else {
      animValue.setValue(0);
    }
  }, [progress, animValue]);

  const pct = progress ? Math.round(progress.progress * 100) : 0;

  return (
    <Modal visible={visible} transparent animationType="fade">
      <View style={s.modalBackdrop}>
        <View style={s.encodingCard}>
          <ActivityIndicator color={ACCENT} size="large" />
          <Text style={s.encodingTitle}>
            {progress ? `Encoding... ${pct}%` : "Preparing..."}
          </Text>
          {progress && (
            <>
              <View style={s.encodingBarBg}>
                <Animated.View
                  style={[
                    s.encodingBarFill,
                    {
                      width: animValue.interpolate({
                        inputRange: [0, 1],
                        outputRange: ["0%", "100%"],
                      }),
                    },
                  ]}
                />
              </View>
              <Text style={s.encodingDetail}>
                Frame {progress.framesProcessed} / {progress.totalFrames}
              </Text>
            </>
          )}
        </View>
      </View>
    </Modal>
  );
}

function formatFileSize(bytes: number): string {
  if (bytes >= 1048576) return (bytes / 1048576).toFixed(2) + " MB";
  if (bytes >= 1024) return (bytes / 1024).toFixed(0) + " KB";
  return bytes + " B";
}

function ResultModal({
  visible,
  outputPath,
  onDismiss,
  onNewGif,
}: {
  visible: boolean;
  outputPath: string | null;
  onDismiss: () => void;
  onNewGif: () => void;
}) {
  const insets = useSafeAreaInsets();
  const [fileSize, setFileSize] = useState<number | null>(null);
  const [dimensions, setDimensions] = useState<{ w: number; h: number } | null>(
    null,
  );
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!outputPath || !visible) {
      setFileSize(null);
      setDimensions(null);
      setCopied(false);
      return;
    }
    const file = new File(outputPath);
    if (file.exists) {
      setFileSize(file.size ?? null);
    }
    Image.getSize(
      outputPath,
      (w, h) => setDimensions({ w, h }),
      () => setDimensions(null),
    );
  }, [outputPath, visible]);

  const handleCopy = async () => {
    if (!outputPath) return;
    await Clipboard.setStringAsync(outputPath);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleShare = async () => {
    if (!outputPath) return;
    try {
      await Sharing.shareAsync(outputPath, { mimeType: "image/gif" });
    } catch {
      Alert.alert("Sharing failed", "Could not share the GIF.");
    }
  };

  return (
    <Modal visible={visible} animationType="slide">
      <View style={s.resultModalContainer}>
        <View style={[s.resultModalHeader, { paddingTop: insets.top + 8 }]}>
          <Pressable
            style={({ pressed }) => [
              s.resultCloseButton,
              pressed && s.resultCloseButtonPressed,
            ]}
            onPress={onDismiss}
            hitSlop={8}
          >
            <Text style={s.resultCloseText}>Close</Text>
          </Pressable>
          <Text style={s.resultModalTitle}>Your GIF is ready</Text>
          <View style={{ width: 50 }} />
        </View>
        {outputPath && (
          <ScrollView
            style={s.resultScrollView}
            contentContainerStyle={[
              s.resultScrollContent,
              { paddingBottom: insets.bottom + 20 },
            ]}
            showsVerticalScrollIndicator={false}
          >
            <View style={s.resultPreviewCard}>
              <Image
                source={{ uri: outputPath }}
                style={s.resultGifPreview}
                resizeMode="contain"
              />
            </View>

            <View style={s.resultDetails}>
              {fileSize != null && (
                <View style={s.resultDetailChip}>
                  <Text style={s.resultDetailLabel}>Size</Text>
                  <Text style={s.resultDetailValue}>
                    {formatFileSize(fileSize)}
                  </Text>
                </View>
              )}
              {dimensions && (
                <View style={s.resultDetailChip}>
                  <Text style={s.resultDetailLabel}>Dimensions</Text>
                  <Text style={s.resultDetailValue}>
                    {dimensions.w} × {dimensions.h}
                  </Text>
                </View>
              )}
            </View>

            <View style={s.resultPathCard}>
              <Text style={s.resultPathLabel}>Output path</Text>
              <View style={s.resultPathRow}>
                <Text style={s.resultPath} numberOfLines={2}>
                  {outputPath}
                </Text>
                <Pressable
                  style={({ pressed }) => [
                    s.copyButton,
                    pressed && s.copyButtonPressed,
                    copied && s.copyButtonCopied,
                  ]}
                  onPress={handleCopy}
                  hitSlop={8}
                >
                  <Text
                    style={[s.copyButtonText, copied && s.copyButtonTextCopied]}
                  >
                    {copied ? "Copied!" : "Copy"}
                  </Text>
                </Pressable>
              </View>
            </View>
          </ScrollView>
        )}

        <View style={[s.resultBottomBar, { paddingBottom: insets.bottom }]}>
          <Pressable
            style={({ pressed }) => [
              s.resultButton,
              s.resultShareButton,
              pressed && s.resultShareButtonPressed,
            ]}
            onPress={handleShare}
          >
            <Text style={s.resultShareButtonText}>Share GIF</Text>
          </Pressable>
          <Pressable
            style={({ pressed }) => [
              s.resultButton,
              s.resultNewGifButton,
              pressed && s.resultNewGifButtonPressed,
            ]}
            onPress={onNewGif}
          >
            <Text style={s.resultNewGifButtonText}>New GIF</Text>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}

function AppContent() {
  const insets = useSafeAreaInsets();

  const [progress, setProgress] = useState<GifskiProgress | null>(null);
  const [isEncoding, setIsEncoding] = useState(false);
  const [outputPath, setOutputPath] = useState<string | null>(null);
  const [showResult, setShowResult] = useState(false);
  const moduleVersion = (() => {
    try {
      return getModuleVersion();
    } catch {
      return null;
    }
  })();
  const rustGifskiVersion = (() => {
    try {
      return getGifskiVersion();
    } catch {
      return null;
    }
  })();

  const [fps, setFps] = useState("10");
  const [width, setWidth] = useState("480");
  const [height, setHeight] = useState("360");
  const [quality, setQuality] = useState("90");
  const [fast, setFast] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);

  const [videoUri, setVideoUri] = useState<string | null>(null);
  const [videoThumbnail, setVideoThumbnail] = useState<string | null>(null);
  const [videoDuration, setVideoDuration] = useState<number | null>(null);
  const [startTime, setStartTime] = useState("0");
  const [clipDuration, setClipDuration] = useState("3");

  const handleFpsChange = useCallback((text: string) => {
    setFps(text);
  }, []);

  const handleWidthChange = useCallback((text: string) => {
    const num = parseInt(text, 10);
    setWidth(isNaN(num) || num < 1 ? text : Math.max(1, num).toString());
  }, []);

  const handleHeightChange = useCallback((text: string) => {
    const num = parseInt(text, 10);
    setHeight(isNaN(num) || num < 1 ? text : Math.max(1, num).toString());
  }, []);

  const handleClear = () => {
    setVideoUri(null);
    setVideoThumbnail(null);
    setVideoDuration(null);
    setOutputPath(null);
    setProgress(null);
    setShowResult(false);
  };

  const handlePickVideo = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ["videos"],
      quality: 1,
    });
    if (!result.canceled && result.assets.length > 0) {
      const asset = result.assets[0];
      const durSec = asset.duration ? (asset.duration / 1000).toFixed(1) : "?";
      console.log(
        `[gifski] Picked video: ${asset.width}x${asset.height}, ${durSec}s, ${asset.mimeType ?? "unknown"}`,
      );
      setVideoUri(asset.uri);
      setOutputPath(null);
      setShowResult(false);
      if (asset.duration && asset.duration > 0) {
        const durationSec = asset.duration / 1000;
        setVideoDuration(durationSec);
        setClipDuration(durationSec.toFixed(1));
      }
      if (asset.width > 0 && asset.height > 0) {
        const scaled = computeScaledSize(asset.width, asset.height);
        setWidth(scaled.width.toString());
        setHeight(scaled.height.toString());
      }
      try {
        const thumb = await VideoThumbnails.getThumbnailAsync(asset.uri, {
          time: 0,
        });
        setVideoThumbnail(thumb.uri);
      } catch {
        setVideoThumbnail(null);
      }
    }
  };

  const handleEncode = async () => {
    if (!videoUri) {
      Alert.alert("No video", "Please select a video first.");
      return;
    }
    const w = Math.max(1, parseInt(width, 10) || 480);
    const h = Math.max(1, parseInt(height, 10) || 360);
    try {
      setIsEncoding(true);
      setProgress(null);
      setOutputPath(null);
      const sub = addProgressListener(setProgress);
      const output = `${Paths.cache.uri}output_${Date.now()}.gif`;
      const opts = {
        quality: Math.min(100, Math.max(1, parseInt(quality, 10) || 90)),
        repeat: -1,
        width: w,
        height: h,
        fast,
        fps: Math.max(0.1, parseFloat(fps) || 10),
        startTime: Math.max(0, parseFloat(startTime) || 0),
        duration: Math.max(0.1, parseFloat(clipDuration) || 3),
      };
      console.log("[gifski] Encoding from video:", opts);
      const result = await encodeGifFromVideo(videoUri, output, opts);
      sub.remove();
      console.log("[gifski] Encoding complete:", result);
      setOutputPath(result);
      setShowResult(true);
    } catch (error) {
      console.error("[gifski] Error encoding GIF from video:", error);
      Alert.alert(
        "Encoding Error",
        error instanceof Error ? error.message : String(error),
      );
    } finally {
      setIsEncoding(false);
    }
  };

  const estimatedFrames = Math.ceil(
    (parseFloat(clipDuration) || 3) * (parseFloat(fps) || 10),
  );

  return (
    <View style={s.root}>
      <StatusBar style="dark" />

      <View style={[s.header, { paddingTop: insets.top + 8 }]}>
        <Text style={s.title}>Gifski</Text>
        {(moduleVersion || rustGifskiVersion) && (
          <Text style={s.version}>
            {moduleVersion ? `module v${moduleVersion}` : ""}
            {moduleVersion && rustGifskiVersion ? "  ·  " : ""}
            {rustGifskiVersion ? `gifski v${rustGifskiVersion}` : ""}
          </Text>
        )}
      </View>

      <ScrollView
        style={s.scroll}
        contentContainerStyle={s.scrollContent}
        keyboardShouldPersistTaps="handled"
      >
        {!videoUri ? (
          <Pressable
            style={s.emptyPicker}
            onPress={handlePickVideo}
            disabled={isEncoding}
          >
            <Text style={s.emptyPickerIcon}>🎬</Text>
            <Text style={s.emptyPickerTitle}>Select a video</Text>
            <Text style={s.emptyPickerHint}>
              Tap to choose from your library
            </Text>
          </Pressable>
        ) : (
          <Pressable
            onPress={handlePickVideo}
            disabled={isEncoding}
            style={s.videoCard}
          >
            {videoThumbnail ? (
              <Image
                source={{ uri: videoThumbnail }}
                style={s.videoPreview}
                resizeMode="cover"
              />
            ) : (
              <View
                style={[
                  s.videoPreview,
                  {
                    backgroundColor: "#1a1a2e",
                    justifyContent: "center",
                    alignItems: "center",
                  },
                ]}
              >
                <Text style={{ fontSize: 40 }}>🎬</Text>
              </View>
            )}
            <View style={s.videoOverlay}>
              <Text style={s.videoOverlayText}>
                {videoDuration ? `${videoDuration.toFixed(1)}s` : "Video"}
              </Text>
              <Text style={s.videoChangeText}>Tap to change</Text>
            </View>
          </Pressable>
        )}

        {videoUri && (
          <View style={s.section}>
            <Text style={s.sectionTitle}>Settings</Text>
            <SettingsFields
              fps={fps}
              onFpsChange={handleFpsChange}
              width={width}
              onWidthChange={handleWidthChange}
              height={height}
              onHeightChange={handleHeightChange}
              quality={quality}
              onQualityChange={setQuality}
              fast={fast}
              onFastToggle={() => setFast((f) => !f)}
              showAdvanced={showAdvanced}
              onToggleAdvanced={() => setShowAdvanced((v) => !v)}
              extra={
                <>
                  <View style={s.settingsRow}>
                    <View style={s.settingsField}>
                      <Text style={s.fieldLabel}>Start (s)</Text>
                      <TextInput
                        style={s.fieldInput}
                        value={startTime}
                        onChangeText={setStartTime}
                        onEndEditing={() => {
                          if (videoDuration == null) return;
                          const clamped = Math.min(
                            Math.max(0, parseFloat(startTime) || 0),
                            videoDuration,
                          );
                          setStartTime(clamped.toFixed(1));
                          const remaining = videoDuration - clamped;
                          if ((parseFloat(clipDuration) || 0) > remaining) {
                            setClipDuration(Math.max(0.1, remaining).toFixed(1));
                          }
                        }}
                        keyboardType="decimal-pad"
                        placeholder={
                          videoDuration != null
                            ? `0 – ${videoDuration.toFixed(1)}`
                            : "0"
                        }
                        placeholderTextColor="#ced4da"
                      />
                    </View>
                    <View style={s.settingsField}>
                      <Text style={s.fieldLabel}>Duration (s)</Text>
                      <TextInput
                        style={s.fieldInput}
                        value={clipDuration}
                        onChangeText={setClipDuration}
                        onEndEditing={() => {
                          if (videoDuration == null) return;
                          const maxDur =
                            videoDuration - (parseFloat(startTime) || 0);
                          const clamped = Math.min(
                            Math.max(0.1, parseFloat(clipDuration) || 0.1),
                            maxDur,
                          );
                          setClipDuration(clamped.toFixed(1));
                        }}
                        keyboardType="decimal-pad"
                        placeholder={
                          videoDuration != null
                            ? `max ${(videoDuration - (parseFloat(startTime) || 0)).toFixed(1)}`
                            : "3"
                        }
                        placeholderTextColor="#ced4da"
                      />
                    </View>
                  </View>
                  <Text style={s.fieldHint}>
                    ~{estimatedFrames} frames will be extracted
                  </Text>
                </>
              }
            />
          </View>
        )}

        <View style={{ height: 100 }} />
      </ScrollView>

      {videoUri && (
        <View style={[s.bottomBar, { paddingBottom: insets.bottom + 12 }]}>
          <Pressable
            style={[s.encodeButton, isEncoding && s.encodeButtonDisabled]}
            onPress={handleEncode}
            disabled={isEncoding}
          >
            <Text style={s.encodeButtonText}>Encode GIF</Text>
          </Pressable>
        </View>
      )}

      {videoUri && !isEncoding && (
        <Pressable
          style={[s.clearFab, { top: insets.top + 12 }]}
          onPress={handleClear}
          hitSlop={8}
        >
          <Text style={s.clearFabText}>Clear</Text>
        </Pressable>
      )}

      <EncodingModal visible={isEncoding} progress={progress} />
      <ResultModal
        visible={showResult && !isEncoding}
        outputPath={outputPath}
        onDismiss={() => setShowResult(false)}
        onNewGif={handleClear}
      />
    </View>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <AppContent />
    </SafeAreaProvider>
  );
}

const s = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: "#f8f9fa",
  },

  header: {
    paddingHorizontal: 20,
    paddingBottom: 12,
    backgroundColor: "#fff",
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: "#e9ecef",
  },
  title: {
    fontSize: 28,
    fontWeight: "800",
    color: "#1a1a2e",
    textAlign: "center",
  },
  version: {
    fontSize: 11,
    color: "#adb5bd",
    textAlign: "center",
    marginTop: 2,
    fontFamily: Platform.OS === "ios" ? "Menlo" : "monospace",
  },

  scroll: {
    flex: 1,
  },
  scrollContent: {
    padding: 20,
  },

  emptyPicker: {
    backgroundColor: "#fff",
    borderRadius: 16,
    borderWidth: 2,
    borderColor: "#dee2e6",
    borderStyle: "dashed",
    paddingVertical: 48,
    alignItems: "center",
    justifyContent: "center",
  },
  emptyPickerIcon: {
    fontSize: 40,
    marginBottom: 12,
  },
  emptyPickerTitle: {
    fontSize: 17,
    fontWeight: "700",
    color: "#495057",
  },
  emptyPickerHint: {
    fontSize: 13,
    color: "#adb5bd",
    marginTop: 4,
  },

  videoCard: {
    borderRadius: 16,
    overflow: "hidden",
    backgroundColor: "#1a1a2e",
  },
  videoPreview: {
    width: "100%",
    height: 200,
  },
  videoOverlay: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    paddingVertical: 8,
    paddingHorizontal: 14,
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    backgroundColor: "rgba(0,0,0,0.45)",
  },
  videoOverlayText: {
    color: "#fff",
    fontSize: 13,
    fontWeight: "700",
  },
  videoChangeText: {
    color: "rgba(255,255,255,0.7)",
    fontSize: 12,
  },

  section: {
    marginTop: 24,
  },
  sectionTitle: {
    fontSize: 13,
    fontWeight: "700",
    color: "#495057",
    textTransform: "uppercase",
    letterSpacing: 0.5,
    marginBottom: 10,
  },

  settingsCard: {
    backgroundColor: "#fff",
    borderRadius: 14,
    padding: 14,
    gap: 12,
  },
  settingsRow: {
    flexDirection: "row",
    gap: 10,
  },
  settingsField: {
    flex: 1,
  },
  fieldLabel: {
    fontSize: 11,
    fontWeight: "600",
    color: "#6c757d",
    marginBottom: 4,
    textTransform: "uppercase",
    letterSpacing: 0.3,
  },
  fieldInput: {
    backgroundColor: "#f8f9fa",
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#dee2e6",
    paddingHorizontal: 10,
    paddingVertical: 8,
    fontSize: 15,
    color: "#1a1a2e",
  },
  fieldHint: {
    fontSize: 11,
    color: "#adb5bd",
    marginTop: 3,
  },
  advancedHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingVertical: 4,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: "#e9ecef",
    paddingTop: 8,
  },
  advancedHeaderText: {
    fontSize: 12,
    fontWeight: "600",
    color: "#6c757d",
  },
  advancedChevron: {
    fontSize: 10,
    color: "#adb5bd",
  },
  advancedContent: {
    gap: 12,
  },
  toggleRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
  },
  toggleLabelGroup: {
    flex: 1,
  },
  toggle: {
    width: 44,
    height: 26,
    borderRadius: 13,
    backgroundColor: "#dee2e6",
    justifyContent: "center",
    paddingHorizontal: 2,
  },
  toggleActive: {
    backgroundColor: ACCENT,
  },
  toggleThumb: {
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: "#fff",
  },
  toggleThumbActive: {
    alignSelf: "flex-end",
  },

  bottomBar: {
    position: "absolute",
    bottom: 0,
    left: 0,
    right: 0,
    paddingHorizontal: 20,
    paddingTop: 12,
    backgroundColor: "rgba(248,249,250,0.95)",
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: "#dee2e6",
  },
  encodeButton: {
    backgroundColor: ACCENT,
    borderRadius: 14,
    paddingVertical: 16,
    alignItems: "center",
  },
  encodeButtonDisabled: {
    backgroundColor: ACCENT_LIGHT,
  },
  encodeButtonText: {
    fontSize: 17,
    fontWeight: "700",
    color: "#fff",
  },

  clearFab: {
    position: "absolute",
    right: 20,
    backgroundColor: "rgba(0,0,0,0.06)",
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
  },
  clearFabText: {
    fontSize: 13,
    fontWeight: "600",
    color: "#6c757d",
  },

  modalBackdrop: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.5)",
    justifyContent: "center",
    alignItems: "center",
  },
  encodingCard: {
    backgroundColor: "#fff",
    borderRadius: 20,
    padding: 32,
    alignItems: "center",
    width: 260,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.15,
    shadowRadius: 24,
    elevation: 12,
  },
  encodingTitle: {
    fontSize: 17,
    fontWeight: "700",
    color: "#1a1a2e",
    marginTop: 16,
  },
  encodingBarBg: {
    width: "100%",
    height: 6,
    backgroundColor: "#e9ecef",
    borderRadius: 3,
    marginTop: 16,
    overflow: "hidden",
  },
  encodingBarFill: {
    height: "100%",
    backgroundColor: ACCENT,
    borderRadius: 3,
  },
  encodingDetail: {
    fontSize: 12,
    color: "#6c757d",
    marginTop: 8,
  },

  resultModalContainer: {
    flex: 1,
    backgroundColor: "#f8f9fa",
  },
  resultModalHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 20,
    paddingBottom: 8,
  },
  resultCloseButton: {
    paddingVertical: 4,
    paddingHorizontal: 2,
    borderRadius: 8,
    width: 50,
  },
  resultCloseButtonPressed: {
    opacity: 0.6,
  },
  resultCloseText: {
    fontSize: 16,
    fontWeight: "600",
    color: ACCENT,
  },
  resultModalTitle: {
    fontSize: 17,
    fontWeight: "700",
    color: "#1a1a2e",
  },
  resultScrollView: {
    flex: 1,
  },
  resultScrollContent: {
    padding: 20,
    paddingBottom: 8,
  },
  resultPreviewCard: {
    backgroundColor: "#1a1a2e",
    borderRadius: 16,
    padding: 4,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 12,
    elevation: 6,
  },
  resultGifPreview: {
    width: "100%",
    height: 300,
    borderRadius: 12,
  },
  resultDetails: {
    flexDirection: "row",
    gap: 10,
    marginTop: 16,
  },
  resultDetailChip: {
    flex: 1,
    backgroundColor: "#fff",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    alignItems: "center",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.04,
    shadowRadius: 4,
    elevation: 1,
  },
  resultDetailLabel: {
    fontSize: 10,
    fontWeight: "600",
    color: "#adb5bd",
    textTransform: "uppercase",
    letterSpacing: 0.3,
  },
  resultDetailValue: {
    fontSize: 16,
    fontWeight: "700",
    color: "#1a1a2e",
    marginTop: 2,
  },
  resultPathCard: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 12,
    marginTop: 12,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.04,
    shadowRadius: 4,
    elevation: 1,
  },
  resultPathLabel: {
    fontSize: 10,
    fontWeight: "600",
    color: "#adb5bd",
    textTransform: "uppercase",
    letterSpacing: 0.3,
    marginBottom: 6,
  },
  resultPathRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  resultPath: {
    flex: 1,
    fontSize: 11,
    color: "#6c757d",
    fontFamily: Platform.OS === "ios" ? "Menlo" : "monospace",
  },
  copyButton: {
    backgroundColor: "#f1f3f5",
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#e9ecef",
  },
  copyButtonPressed: {
    backgroundColor: "#dee2e6",
    borderColor: "#ced4da",
  },
  copyButtonCopied: {
    backgroundColor: "#d3f9d8",
    borderColor: "#b2f2bb",
  },
  copyButtonText: {
    fontSize: 12,
    fontWeight: "600",
    color: "#495057",
  },
  copyButtonTextCopied: {
    color: "#2b8a3e",
  },
  resultBottomBar: {
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 8,
    gap: 8,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: "#e9ecef",
    backgroundColor: "#fff",
  },
  resultButton: {
    borderRadius: 14,
    paddingVertical: 16,
    alignItems: "center",
  },
  resultShareButton: {
    backgroundColor: ACCENT,
  },
  resultShareButtonPressed: {
    backgroundColor: "#4a4cb0",
  },
  resultShareButtonText: {
    fontSize: 17,
    fontWeight: "700",
    color: "#fff",
  },
  resultNewGifButton: {
    backgroundColor: "transparent",
  },
  resultNewGifButtonPressed: {
    opacity: 0.6,
  },
  resultNewGifButtonText: {
    fontSize: 15,
    fontWeight: "600",
    color: ACCENT,
  },
});
