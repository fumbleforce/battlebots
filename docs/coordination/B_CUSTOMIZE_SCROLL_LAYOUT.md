# B Customize scrolling choice list — 23 September 2026

Owner: B. Issue: [#33](https://github.com/fumbleforce/battlebots/issues/33).
Branch: `codex/b-customize-scroll-layout`, based on `origin/main` at `8c386f6`.

## Decision

On 23 September 2026 the user explicitly asked for a scrolling box in place of
the PREVIOUS / NEXT paging in Customize's right panel. This supersedes the
earlier no-scroll direction **for the Customize choice list only**:
- The left part-slot list keeps its paging.
- Other screens are unchanged.
- Tests now allow exactly one ScrollContainer, `Customize._choice_scroll`.

## Behavior

- **Description placement.** The selected choice's name and description
  (including invalid-build reasons and save messages) sit under the 3D
  preview. The block has a fixed minimum height, so the preview does not
  resize when the text changes. Show Stats still swaps the model for the
  comparison panel.
- **Scrolling choice list.** Choices live in a vertical ScrollContainer.
  Mouse wheel and scrollbar work, focused tiles are scrolled into view, and the
  scroll position is kept while equipping within one category. A right
  gutter keeps the scrollbar off the tiles. The ARMOR section headings are
  unchanged.
- **Compact tiles.**
  - Each tile is one 44 px row (scaled with text) showing only the name.
  - The status label appears only when relevant (EQUIPPED), since every listed
    choice is usable.
  - Long names truncate with an ellipsis. The full name is in the tooltip and,
    once selected, in the description.
  - Paint tiles keep a 6 px colour strip.

About 20 options are visible at 1920×1080, up from about 6.

## Compatibility and validation

Presentation only. There is no catalogue, save, protocol or hosted change.

Pinned Godot 4.7.2 checks updated for scrolling:
- `customize_text_test`: only the choice list may scroll, and focus scrolls a
  tile into view.
- `garage_pagination_test`: the list stays inside the body, the scrollbar
  does not cover tiles, focus reveals the last choice, and a taller aspect
  needs no scroll.
- `garage_test_drive_entry_test`: only the choice list may scroll.

Also passing: garage history/profile/compatible parts/menu text screens,
customization screens, unlocked options, repair, recovery, catalogue text,
comparison panel, Scorpion garage, preview, sawblade and
`tools/check-baseline.ps1`. Native captures were reviewed at 1920×1080 and
1280×720, at 100% and 150% text.

Remaining: human playtest.
