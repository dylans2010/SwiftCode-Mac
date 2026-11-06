# __APP_NAME__

A standalone macOS app scaffold created with the SwiftCode SDK (SwiftCode SDK §14.1).
This is **your own code** — the SDK only provided this starting template. There are no
extension-style sandbox restrictions on a standalone project; build, sign, and distribute
it exactly like any other native Mac app.

## Open / build / run

### In Xcode (recommended)

1. Create a new macOS App project: **File → New → Project → macOS → App**.
2. Product Name: `__APP_NAME__`; Organization Identifier: `__ORGANIZATION__` →
   the bundle identifier becomes `__BUNDLE_ID__`.
3. Language: Swift, Interface: SwiftUI. Uncheck the options you don't need (tests are fine).
4. Replace the generated files with `App.swift` and `ContentView.swift` from this folder.
5. Build and run with **⌘R**.

### From the terminal

```sh
# List schemes once the .xcodeproj exists
xcodebuild -list -project __APP_NAME__.xcodeproj

# Build
xcodebuild -project __APP_NAME__.xcodeproj -scheme __APP_NAME__ -configuration Debug build

# Run the built app
open "build/Debug/__APP_NAME__.app"
```

## What to change first

1. **App structure** — `App.swift` is the `@main` entry point. Rename the struct freely;
   only the `@main` attribute and the `Scene` body matter.
2. **Main view** — `ContentView.swift` holds the starter view. Replace its body with your
   real UI; native macOS conventions (toolbar, sidebar, menus) apply as usual.
3. **App identity** — bundle ID `__BUNDLE_ID__` and the version/marketing fields live in
   your Xcode target (Signing & Capabilities), not in these source files.
4. **Entitlements** — add an entitlements file only if your app needs sandbox capabilities
   (network client, files, etc.); a plain app needs none.
5. **Assets** — replace the system icon with real app icons in `Assets.xcassets`.

## Notes

- Requires macOS 14+ and a current Xcode with the Swift toolchain.
- This template is deliberately minimal: two Swift files and no asset catalogs or
  entitlements. Add Swift packages, menus, or persistence the way you normally would.
