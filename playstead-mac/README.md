# Playstead for Mac

This is the implementation root for the native macOS reference client.

It will own pairing and Keychain credentials, catalogue browsing, selective verified caching, controller UX, emulator and BIOS adapters, launch preflight, offline operation, and persistent-save capture and recovery. SwiftUI is the default UI technology with targeted AppKit integration where the empirical Mac adapter spike requires it.

The client depends only on the versioned HTTPS protocol and downloaded assets—not Phoenix LiveView internals or server implementation details. It will be initialized when the roadmap reaches the Mac vertical slice and its signing, notarization, sandbox, controller, and emulator-launch assumptions have been tested.

