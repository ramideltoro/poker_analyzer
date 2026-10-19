# Live Card Reader · 0.10.0

Continuously scans a monitor you select and automatically looks for visible playing-card faces. It displays your detected hole cards, community cards, current combination, local showdown equity and a simplified dollar EV for calling. It automatically reads the current pot, Call/Check controls, occupied players’ remaining stacks and visible card backs. There is one dashboard with Start/Stop, Show logs and an optional manual-input override. No card-area marking, stored layouts, action recommendations, automated betting or hand history.

## Full-window dashboard

The app opens maximized to the current display’s usable desktop area, keeping native window controls, menu bar and Dock available. Use the header’s expand button to fill the screen again after resizing. The layout adapts across the entire window from a 1000×720-point content area upward and has no main scroll container.

A full-width probability/EV summary sits above three aligned columns. Showdown Outcome and expanded Hand Details share the left column, with Hand Details directly below the outcome chart. The center contains a call-threshold explanation and final-hand probabilities. Player stacks fill the right column; your cards and the community cards remain in a bottom dock. Panel heights, row spacing and selected text/card sizes grow with the window, keeping labels stable during live reading updates.

The threshold panel shows `call ÷ (eligible pot + call)`, the actual dollar inputs, pot odds, decision equity and the difference in percentage points. Larger windows also show the EV arithmetic and additional explanations. For example, a $1 call into a $3 eligible pot requires 25% equity: `$1 / ($3 + $1)`. This is a mathematical calling threshold under the displayed assumptions; it is not a solver recommendation. After a fold, the entire threshold/EV explanation uses the saved decision snapshot, even while what-if equity changes with later cards.

Hand Details now shows the street, starting class, current made hand, a best-five-card selection, board texture, category-improvement probabilities, improving-card list, exact runout count and historical sample context. Equivalent best-five selections may exist in tied hands. Historical samples and category improvements do not guarantee winning. The **?** button and Hand Details **…** popover retain extended definitions and lists. Keep the captured table unobstructed; move or resize the dashboard if needed.

## Start


For a fresh checkout, run `bash scripts/build-app.sh` first. The generated app is in `dist/Live Card Reader.app`; build outputs are excluded from Git. This project requires an Apple silicon Mac with macOS 15.2+ and Xcode installed.

1. Open `dist/Live Card Reader.app` on this Apple silicon Mac (macOS 15.2+).
2. Click **Start**, then choose the monitor containing your poker table in Apple's screen-sharing picker. Complete any macOS screen-recording permission prompt.
3. Keep one table visible with the cards uncovered. Put this app beside the table or on another monitor; it cannot see cards hidden behind another window.
4. Leave it running. **Stop** ends capture and clears the hand.

Start once per sharing session. Folding, the board clearing and a new deal do not require Stop/Start. After two matching observations, the reader remembers the card positions and checks those areas on every subsequent frame, alongside its full-screen search. It retains those positions between hands and through stale/failed readings, but reads card values anew. After your cards disappear, saved-card review can continue probabilities as the anchored board changes. Your last confirmed cards are labeled hypothetical and the last decision EV stays frozen. Missing or uncertain board readings pause updates while scanning continues. Previous confirmed values remain muted with an Updating label; they clear on a confirmed changed hand, Stop or capture loss. Explicit Stop, a new monitor-selection session, sleep or macOS ending screen sharing clears the remembered layout; capture requires a new Start after sharing ends.

The selected monitor is streamed continuously, targeting two frames per second. This version uses only the stream authorized through Apple's sharing picker; it makes no separate screenshot requests. An explicit stream idle event confirms unchanged content and allows the latest frame to be scanned again. Blank, suspended, stopped, invalid or unreadable frames discard the cached image; silence does not renew old readings. Safari tab titles and window resizing no longer stop reading, and no manual layout calibration is required. A user-initiated activity keeps background processing active while allowing normal system sleep. Sleep or capture revocation stops reading; click Start to resume afterward.

