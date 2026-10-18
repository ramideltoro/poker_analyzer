# Live Card Reader 0.5.1 verification

## Third screenshot: rejected diamonds

The supplied 7:20:45 PM screenshot reproduces the blank hand in the unchanged v0.5.0 detector. It accepts the board's 6-spades/4-spades/Q-spades but rejects both hole cards at the suit stage. The native 9-diamonds candidate's suit score is about 0.8953 with a 0.0057 margin; 5-diamonds is about 0.8967 with a 0.0094 margin. Both margins fall below the required 0.035. With no accepted two-card pair, grouping suppresses the hand and board. The latest v0.5.0 metadata log separately confirms 223 processed scans before an explicit Stop; it does not indicate an automatic stop after a fold.

Version 0.5.1 adds only the normalized diamond silhouette from that supplied artwork to the existing suit library. All four actual-artwork suits are now represented. Score and margin thresholds, scanning cadence and two-frame confirmation rules are unchanged. No screen coordinates or hand values are hardcoded in production recognition.

The full screenshot now selects 9-diamonds/5-diamonds and exactly 6-spades/4-spades/Q-spades, ignoring header previews and sidebar history. Native replay and nine resized/shifted variants (3840×2160, 2560×1440, 1920×1080; offsets 0, 1, 7) pass. A permanent card-and-felt crop excludes balances, betting controls, account data and browser chrome. Its test verifies confirmation, immediate clearing on an empty observation, retained positions and reacquisition after a fold. The full image remains in private work files, outside source/app archives.

The v0.5.1 optimized suite schedules 47 cases: 45 passed, two optional old original full-screenshot cases skipped, zero failures (about 4.79 seconds). Both available full screenshots, all three packaged crops, all 52 generated rank/suit combinations, continuous-hand tracking, equity/EV and capture-cache tests pass. The app is built and ad-hoc signature verified. This confirms the supplied failing image, not all live-site glyphs or layouts.

## Equity and manual-input call EV

Added a local equity engine with uniform legal opponent deals, fractional tie shares and a two-sided 95% Hoeffding sampling bound. Heads-up river results enumerate all 990 opponent combinations; other states use 12,000 Monte Carlo samples. Opponent count is explicit and manual (1–8). No range or wager amount is inferred from the screen. Dollar EV is `equity × (pot before call + new call) − new call`, with manual inputs and a one-pot, no-later-betting, no-rake showdown assumption.

Analysis runs in cancellable background tasks, separate from capture/recognition. Results and money inputs clear on unconfirmed, changed or stale cards, opponent-count changes and capture invalidation. Generation checks reject late results from old hands even when a worker ignores cancellation. Identical confirmed cards retain their analysis and entered amounts instead of restarting each frame. Manual amounts must still be updated when betting changes without a card change.

New tests cover exact counted combinations, known wins/losses, multiway ties, seeded reproducibility, Monte Carlo agreement within its bound, invalid/duplicate inputs, cancellation, EV arithmetic and threshold/range propagation. Model tests cover automatic recognition-to-analysis wiring, amount resets, invalid dollar inputs, late results after a new hand and clearing after folds. A synthetic offscreen NSHostingView render was inspected to verify the dashboard layout; no live poker display was captured for UI verification.

The v0.5.0 optimized run scheduled 45 cases: 43 passed, two optional original full-screenshot cases skipped, zero failures (about 4.16 seconds). The new flop screenshot and both packaged crops were tested. Live capture with the new panel and manual amount editing still require user verification.

## Second screenshot: reproducible suit error

The reattached 6:42:23 PM file became accessible and was copied into private local work files for replay. The unchanged v0.4.4 reader accepted A-clubs/J-hearts but mislabeled the board's 4-spades as 4-clubs (suit score about 0.8945, margin about 0.0392, above its acceptance thresholds). This is a confirmed wrong accepted suit. That static replay did not reproduce the earlier blank display, so the suit fix is not claimed as a demonstrated diagnosis of every missing-hand observation.

Version 0.4.5 adds normalized silhouettes for the supplied artwork's spade, club and heart to the existing font-derived shape library, and allows one-pixel alignment when comparing suits. Reference data contains only generic suit shapes, with no card rank, table image or account data. Acceptance scores/margins are unchanged. The native screenshot and nine resized/shifted variants now produce A-clubs/J-hearts and exactly 4-spades/10-clubs/J-clubs. The packaged crop verifies those five cards and normal two-frame confirmation/clearing independently of the private full screenshot.

