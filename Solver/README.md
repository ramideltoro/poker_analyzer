# Local postflop solver helper

A separate JSON stdin/stdout command-line program, `live-card-solver`, built for the native reader. No network calls or screen access. Wrapper copyright (C) 2026 Live Card Reader contributors, licensed **AGPL-3.0-or-later**, without warranty. The engine is copyright (C) 2022 Wataru Inariba under the same license. See `LICENSE`; dependency licenses and original notices are retained in `vendor/`.

Engine: https://github.com/b-inary/postflop-solver
Pinned commit: `9d1509fe5077d019825f833eed04b16d342dfda1`.
The vendored engine has one compatibility-only modification: three raw-pointer child-vector references in `src/action_tree.rs` are made explicit (`(&(*node).children)[…]`) for the current Rust compiler's `dangerous_implicit_autorefs` lint. No algorithm change. The original README notes upstream development is suspended.

## Rebuild without network access

Install Rust using https://rustup.rs and Apple's command-line tools. From the project root:

```sh
bash scripts/build-solver.sh
cd Solver
cargo test --release --locked --offline
```

`Cargo.lock`, the engine source and all registry dependencies are checked in. `.cargo/config.toml` redirects registry dependencies to those local sources. `COACH_CARGO_BIN` optionally selects a Cargo executable; `COACH_SOLVER_TARGET_DIR` optionally selects the build-cache directory. Tested with Rust 1.99.1 on arm64 macOS. `scripts/build-app.sh` signs and bundles the helper and a `GTOSolverSource.zip` containing its full source, dependency sources, licenses, lockfile, and build script. Rebuilding from that archive does not require the Swift application.

## Protocol 1

Read one UTF-8 JSON object from stdin (maximum 64 KiB); write exactly one JSON object to stdout. Errors are `{ "error": "…" }`. See `src/main.rs` for the complete typed schema and validation. Request keys use snake_case:

```json
{"protocol":1,"hole":["As","Kd"],"board":["2c","3d","4h","5s","9c"],"oop_range":"AsKd","ip_range":"KcKh","hero_ip":false,"pot_cents":200,"stack_cents":100,"facing_bet_cents":100,"rake_percent":0,"rake_cap_cents":0,"max_iterations":500,"target_gap_percent":0.5,"seconds":20}
```

This deliberately degenerate test range has a certain winning wheel and gives CALL EV +300 cents. Real studies should use both players' *full plausible ranges*, not disclose the actual hero hand as the entire hero range. The selected hand must have positive weight. Specific combos use the higher rank first, e.g. `AsKd`; ranges support comma-separated pairs/suited/offsuit classes, plus/dash expansion, and weights such as `AQo:0.5`.

Money is integer cents. `pot_cents` excludes the first opposing bet; `stack_cents` is the equal effective remaining stack **before** that bet. Hero has invested zero chips on this street. `facing_bet_cents` is zero or that first opposing bet, never a raise-to total. OOP starts at the root; IP without a facing bet follows OOP Check. OOP facing a bet follows Check → IP Bet; IP facing a bet follows OOP Bet. The exact facing bet is added to the tree before solving. Impossible, terminal, zero-reach and duplicate-card situations are rejected.

## Method and limits

Discounted CFR; two threads; all future board runouts represented by the upstream exact/isomorphic card model. The action abstraction uses 50%-pot bets and pot-sized raises, with all-ins when a modeled size reaches the effective stack, with normal minimum-raise clamping. This is *not* a full no-limit size space. No preflop, multiway, side-pot, unknown earlier raise sequence, bunching, opponent-stat range inference, or guaranteed individual-hand best action. Ranges and rake are explicit assumptions.

20 seconds / 500 iterations / 0.5%-root-pot exploitability are UI defaults. Hard input bounds: 60 seconds, 2,000 iterations, SPR 20, pot and stack at most $10,000 each. Strategy storage switches to the engine's 16-bit compressed representation above 256 MiB uncompressed, and rejects trees needing more than 512 MiB of strategy storage. This limit excludes tree/card-cache/worker overhead; it is not an OS resident-memory cap. The parent process enforces a wall deadline with 15 seconds of setup/finish allowance and kills a cancelled/timed-out helper. Large trees can be rejected or miss the requested target.

Outputs include per-action frequency and incremental EV in cents, frequency-weighted strategy EV, conditional range equity, actual iterations/time, strategy memory/compression, root exploitability and whether the requested target was reached. Fold EV is zero; past contributions are sunk. Rake is a configurable constant percentage capped at the supplied amount, applied by the engine to postflop terminal pots; it does not reproduce an operator's complete rake schedule/rounding rules. Zero rate or zero cap models no rake. Root exploitability is **not** a per-hand EV confidence bound, nor a range-uncertainty measurement.
