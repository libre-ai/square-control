# Square Control

A local window layout tool for macOS. Today one keyboard shortcut (Control, Shift, Command and
Left Arrow) places the focused window on the left half of its screen; the core already keeps
the history an undo needs, but no shortcut is bound to it yet. The layout is decided by a pure Rust core
that has no dependency; a small Swift shell owns the hotkeys and moves windows through the
Accessibility API.

It has no network service, no account, no telemetry and no model. Its isolation boundary is
the macOS user account: the Accessibility grant is per user, and the state file is private to
that user. The release binary is checked against a closed list of imported symbols, and must
declare no URL scheme and carry no machine path.

Project of the [Libre AI](https://libre-ai.fr) constellation, couche 1 (workstation domain).

## Project status

<!-- libre-ai:project-status:begin -->
<!-- Section générée depuis project.v1.yaml — ne pas éditer à la main. -->

- Situation actuelle : The E0 skeleton is in the repository. The layout core does the left half of the visible frame with an undo history; its 15 tests and the 12 golden vectors pass in Rust and Swift on one machine (macOS 26.6.2, arm64). The binary gate and the frozen-application probe pass. The permission probes (Accessibility versus input monitoring, hotkey delivery, signing persistence) are still pending a grant or an idle session. The other layouts of the required matrix are not written. No CI job runs the Swift shell, the binary gate or the probes (they need macOS and a window server); the Linux CI covers the Rust workspace and the dependency policy. Not distributed, not signed for third parties.
- Maturité : specified
- Exposition : idea
- Confiance : medium
- Preuves vérifiées le : 2026-10-14
- Avancement : 26,3 % du périmètre actuellement déclaré

<!-- libre-ai:project-status:end -->

## Layout

| Path | Content |
| --- | --- |
| `crates/layout` | Pure layout core: frames in, frames out, history of observed frames |
| `crates/ffi`, `tools/uniffi-bindgen` | UniFFI bridge to Swift, the only crate that knows UniFFI |
| `shell/` | SwiftPM package: orchestrator, Accessibility gateway, hotkeys, state file |
| `golden/` | Golden vectors executed by both Rust and Swift |
| `scripts/` | Core and bundle builds, binary gate, dependency age guard, signing helpers |
| `PROTOCOL.txt`, `probes/` | Probe protocol, committed before the measurements, and raw results |

## Build and check

```sh
scripts/check.sh            # Rust workspace: format, lint, tests, dependency policy
scripts/build-core.sh       # core and local xcframework (macOS)
```

The Swift tests, the binary gate and the probes need macOS and a window server; see
`AGENTS.md` for the commands. Nothing here is signed for distribution to third parties.

## Licence

Source code: [EUPL-1.2](LICENSES/EUPL-1.2.txt). Documentation and probe records:
[CC-BY-4.0](LICENSES/CC-BY-4.0.txt). Licensing is declared per file by `REUSE.toml`.
