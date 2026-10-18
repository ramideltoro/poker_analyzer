# Live Card Reader · 0.4.5

Continuously scans a monitor you select and automatically looks for visible playing-card faces. It displays the detected two-card hand, community cards, and the combination in those cards. There is one screen with Start/Stop and Show logs. No card-area marking, Safari-window selection, stored layouts, coaching, simulations or hand history.

## Start

For a fresh checkout, run `bash scripts/build-app.sh` first. The generated app is in `dist/Live Card Reader.app`; build outputs are excluded from Git. This project requires an Apple silicon Mac with macOS 15.2+ and Xcode installed.

1. Open `dist/Live Card Reader.app` on this Apple silicon Mac (macOS 15.2+).
2. Click **Start**, then choose the monitor containing your poker table in Apple's screen-sharing picker. Complete any macOS screen-recording permission prompt.
3. Keep one table visible with the cards uncovered. Put this app beside the table or on another monitor; it cannot see cards hidden behind another window.
4. Leave it running. **Stop** ends capture and clears the hand.

Start once per sharing session. Folding, the board clearing and a new deal do not require Stop/Start. After two matching observations, the reader remembers the card positions and checks those areas on every subsequent frame, alongside its full-screen search. It retains those positions between hands and through stale/failed readings, but reads card values anew. Missing or uncertain cards clear the display while scanning continues. Explicit Stop, a new monitor-selection session, sleep or macOS ending screen sharing clears the remembered layout; capture requires a new Start after sharing ends.

The selected monitor is streamed continuously, targeting two frames per second. This version uses only the stream authorized through Apple's sharing picker; it makes no separate screenshot requests. An explicit stream idle event confirms unchanged content and allows the latest frame to be scanned again. Blank, suspended, stopped, invalid or unreadable frames discard the cached image; silence does not renew old readings. Safari tab titles and window resizing no longer stop reading, and no manual layout calibration is required. A user-initiated activity keeps background processing active while allowing normal system sleep. Sleep or capture revocation stops reading; click Start to resume afterward.

The footer shows received frames, completed scans, attempted candidates and recognized faces. The status distinguishes a received screen with no card-shaped areas, an excluded screen area, and ranks/suits that do not match. The detector supports conventional light faces and large centered suits. Version 0.4.3 correctly reconstructs Q-clubs and 5-clubs with no live board from the user-supplied Bovada screenshot, ignoring the miniature preview and history faces. It also handles the lower card edges merging into the white seat panel in that image. Other ranks, suits and table layouts on the actual site still need validation; one screenshot does not establish general recognition accuracy. Very small, tilted, unfamiliar or obscured glyphs may be rejected.

## Troubleshoot 0 faces

Version 0.4.5 adds references for the supplied card artwork's spade, club and heart silhouettes, with small pixel-alignment tolerance. This corrects a confirmed 4-spades → 4-clubs misreading. The supplied A-clubs/J-hearts hand and 4-spades/10-clubs/J-clubs flop now pass screenshot replay at the original resolution and at 3840×2160, 2560×1440 and 1920×1080 with small pixel offsets. The acceptance thresholds are unchanged. These are image-replay checks; other live hands and actual-site diamond artwork remain unverified.

Quit and reopen the app after updating; check **v0.4.5** at the bottom. Start screen sharing, leave the table visible for 10–15 seconds, then click **Show logs**. Finder selects this launch's `.jsonl` file. Attach that file for diagnosis. It is in `~/Library/Application Support/LiveCardReader/Logs/`.

Logs contain app/build/OS version, picker and permission-preflight events, capture errors, stream status codes, input dimensions, hint counts and accepted-face rectangles, received-frame counts, scan duration and frame age, exclusion coverage, candidate counts, rank/suit match scores and rejection categories. Per-candidate details record the rectangle, crop method, numeric match scores/margins and rejection stage, without predicted ranks or suits. The global permission preflight is diagnostic only; picker-authorized capture can work even when the global permission flag is false. Rejection counts describe attempts, which can include multiple proposals for the same shape.

## Repeated screen-recording permission dialog

The v0.4.1 logs showed successful `capture_started` events followed immediately by `snapshot_error` code `-3801` (TCC permission denied). The extra screenshot request then stopped the approved stream. Version 0.4.2 removed that request, and the supplied v0.4.2 log confirms 82 incoming frames and completed scans without that error. Quit the old app completely and open `dist/Live Card Reader.app`; verify **v0.4.5** before clicking Start. Selecting a monitor in Apple's sharing picker for each new session is expected.

This development build is ad-hoc signed. Rebuilding changes its code identity, so an existing System Settings permission may refer to an earlier build. If macOS still explicitly requests global screen-recording access, remove the old Live Card Reader entry in System Settings → Privacy & Security → Screen & System Audio Recording, add the exact current app from `dist`, enable it and quit/reopen the app. Do not reset permissions for unrelated apps. Apple's explanation of development signing and privacy authorization is at https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements.

Logs contain **no screenshots, card values, OCR text, window titles or URLs**. Each launch uses private-permission JSONL files; rollover is bounded to three files of about 5 MB each for that launch. If rollover occurred, include the matching `-part1` and `-part2` files. Prior launches are retained until you remove their diagnostic files.

## What identification means

The detector proposes card rectangles using Vision and bright connected regions, reads rank/suit glyph shapes, and groups nearby cards into rows. Joined white faces can be separated using their top caps; the full width below the rank is searched for a large suit. Condensed rank templates and small alignment/width tolerances handle font and resize differences without lowering the acceptance thresholds. Miniature faces are filtered relative to the largest recognized faces before grouping and duplicate checks.

It assumes the single isolated two-card row below a possible three-to-five-card board is your hand. It does not know your account or seat identity, or semantically identify the live table versus a historical image. With multiple comparable candidate pairs, comparable duplicate faces, ambiguous row layouts or uncertain glyph matches it shows no hand rather than selecting one. Keep one live table visible and avoid other large card images.

Cards must agree across successive scans before display. Changed, missing, ambiguous or stale readings clear the previous hand. The combination label uses only recognized cards; unread board cards can change the complete hand's category. Rank and suit similarity scores are geometric match scores, not calibrated probabilities of correctness.

The app ignores only the visible parts of its own windows and a still-open previous reader version, including their recently moved positions. Reader windows fully covered by Safari or located on another macOS Space no longer mask the playing surface. This fixes a possible cause of perpetual 0 faces. Its window still physically covers content behind it, so keep it away from the table's cards.

## Local processing

No accounts, cloud service, API keys, browser extension or network requests. Frames stay in memory: the latest stream image is cached for explicit idle events, alongside the processing frame and latest waiting frame. The cache is replaced on a new complete frame and discarded on interruption or stop; images are never saved to disk. Only the diagnostic metadata described above is saved. Old versions' local history/settings files are left untouched and are no longer opened.

## Build and test

```sh
bash scripts/build-app.sh
bash scripts/test.sh
```

The build is ad-hoc signed for local use, not notarized for public distribution. The scripts use the installed Xcode compiler/Command Line Tools SDK and Apple's XCTest runner. `VERIFICATION.md` describes test evidence and the remaining live-capture validation limits.