The footer shows received frames, completed scans, attempted candidates and recognized faces. The status distinguishes a received screen with no card-shaped areas, an excluded screen area, and ranks/suits that do not match. The detector supports conventional light faces and large centered suits. The supplied screenshot regressions cover Q-clubs/5-clubs, A-clubs/J-hearts with a flop, and 9-diamonds/5-diamonds with a flop, while ignoring miniature previews and history faces. They also cover lower card edges merging into the white seat panel. All four suit artworks are represented; other rank/layout combinations on the actual site still need validation. These screenshots do not establish general recognition accuracy. Very small, tilted, unfamiliar or obscured glyphs may be rejected.

## Automatic table inputs, equity and dollar EV

**Read table automatically** is on by default. Keep one entire table visible, including every occupied seat’s stack/card backs, the pot and your Call or Check button. The reader uses local Vision OCR and relative table geometry, alongside card recognition. It displays all detected remaining stacks and each active opponent’s effective remaining stack, `min(your remaining stack, their remaining stack)`. Seat numbers in the dashboard identify screen locations, not Bovada player identities.

The number of opponents comes from visible card backs. Sitting-out and new-player labels are excluded; seats with no visible cards are assumed out of the current hand. No hidden cards or betting ranges are inferred. The two supplied table screenshots pass with all occupied stacks, pot and zero-cost Check detected; generated six- and nine-seat layouts also test a separate Call amount, current street bets and side-pot labels. Other actual layouts and rendering states still need validation.

Money is parsed strictly into integer cents, with no guessed OCR character substitutions. Cards and relevant table data must agree across consecutive observations. Changed or missing required amounts immediately pause current EV. Previously confirmed values remain in a separate presentation snapshot, muted and age-marked; they never feed a current calculation. When the same confirmed cards/opponent count return, a bounded 16-entry in-memory math cache reuses that probability result to prevent repeated Monte Carlo fluctuations. A confirmed new hole-card hand, Stop, stale capture or capture interruption clears the presentation. During saved-card review, matching board extensions retain last-decision EV and update what-if probabilities. Manual mode changes clear incompatible EV.

Every label, chart row and seat row has a fixed place. The dashboard reserves a You row and eight opponent-position rows, with placeholders for unused positions. Currency and percentages update inline with monospaced digits and no insertion/removal animations. Card tiles keep a dark background in empty, live and updating states. Missing Call/Check controls show a waiting status; probabilities can remain current while call EV waits for a decision. Inactive players’ remaining stacks are excluded from EV confirmation requirements, so their OCR jitter does not interrupt a supported estimate. Large chip labels located inward from known seats are treated as bets instead of automatically triggering a missing-stack warning. Ambiguous active-player or pot eligibility readings still withhold current EV.

Once cards and active opponent count are confirmed, the app calculates your expected share of a shared pot at showdown, including split pots. Each opponent is dealt a uniformly random legal hand. Preflop, flop, turn and multiway river use 100,000 local Monte Carlo deals; a heads-up river enumerates all 990 possible opponent hands. Calculation runs separately from screen recognition.

Dollar EV uses the **current pot before your call**, including existing bets and prior contributions, and the **additional amount you must call**. Your new call is excluded from the pot input. `EV = equity × (eligible pot + call) − call` measures incremental value relative to folding; prior contributions are sunk. A Check button supplies a zero additional call and models checking through to showdown. The break-even calling equity is `call / (eligible pot + call)`.

Stacks cap the new call at your remaining chips. For a heads-up all-in, both players’ current street bets must be readable to resolve an uncapped amount-to-call; any unmatched opponent wager is removed from the eligible pot. Opponents’ remaining stacks show future betting exposure; they do not change showdown hand strength or add unwagered money to the current pot. Existing side pots, multiway short all-ins, unreadable active stacks or ambiguous activity/controls pause current EV with a specific waiting/eligibility message. Previous values remain visibly muted while data updates. Resolving arbitrary side pots requires complete contribution history, which this screen-only reader does not reconstruct.

