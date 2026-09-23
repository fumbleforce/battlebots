# A — coordinated Linux hosted release, 23 September 2026

Owner A; branch `codex/a-hosted-linux-release`, base `345deb8`.
Scope: release tooling, export presets, Linux CI, deployment documentation and
the existing Fly service. No B gameplay, assets, controls or wire changes.

The service still runs build `mvp-ab-12`, protocol 4, catalogue 6 while main
contains `mvp-ab-14`, protocol 6, catalogue 10. Compatibility rejection is correct
and must remain enabled. Update real workers, not just the health manifest.

`tools/prepare-hosted.mjs` uses Node and pinned Godot directly, requires clean
committed source, imports and checks the baseline, generates the actual registry
manifest and exports Linux server plus Linux/Windows clients. Every artifact set
records the same source commit and file hashes. The added Linux Client preset
has no dedicated-server feature. The Linux CI job uses this native command.

Release acceptance is pending: package/container verification, a confirmed
playtest break, actual worker deployment, matching live health, and external
private/Quick Play duels through results and active rematch. Human two-computer
combat acceptance remains separate.

Rollback is the previous image on existing Stockholm Machine `287e605ad7d578`:
`registry.fly.io/battlebots-fumbleforce:deployment-01M2ZJ5DWGKZFW108CWPRP7TF0`,
digest `sha256:89584e87ec307388d69dd2ec0959e0c070836e4fea4c9e2bef1a4500d6c9bcf1`.
Retain it; no additional application, Machine or public IP is needed.
