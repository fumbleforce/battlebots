# Battle Bots menus: Godot 4 UI kit

These are the 8 menu screens from the design canvas, rebuilt as native Godot Control scenes. They were built and tested on **Godot 4.7.1** using both GL Compatibility and headless mode. The UI is laid out for a **1920×1080** viewport. Each element is 1.2× its size in the 1600×900 design.

The scenes are ordinary `.tscn` files built from Containers and a single shared Theme, so you can edit them directly in the editor. Every screen already works: navigation, selection, the buy and equip flow, and the lobby countdown into the loading screen.

## Adding the kit to your project

1. Copy `ui/menus/` into your project root. The scenes and scripts refer to `res://ui/menus/...`. If you move the folder, move it inside the editor so Godot rewrites those paths.
2. **Project Settings → Autoload**. Add both of these, using exactly these names:
   - `MenuRouter` → `res://ui/menus/scripts/menu_router.gd`
   - `PlayerProfile` → `res://ui/menus/scripts/player_profile.gd`
3. **Display → Window**. Set the viewport to 1920×1080, stretch mode to `canvas_items` and aspect to `expand`. If your project uses a different base resolution, scale `default_font_size`, the font sizes and the paddings in the theme accordingly.
4. **Input Map**. You can copy the `[input]` block from the sample `project.godot`:
   - Add W/A/S/D to `ui_up`, `ui_left`, `ui_down` and `ui_right`.
   - Add a new action `menu_tab_prev` bound to Q and LB, and `menu_tab_next` bound to E and RB.
5. Set `res://ui/menus/screens/main_menu.tscn` as your main scene, or call `MenuRouter.goto("main")`.

## Starting a match from the menus

The loading screen hands over to your game in one of two ways. Use either one:

```gdscript
# Option A: the loading screen loads your arena on a background thread, then switches to it
MenuRouter.match_scene_path = "res://game/arena.tscn"

# Option B: take over from the loading screen yourself
MenuRouter.match_requested.connect(func(setup):  # {"mode": "team", "bot": 0, "arena": 0}
	get_tree().change_scene_to_file("res://game/arena.tscn"))
```

If you set up neither, the loading screen prints a warning and returns to the main menu.

## Folder layout

| Path | What it is |
|---|---|
| `screens/` | `main_menu`, `mode_select`, `garage`, `arena_select`, `lobby`, `loading`, `customize` |
| `components/` | Pieces the screens create repeatedly at runtime: mode card, bot row/chip, arena tile, stat bar, category row, item tile, deal row, player slot |
| `theme/menu_theme.tres` | All colours, fonts and styleboxes, stored as **type variations** |
| `scripts/menu_router.gd` | Screen navigation, the Back history and `match_setup` |
| `scripts/player_profile.gd` | Placeholder save state (scrap, level, owned and equipped items, upgrade levels). Replace it with your own save system. |
| `scripts/menu_data.gd` | Every name, price, stat and description. **All of these are placeholders.** |
| `scripts/menu_screen.gd` | Base class for the screens. Handles Esc/Back, the step tracker and the scrap/profile readouts in the header. |
| `art/`, `icons/`, `fonts/` | Images cropped from the in-game screenshot, a hazard-stripe tile, SVG icons, and the Barlow / Barlow Condensed fonts (OFL licence) |

The screen scripts look up nodes by unique name (`%Name`). You can rearrange the layout freely as long as the unique names stay the same.

## Changing the look

Almost everything visual lives in `theme/menu_theme.tres`, grouped by type variation:

- **Buttons:** `PrimaryButton` (amber CTA with a bevelled corner), `MenuItem`, `MenuItemPrimary`, `GhostButton`, `OverlayButton`, `IconButton`, `TextLink`, `Tab`, `Card`, `ListRow`, `Tile`, `CategoryRow`, `SlotButton`
- **Labels:** `Heading`, `HeadingItalic`, `HeadingWide`, `Subheading`, `Eyebrow`, `EyebrowAmber`, `Body`, `Muted`, `Strong`, `Positive`, `Amount`, `KeyLabel`, `Tagline`, `OnAmber`
- **Panels:** `PanelBox`, `PanelFlush`, `PanelGlass`, `PanelSoft`, `PanelDark`, `PanelOutline`, `HeaderBar`, `FooterBar`, `KeyCap`, `Chip`, `TagAmber`, `Step*`, `Badge*`, `Pip`/`PipOn`, `Team*`, `Slot`/`SlotYou`, `Framed`, `Caption`, `BottomBar`

Keyboard and gamepad focus shows as a 3 px amber outline, set by the `focus` stylebox.

## Placeholders and gaps

- **Bot previews are flat images** (`%BotImage` in the Garage and Customize screens). Replace each one with a `SubViewportContainer` showing your 3D bot. The rotate button is already in place for that.
- **Not built yet:** the Career and Settings screens, invites, the custom lobby and the bot builder. Their buttons currently call `push_warning("TODO…")`.
- **The lobby is faked.** Queue time and opponents are simulated, so connect it to your matchmaker.
- **Visual differences from the design:**
  - The bevelled corners on the amber buttons are an approximation: `corner_detail = 1` on the bottom-right radius.
  - The dashed "Build new bot" border is drawn as a solid line.
- **"BATTLE BOTS" is close to the BattleBots TV trademark.** Rename it before you ship. The wordmark is the `Wordmark` label in `main_menu.tscn`.

`design_reference/` (outside `ui/`, and marked `.gdignore` so Godot doesn't import it) holds the original mockups at 1600×900. Use them as a pixel reference.
