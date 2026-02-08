# Regenerating Xcode Projects After Rename

The StashPay → StashNative rename removed the old `.xcodeproj` files so they can be recreated cleanly.

## iOS Library (StashNative.framework)

1. Open Xcode → File → New → Project.
2. Choose **Framework** under iOS, click Next.
3. Product Name: **StashNative**, Language: **Objective-C**, click Next.
4. Save at: `iOS/StashNative/` (so the project is `iOS/StashNative/StashNative.xcodeproj`).
5. In the project navigator, delete the default source group Xcode created.
6. Add the library sources: File → Add Files to "StashNative" → select `iOS/StashNative/Sources/StashNative/` (include `include/`, all `.m` and `.h`). Ensure "Copy items if needed" is **unchecked** and the StashNative target is checked.
7. In Build Phases → Headers: move `StashNative.h` and `StashNativeCard.h` to **Public**.
8. Build Settings: set **Product Bundle Identifier** to `com.stash.stashnative`, **iOS Deployment Target** to 13.0.

## iOS Sample (StashNativeSample.app)

1. Open Xcode → File → New → Project.
2. Choose **App** under iOS, click Next.
3. Product Name: **StashNativeSample**, Interface: **Storyboard**, Language: **Swift**, click Next.
4. Save at: `iOS/Sample/` (so the project is `iOS/Sample/StashNativeSample.xcodeproj`).
5. Replace the default AppDelegate/ViewController with the app in `iOS/Sample/StashNativeSample/`: add all Swift files, `StashNativeSample-Bridging-Header.h`, `Info.plist`, `LaunchScreen.storyboard`, `Assets.xcassets`.
6. Build Settings: set **Objective-C Bridging Header** to `StashNativeSample/StashNativeSample-Bridging-Header.h`, **Product Bundle Identifier** to `com.stash.stashnative.sample`.
7. Link the StashNative framework: add the `StashNative.xcodeproj` (library) to the workspace or add the StashNative framework target as a dependency; under **Frameworks, Libraries, and Embedded Content** add **StashNative.framework** and set to **Embed & Sign**.

After regenerating, the CI workflows (which reference `StashNative.xcodeproj`, `StashNativeSample.xcodeproj`, target StashNative, scheme StashNativeSample) will build correctly.
