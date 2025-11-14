# expo-gifski

[gifski](https://gif.ski/) GIF encoder for Expo / React Native. Rust-powered, runs on iOS and Android.

Video in, GIF out. Progress callbacks, quality/FPS/size control.

<p align="center">
  <img src="assets/expo-gifski-demo.gif" alt="expo-gifski demo" width="240" />
</p>

## Install

```bash
npx expo install expo-gifski
```

Add the plugin in `app.json`:

```json
{
  "plugins": ["expo-gifski"]
}
```

```bash
npx expo run:ios
npx expo run:android
```

Prebuilt binaries ship in the npm package -- no Rust toolchain needed.

## Usage

```typescript
import { encodeGifFromVideo, addProgressListener } from "expo-gifski";
```

### Encode

```typescript
const result = await encodeGifFromVideo(
  "file:///video.mp4",
  "file:///output.gif",
  { fps: 10, width: 320, startTime: 1.0, duration: 3.0, quality: 90 },
);
```

Uses AVAssetImageGenerator on iOS, MediaMetadataRetriever on Android.

### Progress

```typescript
const sub = addProgressListener(
  ({ progress, framesProcessed, totalFrames }) => {
    console.log(`${Math.round(progress * 100)}%`);
  },
);
// later: sub.remove()
```

### Quick example

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

### Options

| Option      | Type      | Default | Description                    |
| ----------- | --------- | ------- | ------------------------------ |
| `width`     | `number`  | auto    | Output width in pixels         |
| `height`    | `number`  | auto    | Output height in pixels        |
| `fps`       | `number`  | `10`    | Frames per second              |
| `quality`   | `number`  | `90`    | Quality 1-100                  |
| `repeat`    | `number`  | `-1`    | -1 infinite, 0 none, >0 count  |
| `fast`      | `boolean` | `false` | Faster encoding, lower quality |
| `startTime` | `number`  | `0`     | Start time in seconds          |
| `duration`  | `number`  | full    | Clip duration in seconds       |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
