# VPS Control Agent Instructions

## Purpose

This repository is for `vps-control`, a local-first application that lets the user visually monitor and administer their VPS without manually composing SSH commands. It must also provide an interactive terminal for exceptional cases.

The initial target is the user's Ubuntu VPS, reached through the existing SSH key as the non-root `jarvis` user. Root SSH login remains disabled. Privileged work must happen through an explicit `sudo` elevation initiated by the user.

## Product invariants

- The control application runs locally on the user's Mac.
- Management UI, local APIs, WebSocket endpoints, and forwarded ports bind to loopback only (`127.0.0.1` or `::1`).
- The VPS must not expose a public administration panel. SSH remains the only public management entry point unless the user explicitly approves a reviewed change.
- The app may hide SSH mechanics from the normal UI, but SSH remains the secure transport underneath.
- Monitoring is read-only by default. Mutating or privileged actions must be visibly distinguished.
- The terminal starts as `jarvis`, not root. Root access is available only through an explicit, visible `sudo` action inside the terminal.
- Do not enable root SSH login, password-based SSH login, or persistent unattended root shells.

## Instruction precedence and scope

- Follow the user's current request and higher-priority platform instructions first.
- Read this file completely before making project changes.
- Inspect the repository before assuming its architecture, commands, package manager, or tooling.
- Keep changes within the requested scope. Do not add unrelated features, dependencies, services, or VPS mutations.
- Ask before choosing the production stack, adding a production dependency, opening any VPS port, changing SSH configuration, or making a major architectural decision.

## Security boundaries

### Credentials and SSH

- Never copy an SSH private key into this repository.
- Never store sudo passwords, API keys, tokens, recovery codes, or private keys in source, config, fixtures, logs, screenshots, or test data.
- Use the user's existing SSH agent or an external key path with filesystem permissions enforced. A key path is configuration; key contents are never application data.
- Preserve and verify SSH host keys. Never use `StrictHostKeyChecking=no` or silently replace a changed host key.
- Secrets that eventually require persistence must use macOS Keychain or another user-approved secret store, never plaintext files.
- Do not place secrets in command-line arguments, process titles, URLs, analytics, or error reports.

### Local-only access

- Local servers must fail closed if they cannot bind to loopback.
- Do not bind management services to `0.0.0.0` or `[::]`.
- Portainer, if used, must listen on the VPS loopback interface and be reached only through an app-managed SSH tunnel.
- Do not open Portainer, terminal, Docker API, database, debug, or development-server ports in UFW.
- Docker-published management ports must include an explicit loopback host binding; never rely on UFW alone for Docker port isolation.

### Privilege and command execution

- Use unprivileged, read-only commands whenever possible.
- Curated UI actions must execute fixed commands with structured arguments. Never concatenate untrusted input into a shell command.
- Show the target, effect, and privilege level before destructive, disruptive, or irreversible actions.
- Reboot, shutdown, package removal, firewall changes, user changes, filesystem deletion, Docker pruning, volume deletion, and service disabling require explicit confirmation.
- Resolve and display exact destructive targets before execution. Never use broad unresolved paths, globs, or environment variables as destructive targets.
- Arbitrary shell commands are allowed only in a terminal session the user deliberately opened. Automation must not replay or infer terminal commands.
- Do not persist terminal keystrokes or sudo passwords. If optional command history is added later, it must be local, user-controlled, and secret-redacted.

### Terminal behavior

- Each terminal is an interactive SSH PTY owned by the current local user session.
- Closing the terminal or application must terminate or explicitly hand off its remote session; do not leave hidden root shells running.
- Display connection host, remote user, privilege state, and reconnect state prominently.
- Root elevation must show a persistent high-risk visual state until the shell returns to the normal user.
- Clipboard paste into a root shell or multiline command should have a warning when it may execute immediately.
- Terminal transport, resize, reconnect, timeout, and disconnect behavior require integration tests.

### Docker and Portainer

