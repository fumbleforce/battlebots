# A — Quick Play service synchronization

Owner A; branch `codex/a-quick-play-service-sync`, base `6c1eb0e`.
Scope: online menu status presentation/tests and existing Fly deployment.
The live health endpoint advertises catalogue hash `703edd52...`, while current
main uses revision 6, hash `63b65500...`. The compatibility gate correctly rejects
the request before queueing. Reappearing actions put the error below the fold.

Keep compatibility validation intact; publish a matching server to the existing
single Machine and verify external private/queued duels. Move online status above
actions and focus failure text so errors remain readable at enlarged text sizes.
No B bot/combat/controls or shared wire changes. Validation pending.
