# JNA (used by UniFFI for Kotlin-to-Rust FFI)
-keep class com.sun.jna.** { *; }
-dontwarn com.sun.jna.**

# UniFFI generated bindings
-keep class uniffi.expo_gifski.** { *; }
