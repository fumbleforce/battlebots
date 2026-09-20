# A — Quick Play service synchronization

Owner A; branch `codex/a-quick-play-service-sync`, base `6c1eb0e`.
Scope: online menu status presentation/tests and existing Fly deployment.
The live health endpoint advertises catalogue hash `703edd52...`, while current
main uses revision 6, hash `63b65500...`. The compatibility gate correctly rejects
the request before queueing. Reappearing actions put the error below the fold.

Keep compatibility validation intact; publish a matching server to the existing
single Machine and verify external private/queued duels. Move online status above
actions and focus failure text so errors remain readable at enlarged text sizes.
No B bot/combat/controls or shared wire changes.

## Validation and deployment

- Online panel checks pass, including visible compatibility errors at 720p/1080p
  and 100/150% text. Actual HTTP/ENet online menu, public service client and
  two-player Quick Play client checks pass. The existing two-ObjectDB shutdown
  warning remains in the online-menu fixture.
- Godot 4.7.2 baseline and all 25 matchmaker tests pass.
- Local private/queued duel checks pass through two rounds, results and active
  rematch (`battlebots-hosted-GzJVLy`). Forfeit-driven lifecycle checks, not human
  combat acceptance.
- Prepared clean source `ce3d2f6` and updated the existing Stockholm Machine
  `287e605ad7d578`; no additional resources. Image digest
  `sha256:89584e87ec307388d69dd2ec0959e0c070836e4fea4c9e2bef1a4500d6c9bcf1`.
  Live health now matches revision 6 hash
  `63b655000dc8129c3cd52cb735ecfaec5cbc7cdb1513b43de024383e7473e8a5`.
  Build `mvp-ab-12` and protocol 4 are unchanged.

- External private and Quick Play duels pass through results and active rematch.
  See [redacted report](evidence/fly-duel-catalogue-6-2026-09-20.json).
  The actual Godot HTTPS PublicServiceClient also reaches Finding an opponent
  and cancels cleanly. Temporary evidence: battlebots-hosted-zr28cG.
- Human two-computer combat acceptance remains open; reconnect was not exercised
  by this duel-only check. No paths remain reserved after integration.

Deployment reminder: catalogue changes require preparing and deploying the matching
server before asking current-main players to test hosted play. Preserve the hash
check; updating only the health manifest would admit incompatible game workers.
