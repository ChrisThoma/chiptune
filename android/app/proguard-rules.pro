# Chiptune keep rules for R8 (minify + shrink on release).
# Compose, AndroidX and coroutines ship their own consumer rules.
-keep class dev.individuation.chiptune.BuildConfig { *; }
-keepclassmembers enum dev.individuation.chiptune.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