Diagnostics now record each glyph-read attempt's normalized candidate rectangle, crop method, numeric scores/margins and rejected stage. They do not record predicted ranks/suits, images, URLs or account data. This avoids relying on aggregate best scores to diagnose one failing card.

The v0.4.5 optimized result was 35 cases scheduled, 33 passed, 2 optional old full-screenshot replays skipped, zero failures (about 3.37 seconds). The old 6:18 full file is no longer available; its packaged Q-clubs/5-clubs crop still passes at four render scales. The new full screenshot is supplied by CARD_READER_FLOP_FIXTURE. Standard rank/suit fixtures, all 52 generated cards, 20 successive hands with folds, stale clearing, hints, exclusions and logging still pass.

## Follow-up recognition evidence

The subsequent v0.4.4 log contains 125 analyzed frames without a capture error, with at most one accepted full-size hole-card face at a time. No pair was confirmed and the position anchor never activated. The repeated 6:18 Q-clubs/5-clubs screenshot still passes, including a new regression that resizes the complete image to 3840×2160, 2560×1440 and 1920×1080 with 0, 1 and 7 pixel offsets. This does not reproduce the current missing-card report. No new recognition fix or version bump is claimed from that replay; a fresh image of the failing observation is needed to identify its cause.

## Continuous reading across hands

The local v0.4.3 metadata confirms that scanning continued after the first confirmed hand: 166 frames were delivered and analyzed before an explicit Stop. The later observations had zero to three accepted faces and no supported pair. There is no capture error or automatic stop at the fold. The log contains no card images/identities, so it does not establish exactly which glyph or geometry caused the next hand to be missed.

Version 0.4.4 retains the confirmed hole/board positions as in-memory search hints across folds, empty frames, stale readings and transient analysis/content failures. The detector attempts those regions on every frame while also continuing full-screen proposals. Every card value must be recognized from the new frame; the hints contain only rectangles. A confirmed seat also anchors grouping, so unrelated header/sidebar pairs do not displace the current seat. Nearby moved/resized pairs can be reacquired after normal confirmation. Large table moves may require a fresh Start to establish a new seat.

Missing, partial, duplicate, ambiguous and stale readings still clear the displayed hand immediately. They do not stop capture. Stop, new monitor selection, sleep or sharing ending clear the layout. Capture permission is never bypassed, and no separate screenshot polling is reintroduced. Log fields now include hint counts, accepted-face rectangles and layout-lock/retention state, without card values or images.

## Recognition repair from user-supplied evidence

The user-supplied v0.4.2 log shows 82 received frames and completed scans at 3840×2160, no excluded area and no accepted faces. Capture is operating; candidates are rejected during rank/suit recognition. A user-supplied screenshot establishes the actual card layout: Q-clubs and 5-clubs with large centered club symbols, condensed ranks and lower edges covered by the white seat panel. There is no live board. The header repeats the hole cards and the sidebar shows a previous hand.

The old narrow rank crop could clip the queen, and the left-third suit crop clipped the club symbol. White-component refinement could merge adjacent faces with the seat panel. Version 0.4.3 uses full-width glyph searches, separates joined faces by their top caps, prevents refinement from widening into the neighbouring card and adds condensed-font and small glyph-alignment/width tolerances. Rank/suit acceptance thresholds remain unchanged. Faces smaller than 60% of the largest recognized face height are excluded before duplicate checks and grouping, preventing thumbnail/history contamination in this scene.

Regression tests replay the complete supplied screenshot from its external path and a card-only crop at several scales. The full screenshot and balances are not copied into the project or app; only the card-only crop is a test resource. Test resources are not included in the shipped app. Runtime logging remains metadata-only and no image export feature was added.

## Permission-loop diagnosis and change

Local metadata-only v0.4.1 logs from six launches were examined. Every attempted capture reached `capture_started`, then the immediate separate `SCScreenshotManager` call failed with domain `com.apple.ScreenCaptureKit.SCStreamErrorDomain`, code `-3801`, and the message "The user declined TCCs for application, window, display capture". The app then stopped its otherwise-started stream before delivering any frames. The global permission-preflight flag was false. This establishes the screenshot fallback as the failing path in those sessions.

