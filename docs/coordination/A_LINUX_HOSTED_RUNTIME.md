# A — Linux hosted runtime acceptance

Intent 2026-09-20, `codex/a-linux-hosted-runtime`, base `4cf0a99`.
A owns the deployment image and CI acceptance. Existing CI exports a Linux server
but executes only Windows workers. Add an independent Linux job which runs the
real release worker and private 1v1 lifecycle harness inside the production
container, as the image's unprivileged user. Preserve strict process/error gates.

No B runtime, controls, assets or contracts change. Linux container success will
prove runtime packaging and assigned local UDP play, not Fly routing or external
human acceptance. Hosting remains unprovisioned pending the existing cost decision.
Investigate current CI failures from actual job evidence before claiming green.

## Initial CI audit

Run `35500585059` at `50f3a63` failed after `CAMERA CONTACT PASS` with native
Windows exit `0xC0000005`, before the hosted step. This is another occurrence of
the existing engine shutdown issue, not a hosted-duel assertion failure. The
strict gate remains; no retries or relaxed exit handling were added. Runs for
`bd1dd3f` and `4cf0a99` were still active at inspection, not declared passing.

## New gate

Independent Ubuntu job checksum-verifies pinned Godot/templates, prepares a fresh
release, builds the production Dockerfile and starts its default command/user.
Host clients use the real container HTTP allocator and assigned UDP workers.
`--local-service` explicitly identifies this separately started loopback service;
`--endpoint` retains external HTTPS/public-IP requirements. Both release only the
test's own memberships. The runner stops only its named container and uploads
selected logs/reports, never temporary admission files.
