---
title: Compatibility
parent: Package Architecture
nav_order: 4
description: Supported versions, toolchains, version-specific behavior, and runtime techniques.
---

# Compatibility

| Package | Minimum | Toolchain |
|---|---|---|
| iOS | iOS 15 | Xcode 27.1 |
| Android | API 21 | JDK 17, Gradle 8.5, AGP 8.1.1, compile SDK 34 |

iPhone Duo layouts need the app itself to link against the iOS 27.1 SDK. Mac Catalyst is not supported. Dependencies: [Package Installation](../usage/installation.md).

## Version-specific behavior

| iOS | Behavior |
|---|---|
| 15 | System medium and large detents |
| 16 | Custom detents and drag to expand |
| 16.4 | Inspectable WebViews |
| 26 | Glass loading background |
| 27.1 | Layout around reserved regions such as the iPhone Duo fold |

| Android API | Behavior |
|---|---|
| 21 to 22 | Rounded WebView corners through a hardware layer |
| 24 | Portrait released in multi-window |
| 26 | Recovery after renderer loss |
| 30 | `CONFIRM` haptic |
| 34 | Keep-alive service with a timeout |

Checkout pages get CSS safe-area insets from Android WebView 144.

## Runtime techniques

| Platform | Technique | Used for |
|---|---|---|
| iOS | Adds orientation methods to the app and scene delegate classes | Portrait checkout on iPhone |
| iOS | Sets the `UIDevice` orientation through key-value coding | Portrait on iOS 15 |
| iOS | Runtime subclass of WebKit content views | Hiding the keyboard toolbar in checkout fields |
| Android | Reflection into `androidx.browser` and the `stashnative-codelink` module | Optional dependencies |

## Limits

- The OS can refuse rotation, for example in multi-window or on foldables.
- Process death ends checkout. The SDK never replays a payment or invents a result.
