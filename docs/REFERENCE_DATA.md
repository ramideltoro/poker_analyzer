# Local reference data and hand review · v0.8.0

The app works offline. Internet access is used only by the separate development download script, never by capture or analysis. The three previously discussed resources are downloaded in full at the listed scope. The app bundles a compact, reproducible aggregate, evaluator tables and attribution files; large raw archives stay beside the project in `../PokerData/raw/`, outside Git. No user sessions, identifiers or screenshots enter this reference corpus.

| Resource | Download scope | Use |
|---|---|---|
| [PH Evaluator](https://github.com/HenryRLee/PokerHandEvaluator) | Entire develop archive, resolved `10be452e4c1ee40a6a56f06457f46bff27ca495a` | Apache-2.0 C evaluator/table subset directly ranks all 5–7-card Hold’em hands. Omaha files remain in the raw archive and are not linked. |
| [PHH dataset](https://github.com/uoftcprg/phh-dataset) | Entire GitHub main archive, resolved `e47fbd5816372360bade4de5d712346fe1bb70f6` | Every supported no-limit Hold’em record contributes to aggregate corpus counts. Every valid revealed two-card hand contributes to its canonical 169-class sample; completed boards contribute final-category counts. |
| [UCI Poker Hand](https://archive.ics.uci.edu/dataset/158/poker+hand) | Both training/testing files and names document | All 1,025,010 labels validate the evaluator, including UCI’s separate royal-flush class. Zero mismatches. This is a classification check, not an opponent model. |

The PHH GitHub archive does not contain the much larger ACPC limit/no-limit collection offered separately through Zenodo. That separate collection includes duplicates and unsupported variants and is outside this download. Non-NT variants present in the GitHub archive are counted but excluded from Hold’em summaries. Raw files preserve all variants originally downloaded. No claim is made that every poker dataset on the Internet has been collected.

The archive includes anonymized HandHQ July 2009 records, the 10,000 Pluribus experiment hands and other historical examples. Revealed-card samples are heavily selected toward showdown; completed boards are also selected. These frequencies must not replace conditional equity or be presented as modern Bovada player tendencies. The UI labels matching-class history separately and shows its sample size and most common recorded final category. All live equity still comes from legal random opponent hands conditional on your known cards and board. More historical hands do not remove opponent-range uncertainty. The faster evaluator permits 100,000 local Monte Carlo deals per sampled result (previously 12,000), with a conservative individual 95% bound of about ±0.43 percentage points. Heads-up river still enumerates 990 legal opponent hands exactly.

PHH repository MIT notice and dataset attribution are retained. The Zenodo metadata additionally identifies CC-BY-4.0; this attribution/license is also included. UCI is CC-BY-4.0. See `ThirdParty/` and the local archive manifest for sources and SHA-256 checksums.

## Reproduce

```sh
bash scripts/fetch-reference-data.sh /absolute/path/to/PokerData
# Review the generated JSON, then copy it into Sources/PokerCore/Resources/ and rebuild.
bash scripts/build-app.sh
```

Allow roughly 20 GB for raw archives plus extracted contents. The streaming C++ importer uses bounded per-record parsing and collects identifier lists for duplicate auditing; it never loads the full 16 GB corpus into memory. The checked-in JSON can be used without downloading anything. The importer is deliberately specific to the downloaded PHH serialization: single-line or multi-line `actions` arrays with comments, explicit `variant`, and standard two-character card notation. It is not a general TOML library. It ignores unknown `????` cards, validates uniqueness of all known hole/board cards per sample and only evaluates complete five-card boards. IDs used for the offline duplicate check are not exported. Files are processed in sorted path order. Repeated HandHQ IDs are scoped by venue and support both string and numeric identifiers. Their parsed action arrays are compared; exact repeats count once, and conflicting groups are quarantined in full before aggregation. Raw and excluded counts remain in the summary. `bash scripts/test-reference-tool.sh` verifies duplicate removal, multiline/comments and royal-flush labeling with small synthetic fixtures.

## After folding

Capture never stops at a fold. Two consecutive absent-hole-card observations plus a readable anchored board or folded hero-seat observation enter saved-card review. Your last confirmed hole cards are explicitly retained as counterfactual inputs. Stable matching board extensions update equity, win/tie/loss, final-category charts, current pot/stacks and exact category-improvement information. Automatic opponents track the currently visible remaining players, so the what-if model can change as other players fold.

The last decision EV, eligible pot and call threshold stay saved and labeled. Folding ends actual pot eligibility, so recomputing that decision’s EV using a later board would introduce hindsight and be misleading. In review the app never exposes a fresh `callEstimate`. Missing/rejected readings keep prior presentation muted. A cleared, replaced or colliding board ends updates to the saved hand; the next confirmed hole-card pair starts normal analysis. Capture Stop, stale capture, permission loss and interruption clear the review.

Cards disappearing can also mean an occlusion or transition. There is no reliable live hand identifier in v1. In particular, a preflop fold followed by a flop cannot prove same-hand continuity from cards alone. Review is therefore labeled hypothetical throughout. Clear/replacement detection protects against obvious hand boundaries but cannot establish semantic identity.

Exact improvement information enumerates all 1,081 flop runouts or 46 turn rivers, using the known hole cards and board only. “Higher category” means a better hand category, not merely a higher kicker, and may improve the board for everyone. These are not clean winning outs. On the river there are no future runouts. Board texture reports paired ranks, suit concentration and distinct ranks in a five-rank window. Starting-hand notation uses `s` for suited and `o` for offsuit.

## v0.15: validated category reference and higher-precision equity

The app adds numerical category data from [oscar6echo/Poker2](https://github.com/oscar6echo/Poker2), pinned to `f4c46143a6f4504f2b2fe82da88dadec84f1c46a`. Its exhaustive rank-distribution CSV contains all 7,462 ranks for every starting class. An independently written Ruby importer normalizes rank notation (including reversed offsuit notation), aggregates mutually exclusive best-five categories and checks all 169 columns sum to C(50,5) = **2,118,760** boards. The all-seven-card distribution also matches the known category totals over all 133,784,560 combinations. Suit permutations have the same category probabilities. This numerical reference improves the preflop final-category chart; it is not a win-equity table.

Only a compact 169-row numerical aggregate ships, with its source SHA-256. The original CSV stays outside the repository. Upstream code is neither executed nor bundled. Attribution/scope are in `ThirdParty/Poker2/NOTICE.txt`; the pinned repository has no license file. These are mathematical counts, not historical human hands or extra independent Monte Carlo samples.

The separate 14,365-row heads-up matchup table was inspected and rejected. Blocker-weighted comparisons with five million independent local deals gave AA 85.1953% versus the table-derived 85.0737%, and KK 82.3894% versus 82.2814%. Both differences exceeded the local individual 95% Hoeffding radius of ±0.06074 percentage points. These checks do not prove the precise upstream cause, but do not support presenting the table as a more accurate exact equity reference. Its runtime code, generated matchup values and two-billion-deal headline were removed before release. The separate nominal 300-million-deal Monte Carlo CSV is also excluded: its tie field is pot-share contribution rather than tie-event frequency, and the current generator's repeated seed / reduced random domain make the filename insufficient evidence of independent coverage. These raw diagnostic inputs remain outside the source.

Live heads-up flop/turn/river equity now enumerates **1,070,190 / 45,540 / 990** legal deals locally. Other equity calculations use **1,000,000 local uniform legal deals**, reducing the individual conservative 95% sampling radius from about ±0.43 to ±0.136 percentage points. Exact preflop category charts use the validated imported counts, independent of the number of random opponents. Enumeration is cancellable. Existing duplicate-card, split-pot and unsupported-pot safeguards remain. PHH historical observations remain separate.

All 169 category distributions are compared with independent seeded local simulations using a family-wise 95% Hoeffding bound over 1,521 category comparisons. All 2,118,760 final boards for 98s are additionally enumerated locally, matching every imported category count exactly. Exact heads-up flop/turn calculations agree with independent simulation within its bound. Other tests check sample counts, all suits of 98s, ties, cancellation and the exclusion of the rejected matchup reference. Sampling bounds quantify Monte Carlo noise under the stated random-opponent model, not uncertainty about actual opponents.

Reproduce the category import with:

```sh
bash scripts/fetch-preflop-reference.sh /absolute/path/outside/repository/poker2-reference
bash scripts/build-app.sh
```

Position does not change raw showdown equity conditional on the same cards and opponent distribution. It changes strategies, equity realization and the distribution of hands that continue. The engine still assumes random opponents. The v0.15 position controls provide explicit per-hand context for limited first-in cash-game rules; they do not implement solver EV, calling/re-raising ranges, blind defense or postflop positional strategy.
