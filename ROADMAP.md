# vps-control Roadmap

## Current development status

Development is intentionally paused after the verified local MVP. The current build remains usable for the single configured Ubuntu VPS; the phases below are planning commitments, not implemented capabilities.

When development resumes, the recommended order is: Compatibility Check, server profiles, localization, then AI Chat. Docker management and privileged administration remain separately approved work because they can change VPS state or introduce root-equivalent access.

## Product shape

The product is a native local Mac application with a visual VPS dashboard, secure Docker-management path, and interactive SSH terminal. SSH remains the VPS's only public management entry point.

## Phase 0 — Architecture and threat model

- [x] Native SwiftUI/AppKit application with no localhost web server.
- [x] Exact-pinned SwiftTerm 1.15.0 and system OpenSSH approved.
- [x] One-host data model structured for future multiple-host support.
- [x] External SSH key reference with strict permission validation.
- [x] Strict host-key verification, explicit sudo, timeouts, redacted activity, and confirmations specified.
- [x] Apple-style dark dashboard reference and screen structure selected.

Status: complete and verified.

## Phase 1 — Secure connection foundation

- [x] Native application shell and typed SSH boundary.
- [x] Server configuration in UserDefaults/environment, outside source control.
- [x] Connection test, strict host-key verification, timeout, cancellation, disconnect, and reconnect.
- [x] Connection host/user/authentication presentation with endpoint masking.
- [x] No application server; process inspection found no TCP listener.
- [x] Live read-only SSH integration passed against the configured VPS.

Status: complete and verified.

## Phase 2 — Read-only dashboard MVP

- [x] Uptime, load, CPU, memory, swap, disk, network counters, and OS information.
- [x] UFW, Fail2ban, SSH, Docker daemon, and socket-access state.
- [x] Controlled refresh, loading, stale-data, partial-failure, and offline states.
- [x] Values verified by opt-in live integration tests.
- [x] Cached package/security updates, reboot state, listening sockets, and failed units.
- [x] Bounded read-only remote file browser with metadata and navigation history.
- [ ] Richer bounded service logs.

Status: read-only dashboard, diagnostics, and file browser complete; richer logs remain.

## Phase 3 — Docker management

- [x] Docker daemon, CLI version, and socket trust state.
- [x] Safe locked state when `jarvis` lacks root-equivalent socket access.
- [ ] Loopback-only Portainer behind an app-managed SSH tunnel.
- [ ] Containers, images, volumes, networks, Compose stacks, logs, and stats.
- [ ] Verified start/stop/restart/recreate/pull actions and danger-zone confirmations.

Status: blocked on separate user approval for the Portainer/VPS change.

## Phase 4 — Interactive terminal

- [x] Multi-tab SSH PTY with resize, reconnect, disconnect, and keyboard input.
- [x] Every terminal starts as `jarvis`.
- [x] Explicit interactive `sudo -i` without password storage.
- [x] Persistent high-risk visual state and paste warnings.
- [x] Clean session termination on disconnect/tab close/app shutdown.
- [x] PTY, paste-policy, configuration, state, and environment tests.

Status: complete and verified.

## Phase 5 — Controlled administration

- [ ] Reviewed controls for service restart, package updates, reboot, shutdown, and maintenance.
- [ ] Exact target/impact previews and privileged-action confirmation.
- [x] Local redacted activity model for app-generated events.
- [ ] Backup and preflight checks for risky operations.

Status: pending.

## Phase 6 — Hardening and release

- [x] Unit, parser, timeout, cancellation, SSH-security, terminal, and live collector tests.
- [x] Secret-pattern and insecure-SSH-option audit.
- [x] Ad-hoc signed local `.app` packaging.
- [x] Product Design comparison QA with focused evidence.
- [ ] External-device network exposure test.
- [ ] Developer ID signing, notarization, updater, and preference export/recovery.

Status: local development release ready; distributable release work remains.

## Phase 7 — Compatibility Check

- [ ] Add a read-only preflight before a server profile is accepted as fully supported.
- [ ] Detect the OS, release, architecture, init system, shell, and required command availability instead of assuming Ubuntu 24.04 behavior.
- [ ] Verify SSH authentication, strict host-key trust, key permissions, the configured user's access, and interactive sudo availability without storing or replaying a password.
- [ ] Report each capability as `Supported`, `Partial`, or `Unavailable`, with a clear explanation and safe remediation guidance.
- [ ] Treat Docker, UFW, Fail2ban, update-notifier data, and systemd diagnostics as optional capabilities with graceful fallbacks.
- [ ] Build fixtures and opt-in live tests for Ubuntu 20.04, 22.04, and 24.04 before marking those releases supported.
- [ ] Refuse state-changing controls when their prerequisites have not been verified.

Status: planned; current live verification covers Ubuntu Server 24.04 LTS only.

## Phase 8 — Server profiles and multiple VPS support

- [ ] Replace the single saved server configuration with add, edit, duplicate, delete, and quick-switch profile flows.
- [ ] Store per-profile host, SSH user, port, external key path, known-hosts path, multiplexing preference, and capability results.
- [ ] Keep metrics caches, activity, terminal tabs, control sockets, connection status, and destructive confirmations isolated by profile ID.
- [ ] Add per-server connection health, last refresh, labels, ordering, and offline states to the sidebar.
- [ ] Support import/export of non-secret profile metadata only; never include private keys, passwords, tokens, terminal contents, or unmasked infrastructure data by default.
- [ ] Add migration from the current one-server UserDefaults format and tests that prevent cross-profile data leakage.

Status: planned; the current model is structurally identifiable but the UI and persistence support one active VPS.

## Phase 9 — AZ / EN / TR localization

- [ ] Move every user-facing string into Swift String Catalogs (`.xcstrings`).
- [ ] Ship Azerbaijani as the default language with complete English and Turkish translations.
- [ ] Maintain a terminology glossary so technical terms such as SSH, Docker, host, port, key, log, and terminal remain consistent.
- [ ] Localize dates, numbers, byte units, durations, plural forms, accessibility labels, errors, confirmations, and notifications.
- [ ] Add layout tests for longer English and Turkish copy, Dynamic Type, VoiceOver, keyboard navigation, and truncation.
- [ ] Allow an in-app language override while respecting the macOS system language by default.

Status: planned; current interface copy is primarily Azerbaijani with English technical terms.

## Phase 10 — AI Chat and agent features

- [ ] Add an optional provider/model configuration with API credentials stored only in macOS Keychain.
- [ ] Start with a read-only assistant that explains metrics, diagnostics, files, services, and Docker state from explicitly selected context.
- [ ] Redact IP addresses, usernames, local paths, terminal content, command output, and secrets by default before any external model request; show exactly what context will be sent.
- [ ] Generate structured action proposals through the existing typed command boundary instead of executing arbitrary shell text.
- [ ] Require a visible target, effect, privilege level, risk summary, and explicit user confirmation before every proposed remote action.
- [ ] Require a separate high-risk confirmation for privileged, destructive, disruptive, or irreversible actions; AI may never enter or retain a sudo password.
- [ ] Keep chat history local and optional, exclude raw terminal keystrokes by default, and provide delete/export controls.
- [ ] Add audit events for AI-proposed and user-approved actions, with secrets redacted and resulting remote state verified.
- [ ] Provide a fully functional non-AI mode when no provider is configured or network access is unavailable.

Status: planned; no AI provider, credential storage, model traffic, or autonomous command execution exists today.
