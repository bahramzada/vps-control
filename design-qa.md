# Design QA

## Comparison target

- Source visual truth: `QA/source-selected-design.png`
- Final implementation: `QA/implementation-overview-final.jpeg`
- Terminal empty state: `QA/implementation-terminal-empty-final.jpeg`
- Terminal connected state: `QA/implementation-terminal-open-final.jpeg`
- State: native macOS dark mode, configured VPS online, live read-only metrics, Docker engine active with socket permission locked.

## Viewport and normalization

- Source pixels: 1487 × 1058.
- Implementation pixels: 1166 × 768.
- Implementation capture: native window content captured by macOS Computer Use at the available 1166 × 768 desktop viewport.
- Density normalization: the comparison compositor scales each artifact to an equal 1000-pixel pane width with high-quality interpolation and preserves each aspect ratio. Focused comparisons use corresponding source/implementation content crops.
- The reference is taller than the available desktop viewport. The implementation therefore uses an intentional responsive two-row metric layout and a scrollable content region; this viewport difference is not treated as typography or spacing drift.

## Evidence

- Full view: `QA/comparison-full.png`
- Header and system health: `QA/comparison-system-health.png`
- Activity and Docker: `QA/comparison-lower-cards.png`
- Terminal whitespace before/after: `QA/comparison-terminal-whitespace.png`

## Required fidelity surfaces

- **Fonts and typography:** Native San Francisco/system typography matches the Apple target. Heading, body, caption, monospaced metric, and terminal hierarchies remain legible with no visible truncation in the captured state.
- **Spacing and layout rhythm:** Sidebar proportions, page margins, card radii, section gaps, dividers, and toolbar alignment follow the source. The narrower viewport uses four metrics followed by two equal-width metrics. Terminal tabs now stay at the top and the workspace fills the detail column.
- **Colors and visual tokens:** Dark canvas, translucent sidebar/toolbar material, blue selection, green health/security states, muted secondary text, and subtle borders closely match the source palette and preserve contrast.
- **Image and asset fidelity:** The target relies on interface icons rather than photographic assets. The implementation uses native SF Symbols and the real SwiftTerm surface; no placeholder raster art, emoji, handcrafted SVG, or CSS-style drawing substitutes are present.
- **Copy and content:** Azerbaijani interface copy with English technical terms is coherent. Dynamic values differ from the mock because the implementation displays real VPS state. Docker's locked state accurately represents the approved security boundary.
- **Responsiveness and accessibility:** Persistent controls remain visible at 1166 × 768, the content scrolls, labels are available through Accessibility, the terminal empty/connected states are keyboard-accessible, and native system materials/font sizing are used.

## Findings

No actionable P0, P1, or P2 visual mismatch remains in the compared viewport and state.

Accepted deviations:

- The source is wider/taller and shows six metrics in one row; the implementation's responsive two-row layout prevents value truncation at 1166 × 768.
- The source contains mock containers; the implementation shows the real `permission_locked` Docker state because root-equivalent access and Portainer are not approved.
- Live values, timestamps, uptime, and activity content intentionally differ from mock data.

## Comparison history

1. **P1 — Missing native window chrome:** The early build hid native traffic lights. Fixed by using the native title-bar window style. Post-fix evidence: `QA/comparison-full.png`.
2. **P2 — Duplicate health label:** SwiftUI Gauge rendered an extra label around the custom center content. Fixed with an empty Gauge label, hidden native labels, and a single custom heart/health overlay. Post-fix evidence: `QA/comparison-system-health.png`.
3. **P2 — Sparse activity and uneven metric width:** The initial screen lacked realistic activity density and the compact metric grid did not fill its region. Fixed with real read-only startup events, full-width metric rows, and a balanced responsive 4 + 2 layout. Post-fix evidence: `QA/comparison-full.png` and `QA/comparison-system-health.png`.
4. **P2 — Excess toolbar whitespace:** macOS distributed separate primary actions too widely. Fixed by grouping terminal, refresh, connection, divider, and date into one compact native toolbar cluster. Post-fix evidence: `QA/implementation-overview-final.jpeg`.
5. **P1 — Vertically floating terminal panel:** The empty terminal workspace used intrinsic height and left a large blank area above it. Fixed by filling the detail column, pinning the tab bar to the top, and centering a compact native empty state in the remaining canvas. Post-fix evidence: `QA/comparison-terminal-whitespace.png`.
6. **P1 — Stale terminal connection UI:** The real PTY connected while status controls stayed idle. Fixed by observing each tab model in dedicated status/content views. Post-fix evidence: `QA/implementation-terminal-open-final.jpeg`, where `Qoşulub`, sudo, and disconnect controls are present.