- Treat access to the Docker socket as root-equivalent.
- Do not add the SSH user to the `docker` group or grant passwordless Docker access without explicit user approval and a documented threat assessment.
- Prefer a loopback-only Portainer deployment through an SSH tunnel for the first visual Docker experience.
- Container publication must use explicit host addresses. Internal services default to loopback or a private Docker network.
- Volume deletion, image pruning, and stack removal are destructive operations and require confirmation plus an exact impact preview.

## Product behavior

The planned application should separate capabilities clearly:

- **Overview:** connection health, uptime, load, CPU, memory, swap, disk, network, updates, and security state.
- **Services:** inspect service status and logs; privileged controls require confirmation.
- **Docker:** containers, images, volumes, networks, logs, stats, and Compose stacks, initially through a secure local tunnel or a reviewed native integration.
- **Terminal:** interactive SSH shell as `jarvis`, with explicit `sudo` elevation when needed.
- **Activity:** local audit trail of app-triggered changes, with secrets redacted. Raw terminal contents are excluded by default.
- **Danger zone:** reboot, shutdown, firewall, user, deletion, and pruning operations with strong confirmation.

The UI must never report success based only on a click. It must verify the resulting remote state and show failures with actionable context.

## Engineering standards

- No implementation stack is approved yet. Record the decision before scaffolding code.
- Prefer a local desktop architecture with a small privileged surface and a typed boundary between UI and SSH operations.
- Reuse project scripts, conventions, and tooling once they exist.
- Do not add production dependencies without user approval.
- Keep remote command definitions centralized, typed, testable, and categorized by risk.
- Validate all remote responses; do not assume GNU/Linux command output is stable or complete.
- Use timeouts and cancellation for every network operation.
- Avoid telemetry by default. Any future telemetry must be opt-in and must exclude hosts, IPs, commands, terminal data, and credentials.
- Design for one VPS first without preventing multiple saved hosts later.
- Accessibility, keyboard navigation, reduced motion, and clear error states are product requirements, not later polish.

## Repository documentation

Maintain these files at the repository root:

- `about_project.md`: verified goals, architecture, stack, entrypoints, and setup commands.
- `progress.md`: append one entry after each completed write task using `YYYY-MM-DDTHH:MM:SSZ | Task Name | Detail | Modified Files | Status`.
- `troubleshooting.md`: record only resolved complex or recurring issues using the prescribed issue template.
- `ROADMAP.md`: keep phases and decisions current; do not mark a phase complete without verification.

Update documentation only with verified facts. Use `TODO` for unresolved decisions.

## Git rules

- Do not initialize a Git repository unless the user explicitly requests it.
- Read-only Git inspection is allowed when a repository exists.
- Any Git operation that mutates local or remote state requires explicit user authorization, including add, commit, push, pull, fetch, branch, switch, checkout, merge, rebase, reset, restore, stash, tag, clean, and init.
- Never commit credentials, local host configuration, generated logs, terminal recordings, or private infrastructure details.
- Preserve unrelated user changes and work safely in dirty worktrees.

## Verification requirements

- Run the narrowest relevant checks after every change and report exactly what ran.
- Security-sensitive changes require both configuration validation and behavioral verification.
- Test that local services are not reachable through non-loopback interfaces.
- Test SSH host-key mismatch handling, authentication failure, disconnects, timeouts, sudo failure, and partial command output.
- Test destructive-action confirmations and ensure cancel paths make no remote change.
- Never claim the VPS or application is secure solely because a configuration file looks correct; verify effective listeners, permissions, and behavior.

## Approved architecture

- The production client is a native macOS application built with SwiftUI and targeted AppKit where native behavior requires it.
- SSH transport uses the system /usr/bin/ssh client with strict host-key verification.
- Interactive terminal rendering uses exact-pinned SwiftTerm 1.15.0.
- The application uses one multiplexed SSH control connection per host and fixed, versioned read-only collectors to keep VPS load low.
- No application server or public management listener is part of the desktop architecture.
- Portainer remains a later, separately approved VPS change and must be loopback-only behind an SSH tunnel.

## Current constraint

The user approved implementation of the native architecture on 2026-08-28. Application scaffolding and the approved SwiftTerm dependency are authorized. VPS mutations, Portainer installation, Docker privilege changes, and new public listeners still require separate explicit approval.