Version 0.4.2 removes the screenshot API and polling timer. Capture now uses only the picker-authorized SCStream. A latest-frame cache handles explicit `.idle` callbacks (documented by the installed Apple SDK as no display change), while blank, suspended, stopped, started, unknown, invalid and unreadable complete events clear the cache. Silence does not replay a cached image; the existing stale-reading watchdog remains in force. Metadata logs distinguish `stream` and `stream_idle`, and record `capture_mode: picker_stream_only`.

The existing bundle is ad-hoc signed, with a designated requirement tied to its code hash; no valid certificate signing identities are installed. That can invalidate privacy authorization across rebuilds, but is separate from the observed screenshot failure. No privacy database was edited and no permissions were reset.

## Troubleshooting changes

- Added private, metadata-only JSONL logs and a Show logs control. Recorded events include launch/version/OS, picker selection, global capture-permission preflight, configured dimensions, stream status codes, capture errors, delivered frames, excluded coverage, pending-frame replacement, detection timing/frame age, candidate counts, recognition-stage rejection counts, aggregate shape-match scores and final reader status.
- Logs do not contain screenshots, card values, OCR text, URLs or window titles. Each launch is bounded to three approximately 5 MB files. Files use owner-only permissions. Tests verify structured decoding, rotation and that fake hand values do not enter the log.
- Fixed a possible all-cards-excluded failure: reader-window exclusions now use front-to-back on-screen geometry and subtract covering opaque normal windows. A reader behind full-screen Safari or on another Space does not exclude the entire playing area. Transparent system sharing overlays are not treated as opaque covering windows. Only metadata is examined; no website pixels are inspected by these geometry checks.
- The status now distinguishes no incoming frames, no card-shaped areas, reader overlap, and unrecognized rank/suit shapes. Footer counters separate received frames, completed scans, attempted candidates and recognized faces.
- The build script stages and signs the new bundle before moving the old bundle to the build cache. An active old process is not overwritten in place. Reopening the app is required to load the new executable and logging UI.

## Checks

- The current suite contains 47 cases: three card-ranking cases, six equity/EV cases, twelve automatic-recognition/grouping cases, seven screenshot cases, five app-model cases, four analysis-model cases, five exclusion/diagnostic-stage cases, two logging cases and three stream-cache cases. The latest result is 45 passed and two optional original full-image cases skipped. Cases cover 20 consecutive hands separated by folds/empty frames, recovery after stale input, retained seat geometry with distracting duplicate sidebar pairs, reading changed cards from hint regions, blank-frame rejection and reader-window exclusions on hinted regions, plus the equity/EV cases above.
- The earlier v0.4.4 full screenshot replay selected Q-clubs/5-clubs, rejected the sidebar as a live board, confirmed after two observations and cleared when cards disappeared. Its packaged crop still passes at four render scales (0.5, 0.75, 1.0 and 1.25 in the test canvas). The new screenshot/crop checks are described above. Fixture timings are not measured live capture-to-dashboard latency guarantees.
- Regression checks verify that full Safari occlusion leaves no reader exclusion, partial occlusion excludes only the visible remainder, off-Space reader windows contribute nothing, transparent overlays do not invent occlusion, and repeated previous-frame rectangles do not inflate coverage.
- The detector still passes all 52 rank/suit combinations on generated conventional card faces. A five-card scene and moved/resized pairs are recognized without supplied coordinates. Empty/ambiguous/duplicate/old observations remain suppressed.
- The Apple silicon release builds; Info.plist and local ad-hoc signature verify. Logging UI and capture instrumentation compile. The active real-site session is not opened or inspected to test those controls in this run. The package includes the permission-loop fix from v0.4.2.

## Limits

The v0.4.1 metadata establishes the permission-loop failure described above; the subsequent supplied v0.4.2 log confirms continuous screen delivery and scanning after the fix. The earlier occlusion defect was a code-level finding and tested fix, not the cause shown by those logs.

The supplied screenshot cases validate those specific pictured hands and boards, including all four suit artworks. Other actual-site ranks, animations and layouts are unverified; no 99% recognition claim is established. The new app's entire live capture-to-dashboard flow is not exercised through tools. Generated fixtures and screenshot replay establish tested cases rather than general real-table accuracy. The detector assumes light faces at comparable scales and a single two-card row below a possible board; unusual fonts, overlapping/tilted/very small cards and multiple tables can be rejected. Miniature filtering is relative to visible face sizes and does not semantically identify a live table.

Only screenshots explicitly supplied by the user and generated fixtures are inspected. No live Bovada browser, monitor or reader capture is opened through tools. The Computer Use restriction remains respected. No wagering is used for testing.