## Interaction checks

- Sidebar destinations opened: Overview, Docker, Services, Files, Terminal, Activity, and Settings.
- Terminal empty state opened a real SSH PTY as `jarvis`.
- Connected status, explicit sudo high-risk banner, disconnect, and session cleanup were exercised.
- Toolbar actions and live connection state remained accessible after the compact layout change.
- The final terminal empty state and connected canvas were rechecked after release packaging; both fill the full detail column without the former floating panel.
- The live Files browser and Services diagnostics tables were checked at the same 1166 × 768 viewport with real bounded VPS data and no clipping.

## Follow-up polish

- P3: Developer ID signing/notarization can improve the first-launch experience outside the development Mac.
- P3: Additional responsive captures on larger external displays can tune the single-row metric breakpoint.

final result: passed

## Toolbar option 3 — focused QA

### Comparison target

- Source visual truth: `QA/source-toolbar-option-3.png`.
- Rendered implementation: `QA/implementation-toolbar-option-3-final.jpeg`.
- Focused source crop: `QA/source-toolbar-option-3-crop.png` (1706 × 165 px).
- Focused implementation crop: `QA/implementation-toolbar-option-3-crop.png` (1165 × 56 px).
- Combined same-input evidence: `QA/comparison-toolbar-option-3-final.png`.
- State: native macOS dark mode, Overview selected, configured VPS online.

### Viewport and normalization

- Source concept: 1706 × 922 px ImageGen result; the toolbar component occupies a focused 1706 × 165 px crop.
- Implementation: 1165 × 768 px native window capture; the title/toolbar occupies a focused 1165 × 56 px crop.
- The comparison compositor scales both focused crops to an equal width while preserving their own aspect ratios. The source is an enlarged concept presentation, so the implementation intentionally retains the native macOS title-bar height rather than matching the concept's presentation scale.
- The implementation capture includes the native sidebar title-bar region and traffic lights; hierarchy comparisons use the detail toolbar content to avoid treating native window chrome as drift.

### Required fidelity surfaces

- **Fonts and typography:** Native San Francisco typography is used throughout. `VPS Control` is a 15-point semibold title, the centered server name is 14-point semibold, and the single-line date/time is a 12-point medium label with monospaced digits. Copy remains crisp, unwrapped, and optically centered.
- **Spacing and layout rhythm:** Back/forward share one 36-point capsule with a single divider. The centered server identity is plain text plus an 8-point online dot. Terminal, refresh, lock, divider, and date/time share one 36-point utility capsule. There are no nested pills or overlapping labels.
- **Colors and visual tokens:** The implementation keeps the existing near-black canvas, native ultra-thin material, subtle project border token, primary/secondary text tokens, and semantic green online state.
- **Image quality and asset fidelity:** This component contains no raster imagery. Native SF Symbols provide the terminal, refresh, lock, and navigation icons at display density; no approximated or handcrafted icons are used.
- **Copy and content:** `VPS Control`, `Jarvis VPS`, the secure connection state, and Azerbaijani date formatting are preserved. The runtime time differs from the static concept by design.

### Findings

No actionable P0, P1, or P2 mismatch remains. The native implementation preserves the chosen hierarchy and interaction model while using the platform's standard title-bar height.

### Comparison history

1. **P2 — Missing app title at the available native window width:** The first implementation let macOS suppress `VPS Control`, weakening the selected left-side hierarchy. Fixed by placing the title explicitly beside the navigation capsule. Post-fix evidence: `QA/implementation-toolbar-option-3-final.jpeg` and `QA/comparison-toolbar-option-3-final.png`.
2. **P3 — Extra separator punctuation in date/time:** A combined `Date.FormatStyle` inserted an additional comma before the time. Fixed by rendering date and time as two tightly grouped labels inside one line.

### Interaction checks

- The toolbar terminal action opened a real SSH PTY as `jarvis`, reported `Qoşulub`, and was disconnected and closed after verification.
- Back navigation returned to Overview.
- Refresh completed while the VPS remained online.
- The test terminal tab was removed, leaving the app in a clean Overview state.

### Follow-up polish

- P3: Recheck the same toolbar on a much narrower window if a compact-window layout is added later.

final result: passed
