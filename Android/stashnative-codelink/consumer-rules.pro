# Consumer ProGuard rules for the StashNative CodeLink module.
# Applied automatically when host apps enable R8/ProGuard.

# The core SDK resolves this class by name and calls its public constructor.
-keep class com.stash.stashnative.codelink.StashScannerSupport {
    public <init>(com.stash.stashnative.StashScannerHost);
}
-dontwarn androidx.camera.**
-dontwarn com.google.zxing.**
