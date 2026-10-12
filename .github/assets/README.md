# Stash Native icon

[`stash_native.svg`](stash_native.svg) is the source for the repository logo and both mobile sample icons. Its outlined S uses the original Stash wordmark's vector path, preserving smooth curves at every size.

The blue gradient and grid come from [Blueprint 1.4.0](https://github.com/MustafaNatur/blueprint/tree/400e45e1fa6176b10251a415cdc4885f0da03c7e), using its default colors, grid, and 9-point outline width. The S outline uses the vector directly instead of Blueprint's bitmap subject tracing.

- Repository: SVG, with a 320-pixel PNG export.
- iOS sample: opaque 1024-pixel PNG in `AppIcon.appiconset`.
- Android sample: separate vector background and foreground for adaptive icons, the foreground for themed icons, and PNGs at the five standard launcher densities for older devices.

Keep all exports aligned with the SVG. Draw launcher masks through the platform; only Android's legacy round PNGs contain a circular crop.
