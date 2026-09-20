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

## Verified evidence

- Local separately started service + Windows release worker: PASS. Two clients
  drove 11.54 m, agreed on two rounds/0-2 scores/winner and entered one new rematch.
  Syntax and invalid argument checks passed; owned service/tickets cleaned up.
- [Linux run 35501573901](https://github.com/fumbleforce/battlebots/actions/runs/35501573901)
  at `8686c24`: PASS. Production image default command runs as `node`; real Linux
  release worker allocated by its HTTP service. Both host clients received 1512
  snapshots, drove 11.54 m, agreed on 0-2 scores and entered the same active rematch.
  Container log confirms its worker stopped by expected SIGTERM after membership
  cleanup. Downloaded report and logs inspected, not just workflow conclusion.
- [Windows run 35501573844](https://github.com/fumbleforce/battlebots/actions/runs/35501573844)
  on the same commit failed after `DRIVE PASS` with `0xC0000005`. This job never
  reached hosted checks. It reproduces the documented native shutdown issue in
  unchanged drive/runtime files; the Linux feature does not fix or mask it.

Linux packaging/lifecycle acceptance is now proven. Fly public UDP routing,
external human play and the Windows shutdown defect remain open. The relevant
new Linux check passes; do not describe the full Windows CI pipeline as green.
