#!/bin/sh
# Aggregate quality gate: the commands of .github/workflows/ci.yml, in the same order,
# plus the dependency policy that the fleet's reusable workflow runs. Run it before pushing.
# The Swift shell tests, the binary gate and the probes need macOS and are not part of it:
# see probes/run.sh and scripts/check-binary.sh.
set -eu
cd "$(git rev-parse --show-toplevel)"
cargo fmt --all --check
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace
cargo deny --locked check bans licenses sources
