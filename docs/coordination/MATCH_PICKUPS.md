# Match item pickups and account credits

Issue: [#35](https://github.com/fumbleforce/battlebots/issues/35). Requested by the user (JosteinE) on
23 September 2026. Implemented by B session `b-pickups-claude-deskfraph-20260923`, with the user's
approval for the A areas it touches (world, session/network, HUD, results). Contract summary:
[CONTRACTS.md, "Match item pickups and credits"](../CONTRACTS.md).

## Rules (user decisions)

- **Kinds.** Parts from the Customize catalogue (every slot, including body and drive), the Nitro and
  charged-jump perks, and credits. Legacy bodies (`compact`, `wide`) and the "no perk" entries never drop.
- **Parts** replace the picker's part in that slot. **Perks** are granted. Both last **until the match
  ends**: a new round keeps them, a rematch or new match starts from each player's own loadout. Nothing
  unlocks for the account.
- **Not picked up** (the item stays in the world): the same part is already fitted, the perk is already
  equipped, or the result would be physically invalid (for example, wheels under a Scorpion).
- **Body pickups** bring the drive that body requires (Scorpion: walker, Atlas: tracks). They replace any
  utility the new body cannot carry (for example the socket-bound auxiliary minigun) with `recovery_assist`.
- **Budget.** Pickups are a bonus above the 120 kg / 100 power construction budget. Only the pickup path
  is exempt; lobby builds are validated strictly as before.
- **Credits** add to the picker's match tally. After the match, the server computes each participant's
  reward: participation 50, victory 150, 50 per elimination, 20 per assist, 1 per 10 effective damage,
  plus pickup credits. Clients pay it into the account wallet once per match id. The wallet will later
  unlock Customize parts; that is out of scope here.

## Implementation choices (open to revision)

- Five points: the centre plus four diagonals at half the arena radius. These stay off the Z-axis team
  spawn lanes and scale with `ArenaBounds`, so new arenas (for example Woodland, #34) get points
  automatically. Moon and Woodland points sit on their terrain. A point that overlaps any bot's spawn is
  not stocked (in Practice the player starts beside the centre), so nobody collects on the first frame.
- Contents are random. There is a 30% chance of credits (25/50/100); otherwise a uniformly random
  catalogue part or perk. A collected point restocks after 20 s, and every point restocks at a new round.
- Collection is a vertical column. Horizontally, the hull footprint must overlap the point (radius: half
  the longest hull side + 0.5 m). Vertically, some part of the hull must lie between 1.5 m below the point
  and the top of the 9 m light beam (`MatchPickups.REACH_DOWN`/`REACH_UP`; the beam is drawn from the same
  constant). Jumping and launched bots therefore collect. Eliminated bots and practice NPCs never collect.
- **Swap state.** The bot keeps its pose, motion, owner, input sequence, score counters, attacker
  credit, timers, and its core, plate and battery fractions. The component in the *changed* slot arrives
  intact: a new weapon, new drive pods or new plates. A taller body is lifted clear of the floor.
- Practice shows pickups and the feed says rewards are not banked. Practice never pays credits.

## Presentation

- `PickupVisuals` draws a floor ring, a light column and a floating, rotating item with a Label3D naming
  the contents. Colours: amber part, cyan perk, green credits. Parts show their real art where it exists
  (`PickupModels`, fitted to 3.2 m): bodies as the whole painted Sawblade/Scorpion/Atlas, weapons,
  tracks, wheels and walker legs as that module cut from an assembled Sawblade, and the auxiliary gun as
  the minigun. Armour grades and other utilities have no dedicated mesh and keep a crate token; perks
  keep a gem and credits a coin. Scorpion legs hang unplanted on the marker. Close-ups:
  [05-model-pickups.jpg](evidence/match-pickups-2026-09-23/05-model-pickups.jpg).
- `PickupFeed` (top-left of the combat HUD canvas) is deliberately small: a one-line `CR +N` chip for this
  match's credits, and up to three one-line toasts (`PART …`, `PERK …`, `+N CREDITS`) for the local
  player's pickups. The whole feed is about 94 px tall at 720p. It follows HUD text scale and stacks below
  the enlarged practice panel.
- `PickupNotice` shows centred amber text on a dark backing, just above the audio-caption band, when the
  server refuses a pickup the local player touched: `NITRO BOOST ALREADY EQUIPPED`, `HAMMER ALREADY
  FITTED` or `<PART> DOESN'T FIT YOUR BUILD`. It fades after 2.5 s. The server reports a refusal once
  per contact (again after the bot drives off and back, or the item respawns with new contents), and
  only to that bot's owner.
- **Camera.** A part pickup rebuilds the local bot node. `menu_game`/`lobby_game` re-bind the orbit
  camera, which recentres it, only when the match or entity changes, so a pickup keeps the player's orbit.
- Results overview shows `+N CREDITS EARNED · performance · pickups`. The menu header shows the
  wallet balance (`%ScrapAmount`, `%ProfileMeta`) in place of the old placeholder scrap readout.

## Validation

- `tests/simulation/match_pickups_test.gd` (`MATCH PICKUPS PASS`): rules, reward, and live swaps on real
  Jolt bodies in Foundry and Moon.
- `tests/network/pickup_session.tscn` (`PICKUP SESSION PASS`, real-time ENet): two clients, replicated
  weapon and body swap, credits, reconnect baseline, results reward.
- `tests/presentation/pickup_presentation_test.gd` (`PICKUP PRESENTATION PASS`): wallet persistence,
  single payment and tamper handling, feed, results line, markers.
- Native review, `tools/capture_pickup_review.gd`, run in real Practice at 1600×900 on Foundry: stocked
  markers, a live Atlas body swap with the feed, and perk/credit toasts. Captures are in
  [evidence/match-pickups-2026-09-23](evidence/match-pickups-2026-09-23/).

## Limits and follow-ups

- The wallet is a local file (`user://wallet.cfg`). It is not tamper-proof and not shared between
  machines. Server-held identity (#16) must own the balance before credits gate anything shared.
- Spending credits and gating Customize parts are not implemented.
- A live body swap rebuilds visuals mid-fight; native frame-time impact is not yet measured.
- Protocol 7 / build `mvp-ab-16` needs a matching hosted server release (A) before hosted play is ready.
