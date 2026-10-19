---
title: Sample Apps
nav_order: 2
description: Build and run the iOS and Android sample apps.
---

# Sample Apps

The repository includes an iOS and an Android sample app. They open the Checkout Card, the In-Game Browser, and the QR scanner, and show each callback as it arrives. Both build the SDK from source.

![Sample apps on iPhone and Android](../assets/images/sample-apps-dark.png)

## iOS

Open `iOS/Sample/StashNativeSample/StashNativeSample.xcodeproj` in Xcode 27.1, choose a simulator, and run the `StashNativeSample` scheme. To run on a device, set your team and a bundle identifier of your own under **Signing & Capabilities**.

## Android

With JDK 17 installed and `ANDROID_HOME` pointing to the Android SDK, run from `Android/`:

```sh
./gradlew :sample:installDebug
```

This builds the sample and installs it on the connected device or emulator. You can also open `Android/` in Android Studio and run the `sample` configuration.

## Checkout links

The **URL** fields start with a test page that can trigger each checkout callback. To test a real checkout, paste a [checkout link](https://docs.stash.gg/guides/stash-pay/integration#create-a-checkout-link), or add an instance with your App ID and ingress secret under **Instances** and tap **Generate Checkout**.

{: .warning }
The samples sign checkout requests on the device for testing only. In production, create checkout links on your backend and keep the ingress secret there.
