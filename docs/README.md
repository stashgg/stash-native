# Stash Native Technical Documentation

This folder contains implementation-level documentation for maintaining the Stash Native SDK across Android, iOS, Windows and macOS. Paths in the docs use links relative to the repository root so you can open the corresponding source files from the clone.

## Document Map

- [Architecture Overview](./architecture-overview.md)
- [JavaScript `stash_sdk` API](./stash-sdk-js.md)
- [Android Implementation](./android.md)
- [iOS Implementation](./ios.md)
- [Windows Implementation](./windows.md)
- [macOS Implementation](./macos.md)
- [Building Wrappers](./building-wrappers.md)
- [Maintenance and Testing](./maintenance-and-testing.md)
- [Desktop Validation Matrix](./desktop-validation-matrix.md) (manual gates for the desktop hosts)
- [Partner guide draft: Desktop](./partner/desktop-stash-pay-integration.mdx) (source for docs.stash.gg)

## Reading Order

1. Start with [Architecture Overview](./architecture-overview.md).
2. For checkout page authors or bridge contract work, read [JavaScript `stash_sdk` API](./stash-sdk-js.md).
3. Read the platform-specific implementation (`android.md`, `ios.md`, `windows.md` or `macos.md`). The two desktop hosts share `Desktop/shared` (bridge script, URL and config helpers, the `Session` callback state machine); read that first for any desktop change.
4. If you integrate via a game engine or need a custom binding layer, read [Building Wrappers](./building-wrappers.md).
5. Use [Maintenance and Testing](./maintenance-and-testing.md) before release or CI changes.
