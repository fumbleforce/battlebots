# Visible online actions and enlarged menu text (#7)

The old online page stacked Quick Play, private creation and joining inside a
scroll container. Create/Join could be below the viewport even at 100% text.
Existing bounds checks exempted scroll content, so those checks passed. Enlarged
host-mode cards also switched to two 660-pixel rows, hiding modes and rules.

The online screen now presents three parallel choices below a compact status
row. Quick Play retains the primary amber action; private creation and joining
keep the quieter existing buttons. The friend-code input has its own row. Idle,
errors and active memberships preserve their existing service behavior, keyboard
focus, retry and cancellation. No smaller font override substitutes for the
requested text scale.

Host mode selection uses four compact cards in two rows, with the same mode
names, descriptions, player counts, rules and selected-state badge. Mode color
and large 1V1/2V2/5V5/FFA marks remain useful distinctions. The selected rules and
Continue action stay visible together. The original Barlow/Barlow Condensed,
steel panels, amber actions and hazard stripe are retained throughout.

At 720p/150%, duel results needed scrolling for the score table and five-round
history. Removing repeated headings and tightening spacing frees room for the
full history, credits, both score rows and rematch/leave controls. Text scale,
server-published results and rematch semantics are unchanged. Larger multiplayer
score tables keep their existing scroll fallback; this acceptance is for 1v1.

## Validation

Pinned Godot 4.7.2. The online regression covers 48 combinations: 720p, 1080p,
2560×1080; 100%/150% text; idle, failed, maximum-length service error, unavailable,
requesting, waiting, starting and canceling. It checks all visible labels/actions
at once, full button text, absence of required scrolling, and Tab reachability.
It is registered in `check-presentation.ps1`.

The broader screen test no longer exempts scroll descendants. Main, online,
lobby, mode/arena selection and loading fit at 100/125/150% text and the above
sizes plus 4K. Mode labels stay within their own cards and color panels. All
four selections retain visible rules and Continue, including FFA capacity.

The results test covers a five-round duel, credited rewards, maximum accepted
integer statistics/player IDs, pending rematch and enlarged text. Both overview
and scores must fit without scrolling at 720p, 1080p, ultrawide and 4K. Existing
reconnect and in-game menu checks remain in that suite.

Real HTTP fixture plus independent ENet admission/menu tests pass. The main-menu
flow test now uses the actual logical canvas/window coordinate transform,
canonical selected build, and the existing Practice arena-choice step; its old
expectations predated these implemented routes. Baseline and focused text,
results-state and navigation checks pass. This is not live-service or human
presentation acceptance.

Native 720p/150% Forward+ captures on RTX 3080:
[online](evidence/menu-flow-fit/online.png),
[error/retry](evidence/menu-flow-fit/error.png),
[host modes](evidence/menu-flow-fit/modes.png),
[results](evidence/menu-flow-fit/results.png),
[score details](evidence/menu-flow-fit/scores.png).

```sh
godot --headless --path battlebots --script res://tests/presentation/online_menu_fit_test.gd
godot --headless --path battlebots --script res://tests/presentation/menu_text_screens_test.gd
godot --headless --path battlebots --script res://tests/presentation/match_menu_text_test.gd
godot --headless --path battlebots --max-fps 60 --script res://tests/presentation/online_menu_test.gd
godot --headless --path battlebots --max-fps 60 --script res://tests/presentation/menu_flow_test.gd
```

`online_menu_fit_test.gd -- --capture` runs the native 720p/150% idle/error/waiting
subset and writes to ignored `exports/menu-flow-review/`. The screen/results
tests also support `--capture`; results captures use `TEMP` as their directory.
No gameplay, wire or catalogue change. Matching CI/release and human full-flow
presentation review remain tracked on [#7](https://github.com/fumbleforce/battlebots/issues/7).
