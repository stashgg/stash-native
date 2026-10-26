# Stash icons

[`stash_native.svg`](stash_native.svg) is the source for the repository logo and both mobile sample icons. Its outlined S uses the original Stash wordmark's vector path, preserving smooth curves at every size.

The grid and badges come from [Blueprint 1.4.0](https://github.com/MustafaNatur/blueprint/tree/400e45e1fa6176b10251a415cdc4885f0da03c7e). Gradients use the yellow, green, and blue color tokens from the [Stash website](https://www.stash.gg/). All three icons share the same S scale and 9-point charcoal outline (`#1E1E1E`), drawn directly from the vector.

- Native: green gradient (`#E1FFB0,#B3FF39,#48FF17`), with a 320-pixel PNG export.
- iOS sample: opaque 1024-pixel PNG in `AppIcon.appiconset`.
- Android sample: separate vector background and foreground for adaptive icons, the foreground for themed icons, and PNGs at the five standard launcher densities for older devices.
- Unity wrapper: [SVG](stash_unity.svg) and [1024-pixel PNG](stash_unity.png), with a blue gradient (`#99F3FF,#00E0FF,#0080FF`) and a `UNITY` badge.
- Unreal wrapper: [SVG](stash_unreal.svg) and [1024-pixel PNG](stash_unreal.png), with a yellow gradient (`#EBFF00,#E5FF11,#CEE50F`) and an `UNREAL` badge.

The backgrounds and badges use Blueprint's `--color` and `--badge` options. Both badges use charcoal text for contrast. Wrapper SVGs embed Blueprint's badge image, overlapping the S.

The README uses `*_rounded.png`: 1024-pixel Icon Composer exports with the iOS Liquid Glass rim, rounded corners, and transparent edges (`Default` rendition, design generation `26`). Full SVGs and sample app icons stay unmasked so the platform applies its launcher shape. Android's legacy round PNGs contain a circular crop.

The Apple and Android snippet icons in `platform/` come from [Bootstrap Icons v1.13.1](https://github.com/twbs/icons/tree/v1.13.1/icons). Their [MIT license](platform/LICENSE) is included alongside the SVGs.
