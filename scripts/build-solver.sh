#!/bin/bash
set -euo pipefail
solverProject="$(cd "$(dirname "$0")/.." && pwd)"
solverCargo="${COACH_CARGO_BIN:-$(command -v cargo || true)}"
if [[ -z "$solverCargo" && -x "$HOME/.cargo/bin/cargo" ]]; then solverCargo="$HOME/.cargo/bin/cargo"; fi
if [[ ! -x "$solverCargo" ]]; then echo 'Install Rust (https://rustup.rs) to build the local GTO helper, or set COACH_CARGO_BIN.' >&2;exit 1;fi
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
export MACOSX_DEPLOYMENT_TARGET=15.2
export CARGO_TARGET_DIR="${COACH_SOLVER_TARGET_DIR:-$solverProject/.build/gto-solver}"
cd "$solverProject/Solver"
"$solverCargo" build --release --locked --offline
if [[ $# -gt 0 ]]; then cp "$CARGO_TARGET_DIR/release/live-card-solver" "$1";fi
