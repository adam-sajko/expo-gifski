<p>
  <img
    src=".github/resources/expo-gifski.svg"
    alt="expo-gifski"
    height="48" />
</p>

🌈 Convert videos to high-quality GIFs in React Native & Expo, powered by [gifski](https://gif.ski/) (Rust).

<!-- <p align="center">
  <img src=".github/resources/expo-gifski-demo.gif" alt="expo-gifski demo" width="240" />
</p> -->

# Installation

### Add the package to your npm dependencies

```bash
npx expo install expo-gifski
```

### Configure the Expo plugin

Add the plugin in `app.json`:

```json
{
  "plugins": ["expo-gifski"]
}
```

### Build

```bash
npx expo run:ios
npx expo run:android
```

Prebuilt Rust binaries ship in the npm package — no Rust toolchain needed.

# API

```typescript
import { encodeGifFromVideo, addProgressListener } from "expo-gifski";
```

### `encodeGifFromVideo(videoUri, outputPath, options?)`

Converts a video file to a GIF. Returns a promise that resolves to the output file path.

```typescript
const result = await encodeGifFromVideo(
  "file:///video.mp4",
  "file:///output.gif",
  { fps: 10, width: 320, startTime: 1.0, duration: 3.0, quality: 90 },
);
```

Uses `AVAssetImageGenerator` on iOS, `MediaMetadataRetriever` on Android.

### `addProgressListener(callback)`

Subscribes to encoding progress events. Returns a subscription with a `remove()` method.

```typescript
const sub = addProgressListener(
  ({ progress, framesProcessed, totalFrames }) => {
    console.log(`${Math.round(progress * 100)}%`);
  },
);
// later: sub.remove()
```

### Options

| Option      | Type      | Default | Description                    |
| ----------- | --------- | ------- | ------------------------------ |
| `width`     | `number`  | auto    | Output width in pixels         |
| `height`    | `number`  | auto    | Output height in pixels        |
| `fps`       | `number`  | `10`    | Frames per second              |
| `quality`   | `number`  | `90`    | Quality 1–100                  |
| `repeat`    | `number`  | `-1`    | -1 infinite, 0 none, >0 count  |
| `fast`      | `boolean` | `false` | Faster encoding, lower quality |
| `startTime` | `number`  | `0`     | Start time in seconds          |
| `duration`  | `number`  | full    | Clip duration in seconds       |

# Example

Pick a video, encode it, show the GIF:

```tsx
import { useState } from "react";
import { Button, Image, Text, View } from "react-native";
import * as ImagePicker from "expo-image-picker";
import * as FileSystem from "expo-file-system";
import { encodeGifFromVideo, addProgressListener } from "expo-gifski";

export default function App() {
  const [gif, setGif] = useState<string | null>(null);
  const [status, setStatus] = useState("");

  const convert = async () => {
    const pick = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ["videos"],
    });
    if (pick.canceled) return;

    const output = FileSystem.cacheDirectory + `output-${Date.now()}.gif`;

    const sub = addProgressListener(({ progress }) =>
      setStatus(`${Math.round(progress * 100)}%`),
    );

    try {
      setStatus("Encoding…");
      const result = await encodeGifFromVideo(pick.assets[0].uri, output, {
        fps: 10,
        width: 320,
        quality: 90,
        duration: 3,
      });
      setGif(result);
      setStatus("Done!");
    } catch (e) {
      setStatus(`Error: ${e}`);
    } finally {
      sub.remove();
    }
  };

  return (
    <View style={{ flex: 1, justifyContent: "center", alignItems: "center" }}>
      <Button title="Pick video & make GIF" onPress={convert} />
      <Text>{status}</Text>
      {gif && (
        <Image source={{ uri: gif }} style={{ width: 320, height: 320 }} />
      )}
    </View>
  );
}
```

# License

The expo-gifski wrapper code is [MIT](LICENSE) licensed.

This package includes prebuilt binaries of [gifski](https://gif.ski/), which is licensed under [AGPL-3.0-or-later](https://www.gnu.org/licenses/agpl-3.0.html). See [THIRD-PARTY-NOTICES](THIRD-PARTY-NOTICES) for full attribution.

# Contributing

Contributions are very welcome! Please refer to guidelines described in the [contributing guide](CONTRIBUTING.md).
