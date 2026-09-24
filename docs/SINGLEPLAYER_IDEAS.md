# Single-player story mode — ideas

**Status:** brainstorm only, 24 September 2026. Nothing here is a game rule or
planned work. `GAME_SPEC.md` still excludes campaign content from the first
release and puts a complete 1v1 game first. Adopting any direction below
requires a spec revision and a tracking issue first.

Constraint from the user: story mode must not be arena-based.

Every direction builds on existing systems: three distinct chassis (Sawblade,
the six-legged Scorpion, the tracked Atlas), turret weapons, match pickups, the
credits wallet, Nitro/jump, the practice NPC machines and the Woodland
environment work.

## 1. Scrapyard Expedition (open-zone salvage campaign)

You're a scavenger bot operator in a ruined industrial valley. You drive
through 3–5 connected open zones, such as a woodland, a quarry, a flooded
foundry and a rail yard. You fight roaming wild bots, rip parts off wrecks and
bring salvage back to a home-base garage.

- **Builds on:** pickups (parts become salvage you keep), the credits wallet,
  Woodland environment work, practice NPCs becoming roaming AI.
- **Hook:** the parts you find are the progression. Each zone favours a
  different chassis: tracks for mud, legs for rubble, wheels for roads.
- **Cost/risk:** high. Needs big streamed levels, roaming AI and persistent
  inventory. It's also the easiest direction to let grow out of control.

## 2. Convoy / Escort Road Campaign (linear missions)

A string of authored levels along a route. You escort a slow hauler, break
through checkpoints, chase bandit bots down canyons and defend the convoy at
night stops. It plays like a vehicle action campaign, with a short objective
and a set-piece in each level.

- **Builds on:** driving feel, Nitro/jump, turret weapons (shooting while
  driving), AI bots.
- **Hook:** driving is the main verb and fighting sits on top of it. There's
  lots of room for authored set-pieces like collapsing bridges, jump gaps and
  ambushes.
- **Cost/risk:** medium. Levels are linear, so content scales one level at a
  time. This is the closest to a classic single-player campaign.

## 3. Rogue Machine (roguelite run across a map)

It works like FTL or Slay the Spire with bots. You pick a node on a branching
map. Nodes include fights in small outdoor pockets, salvage events, a workshop,
a hazard run or a boss machine. Your bot's damage carries between nodes, and
pickups become the upgrades you choose from.

- **Builds on:** damage that carries between rounds (already a rule), pickups,
  Customize catalogue slots, credits.
- **Hook:** a small set of reusable encounter pockets gives replayable content.
  A run takes 20–40 minutes, and repair versus upgrade is a real tradeoff.
- **Cost/risk:** lowest content cost for the most replay. The narrative stays
  thin, delivered through events and boss intros.

## 4. The Last Workshop (hub-and-story RPG-lite)

A character-driven story told from a garage town hub. You run a small workshop
and take jobs from NPCs, such as clearing a mine, recovering a stolen prototype
or testing a rival's bot. Rival builders recur as bosses with their own
personalities and signature machines, such as a Scorpion-only zealot.

- **Builds on:** the garage/Customize UI, chassis identity, the authored NPC
  machines.
- **Hook:** this has the strongest emotional story. Rivals give chassis and
  weapons a narrative identity, and unlocks come through story beats.
- **Cost/risk:** medium-high. Needs dialogue, a quest system, a hub scene and
  writing. It's also the most likely to feel thin if under-produced.

## 5. Environmental Puzzle-Brawler (physics traversal + combat)

You play one scrappy bot escaping a factory complex, level by level, using the
physics the game already has. You lift and flip obstacles, use the hammer to
break walls, cross gaps with jump and Nitro, push crates onto pressure plates
and fight security bots with the environment (crushers, conveyors, pits).
Think *Portal*-style rooms with heavy machinery.

- **Builds on:** the lifter/flipper/hammer, Jolt physics, self-righting and
  recovery, the jump charge.
- **Hook:** this makes the weapons into tools as well as damage dealers. Of the
  five, it shows off the "heavy, mechanically understandable" pillar best.
- **Cost/risk:** medium. Levels are compact and authored. It needs puzzle
  design skill and physics that stay reliable enough for puzzles.

## Recommendation

Start with **3 (Rogue Machine)** and give it an authored spine taken from
**4**: a few named rival bosses with short intros, plus a hub garage between
runs. It reuses the most existing systems (carried-over damage, pickups,
catalogue, credits, NPC machines). Content scales through reusable encounter
pockets rather than bespoke levels. It also plays fully offline, so it doesn't
touch the multiplayer wire contract.

## Phased plan (recommended direction)

1. **Spec and scope (no code):** open a story-mode issue and post a CLAIM on
   #2. Add a spec revision to `GAME_SPEC.md` that lifts the "no campaign"
   exclusion, and confirm with the user that it can run alongside the
   remaining 1v1 work.
2. **Single-player foundation:** a local, offline match authority that reuses
   the server-authoritative sim. Add a `data/story/*.json` config (nodes,
   encounters, rewards, boss definitions) behind a typed loader, with no bare
   tuning numbers in logic.
3. **AI upgrade:** turn the practice NPCs into a real combat AI (approach,
   flank, use weapon, self-right), with difficulty tiers set in config. The
   whole mode depends on this, so it's the biggest single risk and should come
   first.
4. **Encounter pockets:** 4–6 small outdoor combat spaces built from the
   Woodland/arena environment kit, each with a hazard twist.
5. **Run layer:** the branching map UI, damage carried between nodes,
   pickup-based rewards, a workshop node for repair versus upgrade, and a
   save/resume.
6. **Story spine:** a hub garage, 3 rival bosses with intro cards and
   signature builds, and meta-unlocks that feed the credits wallet.
7. **Vertical slice test:** one full 20-minute run, with the checks run
   headless, before adding more content.