This remains a **showdown model**: everyone reaching showdown, one pot with equal eligibility after the supported adjustment, no later bets, no future folds and no rake. Opponent ranges, future actions, position-dependent strategy and recognition errors are not modeled. It is not a solver or a complete prediction of action profitability.

To use explicit assumptions instead, switch **Read table automatically** off. Manual mode provides an opponent-count stepper (1–8) and dollar pot/call fields. Its single-pot formula does not use detected stacks or side-pot adjustments. Manual inputs reset when cards/opponent count change, readings become stale or capture stops; update them yourself as betting changes. The app never silently switches to manual values when automatic reading fails.

Monte Carlo results show a conservative two-sided 95% sampling bound using Hoeffding’s inequality, `sqrt(log(40) / (2 × samples))`; EV’s range propagates that bound through the same eligible pot and call. This covers simulation noise under the random-hand model, separately from unquantified range/recognition uncertainty. Exact river enumeration has no simulation noise. Old jobs are cancelled and ignored after recognized cards/opponents change.

Formula references: [expected value](https://www.pokerstars.com/poker/learn/lesson/examining-tournament-ev/), [pot odds](https://www.pokerstars.com/poker/learn/lesson/pot-odds/), and [Hoeffding’s original paper](https://www.tandfonline.com/doi/abs/10.1080/01621459.1963.10500830).

## Probability charts and definitions

The two fixed charts use a 0–100% scale. **Win outright** is the chance of beating every opponent. **Tie for best** is the chance of sharing first place; a tie beaten by another player counts as **Lose**. These three mutually exclusive outcomes sum to 100% before rounding. **Pot share** is showdown equity, counting only your fraction of a split pot, and therefore differs from tie probability. **Call threshold** is the required equity for zero call EV, a cost threshold rather than an outcome forecast.

The second chart displays the probability of finishing with each best-five-card category: high card, one pair, two pair, three of a kind, straight, flush, full house, four of a kind and straight flush (including royal flush). Exactly one category applies per deal, and the board can supply some or all of the best five cards. These probabilities sum to 100% before rounding and do not by themselves predict winning. Outcomes and categories are collected from the same simulation/enumeration as equity, including multiway splits.

The **?** help popover explains EV, pot/call/eligible pot, remaining/effective stacks, opponent assumptions and simulation uncertainty. Hover over a bar or amount for its individual definition. Sampled bars share the existing conservative 95% bound **for each metric individually**; this is not a simultaneous guarantee across every bar. Exact river enumeration has no simulation noise. Muted charts and amounts are visibly marked as previous confirmed readings while current data updates.

## Reference data and hand details

Version 0.10.0 includes PH Evaluator lookup tables, an aggregate of the downloaded PHH Hold’em archive, and validation against all 1,025,010 UCI labeled hands. It adds current made hand, board texture, starting-hand class, exact flop/turn category-improvement probabilities, card lists and historical revealed-hand sample information. Historical samples are biased and do not determine live equity. Raw archives are local beside this project, outside Git; the compact summary and licenses ship in the app. See [reference data and review documentation](docs/REFERENCE_DATA.md) for scope, provenance, reproduction and post-fold limitations.

## Troubleshoot 0 faces

Version 0.5.1 adds the supplied artwork's diamond silhouette, completing all four suit references. In the 7:20:45 PM screenshot, the previous version recognized the three spades on the board but rejected both hole-card diamonds because their suit matches were ambiguous. The updated reader detects 9-diamonds/5-diamonds and exactly 6-spades/4-spades/Q-spades at the original resolution and at 3840×2160, 2560×1440 and 1920×1080 with small pixel offsets. The previous A-clubs/J-hearts flop and Q-clubs/5-clubs crop also still pass. Acceptance thresholds are unchanged. These are image-replay checks; other live hands still need validation.

Quit and reopen the app after updating; check **v0.10.0** at the bottom. Start screen sharing, leave the table visible for 10–15 seconds, then click **Show logs**. Finder selects this launch's `.jsonl` file. Attach that file for diagnosis. It is in `~/Library/Application Support/LiveCardReader/Logs/`.

Logs contain app/build/OS version, picker and permission-preflight events, capture errors, stream status codes, input dimensions, hint counts and accepted-face rectangles, received-frame counts, scan duration and frame age, exclusion coverage, candidate counts, rank/suit match scores and rejection categories. Table diagnostics add field-presence flags, detected/readable seat counts, confirmation state and generic incomplete reasons; they exclude amounts and recognized text. Per-candidate details record the rectangle, crop method, numeric match scores/margins and rejection stage, without predicted ranks or suits. The global permission preflight is diagnostic only; picker-authorized capture can work even when the global permission flag is false. Rejection counts describe attempts, which can include multiple proposals for the same shape.

## Repeated screen-recording permission dialog

The v0.4.1 logs showed successful `capture_started` events followed immediately by `snapshot_error` code `-3801` (TCC permission denied). The extra screenshot request then stopped the approved stream. Version 0.4.2 removed that request, and the supplied v0.4.2 log confirms 82 incoming frames and completed scans without that error. Quit the old app completely and open `dist/Live Card Reader.app`; verify **v0.10.0** before clicking Start. Selecting a monitor in Apple's sharing picker for each new session is expected.

This development build is ad-hoc signed. Rebuilding changes its code identity, so an existing System Settings permission may refer to an earlier build. If macOS still explicitly requests global screen-recording access, remove the old Live Card Reader entry in System Settings → Privacy & Security → Screen & System Audio Recording, add the exact current app from `dist`, enable it and quit/reopen the app. Do not reset permissions for unrelated apps. Apple's explanation of development signing and privacy authorization is at https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements.

Logs contain **no screenshots, card values, monetary amounts, OCR text, window titles or URLs**. Each launch uses private-permission JSONL files; rollover is bounded to three files of about 5 MB each for that launch. If rollover occurred, include the matching `-part1` and `-part2` files. Prior launches are retained until you remove their diagnostic files.

## What identification means

The detector proposes card rectangles using Vision and bright connected regions, reads rank/suit glyph shapes, and groups nearby cards into rows. Joined white faces can be separated using their top caps; the full width below the rank is searched for a large suit. Condensed rank templates and small alignment/width tolerances handle font and resize differences without lowering the acceptance thresholds. Miniature faces are filtered relative to the largest recognized faces before grouping and duplicate checks.

It assumes the single isolated two-card row below a possible three-to-five-card board is your hand. It does not know your account or seat identity, or semantically identify the live table versus a historical image. With multiple comparable candidate pairs, comparable duplicate faces, ambiguous row layouts or uncertain glyph matches it shows no hand rather than selecting one. Keep one live table visible and avoid other large card images.

Cards must agree across successive scans before being treated as current. Changed, missing or ambiguous readings pause current calculations except for explicitly labeled saved-card review after your hole cards disappear. Previous confirmed data can remain muted in its fixed cells while scanning continues; a confirmed changed hand or capture invalidation clears that presentation. The combination label uses only recognized cards; unread board cards can change the complete hand's category. Rank and suit similarity scores are geometric match scores, not calibrated probabilities of correctness.

The app ignores only the visible parts of its own windows and a still-open previous reader version, including their recently moved positions. Reader windows fully covered by Safari or located on another macOS Space no longer mask the playing surface. This fixes a possible cause of perpetual 0 faces. Its window still physically covers content behind it, so keep it away from the table's cards.

## Local processing

No accounts, cloud service, API keys, browser extension or network requests. Frames stay in memory: the latest stream image is cached for explicit idle events, alongside the processing frame and latest waiting frame. The cache is replaced on a new complete frame and discarded on interruption or stop; images are never saved to disk. Only the diagnostic metadata described above is saved. Old versions' local history/settings files are left untouched and are no longer opened.

## Build and test

```sh
bash scripts/build-app.sh
bash scripts/test.sh
```

The build is ad-hoc signed for local use, not notarized for public distribution. The scripts use the installed Xcode compiler/Command Line Tools SDK and Apple's XCTest runner. `VERIFICATION.md` describes test evidence and the remaining live-capture validation limits.
