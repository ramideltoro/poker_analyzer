# GTO solver workspace (v0.21)

Open the **GTO solver** tab. It uses a bundled local [postflop-solver](https://github.com/b-inary/postflop-solver) helper; no account, API, cloud computation, or automatic betting is involved. Build requirements now include Rust; the installed app needs no Rust installation.

1. Enter a flop, turn or river plus your cards, or use **Copy live spot** when enabled.
2. Set your relative **postflop** order, the root pot/effective stack, and the first bet you face. The root pot excludes that bet; root stacks precede it. This first version cannot import a street where you already invested or face a raise after your own bet/call.
3. Review both full ranges and rake. Defaults are illustrative broad ranges and a clearly editable zero-rake study assumption, not opponent observations or an assertion of Bovada's current rake. `TT+,AQs+,AKo` and weights such as `AQo:0.5` are supported. Do not set your full range to your actual hole cards unless deliberately studying a revealed-card toy game.
4. Click **Solve locally**. Action bars show the strategy frequency and dollar EV for the selected hand, including future modeled betting. The prominent move is the most frequent action; a mixed strategy deliberately uses multiple actions. It does not always choose the action with the largest noisy estimated EV.
5. Inspect convergence. A budget-limited result remains useful for study, but cannot replace the live suggestion. Results include actual work completed, conditional range equity, weighted strategy EV and measured root exploitability.

**Live integration:** A result can replace the ordinary suggestion only if it reached the requested target, was imported from a supported live spot, all independent table/action confirmations still agree, cards/pot/stacks/bet/dealer/order match, the form still matches its solved request, and the preferred action is offered. Non-all-in bet sizing also requires a known minimum big blind. The user still enters any wager in the poker client. Changed confirmed inputs permanently revoke the old live binding; reading gaps suppress it. Folds/capture reset revoke live use while study results remain available. The prior displayed move can remain explicitly historical under the app's existing retention policy.

**Automatic mode is opt-in.** It copies and solves subsequent supported live spots with the same explicit range/rake/tree settings. It does not infer a new range from earlier streets or player statistics. Every changed supported snapshot cancels the previous solve; generation checks reject late completions. A solve can finish after your decision window closes. Unsupported multiway/preflop/side-pot/unknown-wager situations continue to use the existing, clearly labeled heuristic estimates.

**Model separation:** Headline dashboard equity/EV remain the existing uniform-random check-down model. GTO workspace equity is against the solver's conditional range. When the suggested action has GTO SOLVER basis, its pot-odds comparison uses that conditional range equity; Max call still assumes no future bets. Only the solver action EVs include its modeled future responses and rake. None of these is merged with historical hands or the dashboard's deal count.

**What convergence means:** The measured exploitability is for the entire root profile within the limited bet tree (50%-pot bets and pot raises (stack-capped all-ins), plus the exact facing bet). A 0.5%-pot root gap is not an individual-hand error guarantee or a solution of every possible no-limit size. Incorrect ranges or missed history can produce inappropriate advice despite a small gap. No zero-error, profit or operator-permission claim is made.

**Resources and licenses:** Solver memory is limited to 512 MiB of strategy storage, with compression for large trees; auxiliary overhead is extra. Current limits and protocol are documented in [Solver/README.md](../Solver/README.md). The helper is a separate AGPL-3.0-or-later program. **How it works → Included source & license** reveals the bundled complete source archive. Per-decision local HandTraces include the live solver's range/rake/tree assumptions, iteration count and gap; general diagnostics retain their metadata-only policy. Frames are not saved.

## Verification

- Native analytical tests: certain winning/losing river all-in calls, split pots, raked split-pot EV, duplicate/blocker/range rejection, exact off-grid bet and both player orders.
- Swift/native JSON bridge verifies action legality/amounts, finite EVs, normalized frequencies, weighted strategy EV and convergence consistency before use.
- Generation/cancellation, edited-form and changed-table invalidation, missing wagers, multiple opponents, side pots and unconfirmed controls are covered by tests.
- Offscreen native SwiftUI renders at 1000×720 and 1900×1020 validate the workspace without reading the live poker table.
