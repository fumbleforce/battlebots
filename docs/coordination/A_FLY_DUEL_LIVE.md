# A — first live Fly 1v1 deployment

User approved deployment on 2026-09-20 in this conversation, including the
previously estimated roughly USD 14/month base plus usage/tax. That approval
supersedes the earlier pending-cost gate. Branch `codex/a-fly-duel-live` follows
validated/published `2b42812` (private and queued 1v1, results/rematch).

A owns deployment/configuration, endpoint integration, exports and acceptance.
Use only the new `battlebots-fumbleforce` app in the personal organization:
one Stockholm shared-2CPU/2GB Machine and dedicated IPv4, with bounded local
workers. Existing unrelated Fly applications remain outside task scope.

Prepare a fresh Linux release, deploy, verify HTTPS and actual externally
assigned ENet for private/Quick Play duels through results/rematch, then set
the public matchmaking endpoint and prepare matching clients. No B bot/combat/
control source changes. Record project.godot endpoint integration here and in
the handoff. Human hosted play and natural-combat acceptance remain distinct.

## Provisioning

- App created in `personal`: `battlebots-fumbleforce`.
- Dedicated ingress IPv4: `66.51.120.91`.
- One Machine: `287e605ad7d578`, Stockholm `arn`, shared two CPUs/2048 MB.
- Published image digest:
  `sha256:9b776f25dabc8f52e0bb9bbca907111c2a64351c9e18c41beab6ef6ed106f57d`.
- HTTPS `/healthz` passes with build `mvp-ab-11`, protocol 4, current content
  hash and queue capacities two/four. Public assignment tests follow below.
- Corrected Fly Dockerfile path resolution by explicitly supplying repository
  build context, Dockerfile and ignore file. Remote build transferred 166.70 MB;
  the preliminary 1.9 GB warning did not reflect the actual filtered upload.
  Added explicit intermediate-directory exclusions to clarify the allowlist.

## Public-route packet-size diagnosis

Two external runs failed before welcome; improved bounded/redacted peer evidence
identifies `Server disconnected`. HTTPS and the actual UDP bind were healthy.
A temporary UDP echo on unused worker port 24573 measured successful 200/1200/
1300/1350-byte round trips but dropped 1392/1450-byte datagrams. The probe closes
itself after 45 seconds. Godot's default ENet MTU is 1392 and the pinned engine
exposes no MTU setter. Fly documents reduced MTU on its UDP forwarding route.

A enables ENet range-coder compression on both session hosts and clients to
reduce baseline/snapshot datagrams. This is a supported symmetric transport
setting, not a modification of B's simulation. Build becomes `mvp-ab-12` so
public clients must update together with the server. Protocol 4 and bot records
are unchanged. Compression does not establish a hard datagram-size bound for
arbitrary future payloads; external acceptance must verify current game traffic.

## Final acceptance

- Live compressed release image:
  `sha256:75f0baa3c49123aa3c0e484fcdf748e64edeb6cb39e8b629ef54f51521c1194a`.
  Machine remains started with a passing health check; build `mvp-ab-12`.
- External harness passed both private and queued 1v1 from this Windows computer
  to the Fly Linux worker. Both peers drove, agreed on authoritative two-round
  scores/results and entered an active rematch. See the committed
  [redacted report](evidence/fly-duel-2026-09-20.json). Source temporary evidence:
  `battlebots-hosted-s5uxZh`. Forfeit-driven lifecycle proof, not human combat.
- Actual Godot HTTPS client used the configured public endpoint for Quick Play
  and private creation, verified capacity two and canceled both reservations.
- Independent relay boundary test drops 1392 bytes and accepts 1350 intact.
  Existing four-peer transport regression passed at injected 80 ms RTT with
  jitter/loss/duplicates and a 1350-byte datagram ceiling, through admission,
  loadout, driving, damage, round reset, reconnect, results and rematch. Largest
  observed packet was 609 bytes; zero MTU drops. The regular MVP runner applies
  this ceiling to its transport profiles. Larger modes remain deferred product
  scope; this reuses the established transport regression.
- Full presentation suite and final shared baseline pass. Windows online release
  exports and starts headlessly with exit zero. Existing two-ObjectDB shutdown
  warning remains; no native crash or script errors in this increment's checks.
- `project.godot` now uses `https://battlebots-fumbleforce.fly.dev`. Matching
  Windows client is prepared under `battlebots/exports/online-playtest/`.
- Updated allowlist reports 167 MB across 13 files on the second remote build.
  The temporary UDP probe exited; harness credentials and reservations cleaned up.

Remaining: two-computer human hosted duel/recovery and human menu/audio review.
The service remains an ephemeral single-Machine playtest: restart ends matches;
durable identity/results and stronger lifecycle guarantees are later work.
