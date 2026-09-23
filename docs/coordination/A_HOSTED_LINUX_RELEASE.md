# A — coordinated Linux hosted release, 23 September 2026

Owner A; branch `codex/a-hosted-linux-release`, base `345deb8`.
Scope: release tooling, export presets, Linux CI, deployment documentation and
the existing Fly service. No B gameplay, assets, controls or wire changes.

At task start, the service ran build `mvp-ab-12`, protocol 4, catalogue 6 while
main contained `mvp-ab-14`, protocol 6, catalogue 10. The real workers are now
updated to the matching release; compatibility rejection remains enabled.

`tools/prepare-hosted.mjs` uses Node and pinned Godot directly, requires clean
committed source, imports and checks the baseline, generates the actual registry
manifest and exports Linux server plus Linux/Windows clients. Every artifact set
records the same source commit and file hashes. The added Linux Client preset
has no dedicated-server feature. The Linux CI job uses this native command.

Package/container verification, deployment during a user-confirmed playtest
break, matching live health, and external private/Quick Play duels through results
and active rematch all passed. Human two-computer combat acceptance remains open.

Rollback is the previous image on existing Stockholm Machine `287e605ad7d578`:
`registry.fly.io/battlebots-fumbleforce:deployment-01M2ZJ5DWGKZFW108CWPRP7TF0`,
digest `sha256:89584e87ec307388d69dd2ec0959e0c070836e4fea4c9e2bef1a4500d6c9bcf1`.
Retain it; no additional application, Machine or public IP is needed.

## Local validation

Pinned Godot baseline, drive/heavy-drive, Nitro/jump, content, heavy spawn, Atlas
catalogue/grounded weapons/assembly, admission, actual ENet admission/reconnect,
duel menu and HTTP/Quick Play client checks pass. All 25 Node service tests pass.
The natural combat duel passed in 90 seconds through results and active rematch.
Source-worker private and Quick Play duels pass, including actual transport
reconnect with retained health/identity and rotated reconnect credentials
(`/tmp/battlebots-hosted-u3NxJR`).

The online-menu fixture initially failed bounds and its synthetic click: it
compared logical control rectangles (1920x1080 canvas) with physical window
bounds (1280x720), then supplied logical coordinates as physical input. Measured
canvas scale was 2/3. It now checks logical viewport bounds and transforms the
click into window coordinates once. The complete real HTTP/ENet menu flow passes;
production UI and B control code are unchanged. Other historical presentation
fixture failures are outside this release's targeted checks.

Native release preparation passed for all three presets, including the
dirty-source rejection gate. The final artifacts below were rebuilt after the
fixture correction.

## Deployed release

- Clean source: `a84fd11b9c96d4e18378353babe914761a195f44`. Linux server and
  Linux/Windows clients were rebuilt together after the fixture correction.
  Artifact hashes independently match their records. The Linux client starts
  with Vulkan/Forward+ on the RTX 3080 without engine errors. Windows was exported
  but not executed on this Linux machine. Main-menu fit checks pass across the
  existing resolution/text-scale matrix.
- Production container runs as its default unprivileged `node` user. Its actual
  exported workers pass private/Quick Play driving, transport reconnect, two
  forfeit-resolved rounds, agreed results and active rematch. See
  [container report and all artifact records](evidence/linux-release-catalogue-10-2026-09-23.json).
- The user explicitly confirmed the playtest break before restart. The exact
  tested image was pushed and deployed by digest to existing Stockholm Machine
  `287e605ad7d578`, with `--ha=false --strategy immediate --update-only` and that
  Machine as the only deployment target. No new Machine, IP or app was created.
- Image: `registry.fly.io/battlebots-fumbleforce@sha256:e829cafb8fd0cd96449ab7b59f576dc642d8de49cc9b19b8b1e139af920da8f3`.
  Tag: `release-a84fd11-20260923`. Fly reports the expected image, passing health
  and a single started Machine. Its build record, read over SSH, exactly matches
  the local server record.
- Live health matches build `mvp-ab-14`, protocol 6 and catalogue hash
  `623a35b272a0d70feb57b7d4f0d0f298234b9608ab7ac4414945bec8404bd0ed`.
  Submitting the prior build/protocol/catalogue still returns HTTP 409.
- External acceptance passed with
  `node tools/check-hosted.mjs --endpoint https://battlebots-fumbleforce.fly.dev --duel-only --reconnect --godot /home/jorgen/.local/bin/godot`.
  Both private and Quick Play clients drove, reconnected with retained health and
  identity plus rotated credentials, agreed on two-round results and started the
  same rematch. See [external report](evidence/fly-duel-catalogue-10-2026-09-23.json).
  Temporary peer logs: `/tmp/battlebots-hosted-2tiQnu`.

Matching local client archives (ignored build output) are
`battlebots/exports/battlebots-linux-a84fd11.tar.gz` and
`battlebots/exports/battlebots-windows-a84fd11.zip`. Each contains the executable,
adjacent PCK, compatibility manifest and build record. Previous catalogue-six
image is also retained locally as `battlebots-hosted:rollback-catalogue6`.

Rollback, if required during another established playtest break, deploys the
previous digest above to the same Machine. It restores the older compatibility
contract, so current clients would again be rejected. No rollback was necessary.
The local test container is stopped; its owned test memberships were cleaned up.
These checks certify automated hosted lifecycle acceptance, not human control
feel, all historical presentation fixtures or the entire Windows CI suite.
No paths remain reserved after integration.
