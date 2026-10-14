# Square Control Canonical Agent Rules

## Purpose

Square Control is a couche 1 product (P40, workstation domain): a local, single-user
window layout tool for macOS. A pure Rust layout core decides frames; a Swift shell
owns the hotkeys and the Accessibility calls. `project.v1.yaml` owns current state;
`PROTOCOL.txt` owns the measurement protocol of the probes. Fleet doctrine comes from:
https://raw.githubusercontent.com/libre-ai/project-governance/migrate/recover-code/docs/method/CONTEXT-TEMPLATE.md

## Domain doctrine

- No network, no telemetry, no model, no server: the isolation boundary is the macOS user account.
- The core (`crates/layout`) has no dependency, no clock, no OS term; it decides on frames the shell observed, never on frames it assumed.
- All Accessibility access goes through one gateway; window titles are never read.
- The shell calls only the symbols of `scripts/symbols.allowlist`; adding one is a reviewed change that `scripts/check-binary.sh` enforces on the built binary.
- The E2E channel exists only in a build with `-DSC_E2E`, under its own bundle id; the release bundle declares no URL scheme.
- Dependencies are pinned to exact versions, at least three days old, under MIT, Apache-2.0, BSD or MPL-2.0 only (`deny.toml`).
- Probe protocols are committed before the measurement they govern; raw results are recorded as produced, without machine paths.
- Signing identities, keychains and certificates never enter Git; they live outside the repository.
- A permission or behaviour is unverified until its probe has passed on the exact macOS version.

## Commands

- `scripts/check.sh` — format, lint, tests and dependency policy of the Rust workspace; the Linux part of CI.
- `scripts/build-core.sh` — builds the core and the local xcframework (macOS, never committed).
- `scripts/check-binary.sh` — closed symbol list, entitlements, URL scheme and machine-path gate on the built bundle.
- `probes/run.sh` — runs the probes of `PROTOCOL.txt` (macOS, window server needed).

## Working here

Security > quality > performance > completeness. Write the core test-first and keep the red run.
Code and commits are English. Stage files before tree-walking gates.
Never hide a red result, simulate a permission, or change a system security setting.
