# Troubleshooting

## OpenSSH control socket path exceeded the Unix-domain limit

- **Context/Component:** macOS OpenSSH multiplexing for metrics and terminal sessions
- **Error:** Live SSH failed because the original control path under `NSTemporaryDirectory()` exceeded the Unix-domain socket path-length limit.
- **Failed Attempts:** Reusing the long app-specific temporary path and `%C` filename still exceeded the limit.
- **Solution:** Use the permission-validated `0700` directory `/private/tmp/vpsc-<uid>/com.vps-control.ssh` and share its short `%C` control path between collectors and terminals.

## Ad-hoc code signing rejected resource metadata

- **Context/Component:** `Scripts/package-app.sh` and the bundled SwiftTerm resources
- **Error:** `codesign` reported resource-fork/Finder metadata, while a direct recursive xattr cleanup initially hit non-writable packaged shader resources.
- **Failed Attempts:** Signing before metadata cleanup; running `xattr -cr` before making copied resources writable.
- **Solution:** Build in a private temporary staging directory, make the staged bundle user-writable, recursively clear extended attributes, sign and strict-verify it there, then create an xattr-free ZIP and verify a fresh extraction. A convenience `.app` copy remains in `dist`, but macOS File Provider may reattach Finder metadata to that directory copy; the verified ZIP is the portable artifact.

## Terminal status controls stayed visually idle

- **Context/Component:** SwiftUI terminal tab/status presentation
- **Error:** The SSH PTY and remote prompt were active, but the status stayed `Hazır` and the sudo button remained disabled.
- **Failed Attempts:** First-output callbacks and title callbacks correctly changed the model, but the parent view did not observe each tab's published state.
- **Solution:** Move status controls and terminal content into child views with `@ObservedObject` tab models. Real UI verification then showed `Qoşulub`, active sudo, and clean disconnect state.

## Terminal workspace floated vertically

- **Context/Component:** Empty terminal screen in the `NavigationSplitView` detail column
- **Error:** The terminal workspace kept its intrinsic height and was vertically centered, leaving a large blank area above it.
- **Failed Attempts:** Styling the tab strip alone did not change the parent layout behavior.
- **Solution:** Bind the workspace and content to the full available width/height with top-leading alignment, fix the tab bar to 46 points, and use a compact centered empty state inside the remaining canvas.

## Generated macOS iconset was rejected by iconutil

- **Context/Component:** Packaging the selected raster artwork as the native application icon
- **Error:** `iconutil` rejected a mechanically generated complete iconset as invalid; the first asset-catalog compilation also produced no icon because `actool` requires an output partial Info.plist path when compiling an app icon.
- **Failed Attempts:** Direct `iconutil` conversion; `actool` compilation without `--output-partial-info-plist`.
- **Solution:** Keep the ten standard macOS icon representations in `AppIcon.appiconset`, compile them with `actool --app-icon AppIcon --output-partial-info-plist ...`, and package both the resulting `AppIcon.icns` and `Assets.car` resources.

## sips crop offsets did not produce deterministic top-edge QA crops

- **Context/Component:** Focused Product Design comparison evidence for the native toolbar
- **Error:** `sips --cropOffset` repeatedly returned the image center or a blank edge instead of the requested top title-bar region.
- **Failed Attempts:** Zero, positive, and negative crop offsets with `sips`.
- **Solution:** Use an AppKit/CoreGraphics crop with an explicit pixel rectangle, then verify the produced crop visually before composing the same-input comparison image.

## Terminal QA capture contained client IP metadata

- **Context/Component:** GitHub preparation and local visual QA evidence
- **Error:** A connected-terminal screenshot included OpenSSH's `Last login ... from ...` line with the client public IP even though the server endpoint elsewhere in the UI was masked.
- **Failed Attempts:** None
- **Solution:** Keep the entire local `QA/` directory Git-ignored and exclude it from the initial repository add. Retain only the textual QA report in source control. Future publishable captures must use synthetic sessions or be explicitly redacted and re-audited before tracking.
