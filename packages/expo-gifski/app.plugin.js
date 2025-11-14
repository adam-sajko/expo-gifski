const { withDangerousMod } = require("@expo/config-plugins");
const fs = require("fs");
const path = require("path");

const withExpoGifski = (config) => {
  const modulePath = path.resolve(__dirname);

  const iosLib = path.join(modulePath, "ios", "libs", "libexpo_gifski.a");
  const androidLib = path.join(
    modulePath,
    "android",
    "src",
    "main",
    "jniLibs",
    "arm64-v8a",
    "libexpo_gifski.so",
  );

  const iosOk = fs.existsSync(iosLib);
  const androidOk = fs.existsSync(androidLib);

  if (!iosOk || !androidOk) {
    const missing = [];
    if (!iosOk) missing.push("iOS  (ios/libs/libexpo_gifski.a)");
    if (!androidOk)
      missing.push(
        "Android  (android/src/main/jniLibs/arm64-v8a/libexpo_gifski.so)",
      );

    const isDevCheckout = fs.existsSync(path.join(modulePath, "rust"));
    const hint = isDevCheckout
      ? "Run the Rust build scripts:\n" +
        "  ./ios/build.sh\n" +
        "  ./android/build.sh"
      : "The npm package may be corrupted — try reinstalling:\n" +
        "  rm -rf node_modules && npm install";

    console.warn(
      "\n" +
        "expo-gifski: prebuilt Rust binaries are missing!\n" +
        "Missing:\n" +
        missing.map((m) => "  - " + m).join("\n") +
        "\n\n" +
        hint +
        "\n",
    );
  }

  return withDangerousMod(config, [
    "ios",
    async (config) => {
      return config;
    },
  ]);
};

module.exports = withExpoGifski;
