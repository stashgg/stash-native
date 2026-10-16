---
title: Compatibility
parent: Platform Architecture
nav_order: 4
description: Supported versions, toolchains, version-specific behavior, and runtime techniques.
---

# Compatibility

| Target | Minimum runtime | Toolchain |
|---|---|---|
| iOS SDK | iOS 15 | Xcode 27.1, iOS 27.1 SDK for releases |
| Android SDK | API 21 | JDK 17, Gradle 8.5, AGP 8.1.1, compile SDK 34 |
| Android host test fixture | API 21 | AGP 9.1.1, compile SDK 37, target SDK 36 and 37 |

iPhone Duo layouts require the app itself to link against the iOS 27.1 SDK. Mac Catalyst is not supported. Dependencies: [Installation](../usage/installation.md).

## iOS versions

| iOS | Behavior |
|---|---|
| 15 | System `medium` and `large` detents. Portrait rotation through `UIDevice`. |
| 16 | Custom detents, content-drag expansion, portrait through `requestGeometryUpdate` |
| 16.4 | Inspectable WebViews |
| 18 | Per-frame keyboard and scroll updates through `UIUpdateLink` |
| 26 | Glass loading background, entrance animation correction |
| 27 | Centered sheet placement, scene delegate orientation hook |
| 27.1 | Reserved regions such as the iPhone Duo fold |

## Android versions

| API | Behavior |
|---|---|
| 21 to 22 | Hardware layer for rounded WebView corners |
| 21 to 23 | Subframe navigations cannot be told apart; deep links still work |
| 21 to 32 | Signature permission protects internal broadcasts |
| 24 | Portrait is released in multi-window |
| 26 | Renderer loss recovery, WebView version in telemetry |
| 29 | Commit detection, thermal state in telemetry |
| 30 | `CONFIRM` haptic |
| 33 | Non-exported receiver, predictive back callback |
| 34 | `shortService` keep-alive with timeout |

CSS safe-area insets need Android WebView 144 or later.

## Runtime techniques

| Platform | Technique | When |
|---|---|---|
| iOS | Adds or replaces orientation methods on the app and scene delegate classes; other windows forward to the original | First portrait presentation on iPhone |
| iOS | Sets `UIDevice` orientation through key-value coding | Portrait on iOS 15 |
| iOS | Runtime subclass of WebKit content views to hide the input accessory bar | Checkout WebViews |
| iOS | Counter-animation for a UIKit scale spring | First compact iPhone entrance on iOS 26+ |
| Android | Reflection into `androidx.browser` | Browser launches |
| Android | Reflective loading of the scanner | CodeLink |

## Limits

- Rotation requests can be refused by the OS, foldable postures, or multi-window.
- Process death ends checkout. The SDK never replays a payment or invents a result.
- A minimum OS version is a deployment contract. Test the oldest OS and WebView you support.
