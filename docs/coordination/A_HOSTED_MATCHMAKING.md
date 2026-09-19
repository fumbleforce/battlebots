# A hosted matchmaking increment

Owner: Developer A. Branch `codex/a-hosted-matchmaking`, based on performance
`3f0e80f`. User priority: play over the internet without player-hosted tunnels.

Use Fly.io for both the HTTPS matchmaking API and dedicated Godot/ENet workers.
A matchmaker alone cannot make a residential UDP host reachable. Fly supports
the existing transport; Cloudflare Containers currently accept HTTP through a
Worker, not direct inbound UDP. Keep Cloudflare optional for later control-service
work rather than introducing two providers for this playtest.

First delivery: guest sessions, private rooms with shareable codes, a solo 2v2
queue, assigned public UDP endpoints and short-lived admission tickets. Existing
LAN/practice remain available. Public servers enforce reserved player/slot/build
bindings; reconnect credentials remain separate. No cosmetic awards or persistent
account claims in this increment. Parties, skill matching, multiple regions,
durable receipts and public release acceptance remain subsequent work.

One Fly Machine runs a bounded pool of four game processes on UDP 24570–24573
and the HTTP control process on TCP 8080 behind Fly HTTPS. Dedicated public IPv4
is required. Each UDP worker resolves/binds `fly-global-services`, with the same
external/internal port. Do not horizontally scale this in-memory allocator:
multiple Machines would need a shared allocator and per-allocation routing.
Autostop stays disabled so HTTP idleness cannot terminate an active UDP match.

Parallel ownership for this increment:

- A control-service agent: `services/matchmaking/` implementation and Node tests.
- A worker agent: hosted admission/worker, session integration and isolated tests.
- A client agent: service client and minimal online-menu integration/tests.
- Root: deployment packaging, end-to-end checks and coordination documentation.

The user explicitly requests the hosted player flow; UI changes here are the
integration necessary to reach it. Existing B assets and modelling checkout remain
untouched. Preserve separate ownership within the shared directory.

## Initial wire/control agreement

Build `mvp-ab-10`, protocol 4, existing catalogue revision four. The generated
manifest is `{build, protocol, content_hash}`; no duplicated hand-written hash.
`POST /v1/guests` checks that manifest and returns a guest bearer credential.
Authenticated room creation/join, 2v2 queue, membership poll and membership cancel
use bounded JSON over HTTPS (literal loopback HTTP is allowed for local tests).
Only a fresh ready worker produces a playable assignment. Assignments carry the
address, port, room ID and admission ticket. The ticket is distinct from ENet's
reconnect token and is never logged or put in process arguments.

The supervisor atomically writes a private allocation configuration with slot
bindings, SHA256 ticket hashes/expiry and a thirty-second lease. Godot publishes
readiness/phase and connected player IDs to a local status file. The supervisor
renews the lease; worker exits on stale/revoked configuration. Local lifecycle
files are not a network-accessible API. Worker failures report incomplete games.
Each membership has a unique reservation generation, preserved during ticket
rotation and changed on cancellation/rejoin. Old connected peers and reconnect
tokens cannot retain a replaced reservation. Game endpoints resolve to IPv4 so
the Fly app's public IPv6 cannot accidentally be selected for UDP.

Export templates ignore the editor's `--script` entry option. Allocation workers
therefore use normal application startup with `--allocation-config`; the main
scene routes to the dedicated packed scene before ordinary menu/server startup.
Source and exported workers share this path and `/root/MenuGame/Session` RPC root.

## Validation and deployment gates

Node tests cover HTTP authentication, version/bounds, queues, room codes, worker
failure/cancellation and reservation reuse. Godot tests cover admission/replay/
expiry and unchanged local/reconnect flows. An independent-process test must
create a room through HTTP, join real clients through assigned ENet, Ready and
reach active. Validate both source and exported-server paths. Generate a new
online playtest export separately from the saved menu/music ZIP.

Fly account is accessible; no new paid app/IP/Machine has been provisioned yet.
Prepare and test the complete deployment before confirming its concrete cost
and provisioning scope. External reachability and real internet play must be
measured after deployment, not inferred from local checks.

Local evidence: nineteen Node tests passed; admission and service-client/menu
tests passed; real private two-player and queued four-player matches reached
active gameplay both from source and with a released Windows worker executable.
Linux export and Fly config validation passed, but Linux runtime awaits deployment.
An intermittent native GDScript shutdown crash in the existing baseline/camera
fixtures remains open; gates reject its backtrace even if Godot returns zero.
The saved menu/music ZIP is unchanged. Public endpoint configuration and a new
online-client ZIP follow external reachability validation.

Sources checked 2026-09-19:
[Fly UDP](https://fly.io/docs/networking/udp-and-tcp/),
[Cloudflare Container networking](https://developers.cloudflare.com/containers/concepts/architecture/).
