# Fly.io online playtest deployment

Live endpoint: `https://battlebots-fumbleforce.fly.dev`. Updated 2026-09-23 to
build `mvp-ab-14`, protocol 6, catalogue 10 from source `a84fd11`, with matching
Linux/Windows clients. Private and Quick Play duels passed external UDP driving,
reconnect, results and active rematch checks; stale clients still receive HTTP 409.
See [current release and rollback evidence](../../docs/coordination/A_HOSTED_LINUX_RELEASE.md).
The original deployment was 2026-09-20; previous catalogue-six evidence remains in
[service synchronization](../../docs/coordination/A_QUICK_PLAY_SERVICE_SYNC.md).
Provisioning commands below describe recreation, not a request to create duplicates.

This deploys the HTTPS matchmaker and a bounded pool of real Godot UDP game
servers. Players need only the updated game; they do not host a tunnel or forward
ports. First deployment uses one Machine in Stockholm (`arn`), four worker ports
and guest sessions. Rooms, queues and guest credentials are ephemeral: a service
restart invalidates them and running matches are incomplete. This is not the
public-release persistence/account implementation.

## Automated deploys (GitHub Actions)

Every push to `main` that touches the game, service or release tooling runs the
**Linux hosted duel runtime** workflow. After it prepares the release from that
commit and passes the local production-container duel, it runs
`tools/deploy-hosted.mjs`, which:

1. skips the deploy when live `/healthz` already reports this build, protocol and
   content hash;
2. records the running image for rollback;
3. waits (up to 45 minutes) until `/healthz` reports `active_rooms: 0`, so a
   restart never ends a running playtest;
4. runs `fly deploy` with the checked-in configuration;
5. waits until live `/healthz` reports exactly this commit's manifest;
6. runs the external private + Quick Play duel acceptance against the live
   endpoint, and rolls back to the recorded image if any step fails.

Deploys are serialized (one at a time). A manual *Run workflow* on `main` also
deploys. The workflow uses the repository secret `FLY_API_TOKEN`, a deploy token
scoped to the `battlebots-fumbleforce` app (`fly tokens create deploy`), which
expires after one year. The same script can deploy manually after
`node tools/prepare-hosted.mjs` with `FLY_API_TOKEN` set.

## Prepare and validate

On Linux, use Node 24 and Godot 4.7.2 with matching export templates; PowerShell
is not needed. From a clean committed repository:

```bash
nvm use 24
npm test --prefix services/matchmaking
node tools/prepare-hosted.mjs --godot godot
node tools/check-hosted.mjs --godot godot --duel-only \
  --server-binary "$PWD/battlebots/exports/hosted-server/battlebots-server.x86_64"
fly config validate -c services/matchmaking/fly.toml
```

The native preparation command imports/checks the baseline and exports Linux
server plus Linux/Windows clients from one clean commit. `hosted-server`,
`linux-client` and `windows-client` under `battlebots/exports/` each contain a
generated compatibility manifest and a build record with source commit and
SHA256 hashes. Keep each executable with its adjacent PCK. Test the production
container and record its image before deploying; a build alone is not acceptance.

From the repository root with Godot 4.7.2 and matching export templates installed:

```powershell
node --test services/matchmaking/test/*.test.mjs
node tools/check-hosted.mjs --godot $GodotPath
./tools/prepare-hosted.ps1 -GodotPath $GodotPath -WindowsSmokeServer
node tools/check-hosted.mjs --godot $GodotPath --server-binary (Resolve-Path battlebots/exports/hosted-windows/battlebots.exe)
fly config validate -c services/matchmaking/fly.toml
```

For the current 1v1 priority, add `--duel-only` to either hosted check. It checks
both a private duel and two-player Quick Play, each using two independent clients
and public forfeit votes to verify two rounds, matching
authoritative scores/results and an active rematch. This is lifecycle acceptance,
not natural combat or human-feel acceptance. Omitting the flag retains the older
four-client queue regression too when running locally; external endpoint mode
always selects these duel checks. Legacy four-player regression is not required
for deployment. Health must advertise `queue_capacities` containing two; the
current client never silently falls back to the legacy four-player queue.

The prepare command creates a fresh Linux binary, PCK and compatibility manifest
under `battlebots/exports/hosted-server/`. The existing menu/music playtest ZIP is
preserved. The Docker context excludes unrelated repository files, private local
configuration and other exports. The runtime runs as an unprivileged user.

The **Linux hosted duel runtime** CI job prepares the Linux release, builds this
Dockerfile and starts its default command as `node`. Two independent host-side
Godot clients then use `--local-service http://127.0.0.1:18080` to test the real
container allocator and its release workers through results/rematch. That option
is restricted to literal HTTP loopback and does not launch a replacement service.
The image's bind/public-address overrides are local test configuration only;
Fly uses the deployed configuration below. CI artifacts retain redacted peer logs,
the non-secret result report, image service logs and release hashes. Success proves
Linux runtime packaging, not internet/Fly routing or human combat acceptance.
The first production-container run passed at `8686c24`; see
[recorded Linux evidence](../../docs/coordination/A_LINUX_HOSTED_RUNTIME.md).

## Provision and deploy

The checked-in app name is `battlebots-fumbleforce`; change both `app` and
`PUBLIC_ADDRESS` together if that name is unavailable. Use the selected Fly
organization, not an unrelated existing application. The commands below create
billable resources and are deployment instructions, not evidence of deployment.

```powershell
fly apps create battlebots-fumbleforce --org personal
fly ips allocate-v4 --app battlebots-fumbleforce
fly deploy . --config services/matchmaking/fly.toml --dockerfile services/matchmaking/Dockerfile --ignorefile .dockerignore --remote-only --ha=false --strategy immediate
fly scale count 1 --app battlebots-fumbleforce
fly status --app battlebots-fumbleforce
```

Only one Machine may serve this allocator. Do not enable rolling multi-Machine
deployment or automatic scale-out: the in-memory room directory and UDP workers
are local to that Machine. Update during a playtest break; an image restart ends
its running matches. Autostop is disabled because HTTPS idleness does not mean a
UDP game is idle.

Fly HTTPS terminates TLS and routes to TCP 8080. UDP 24570–24573 must use dedicated
public IPv4 and bind the resolved `fly-global-services` address. External and
internal UDP ports match; shared IPv4/public IPv6 cannot carry this ENet service.
The service resolves `PUBLIC_ADDRESS` explicitly to IPv4 before issuing assignments
so an IPv6-preferring client cannot accidentally choose the app's HTTPS-only IPv6.
Do not place an ordinary HTTP CDN proxy in front of the game endpoint.

After health and a real external assigned-ENet check pass, set
`services/matchmaking_url` in `battlebots/project.godot` to
`https://battlebots-fumbleforce.fly.dev` and export matching clients. The endpoint
is public configuration, not a secret. An override `--matchmaking-url=...` permits
testing a different HTTPS service; plain HTTP is accepted only for literal
loopback addresses. Deploying a new build requires matching clients/server.

Run the external acceptance check from a computer outside the Fly Machine:

```powershell
node tools/check-hosted.mjs --godot $GodotPath --endpoint https://battlebots-fumbleforce.fly.dev --duel-only
```

This mode uses the deployed allocator and its assigned UDP workers; it does not
start a local service/server. It still runs two independent clients on the test
computer. Keep the resulting report as deployment evidence, then conduct a
two-computer human hosted duel to assess actual combat and connection quality.

## Costs and limits

Pricing checked 2026-09-19: Stockholm shared 2 CPUs/2 GB is about USD 11.83/month
continuously running, plus USD 2/month for required dedicated IPv4, plus public
egress (Europe USD 0.02/GB), applicable build usage and tax. The approximate base
is USD 13.83/month; it is not a hard spending cap. This size is a playtest starting
point, not a certified four-concurrent-match performance tier. Worker/room caps
bound application allocation; there is no automatic Machine scaling.

Sources: [Fly pricing](https://fly.io/docs/about/pricing/),
[Fly UDP requirements](https://fly.io/docs/networking/udp-and-tcp/),
[Fly configuration](https://fly.io/docs/reference/configuration/).

The service logs only operational identifiers/errors, never guest bearer or join
tickets. Worker allocation files contain ticket hashes and live leases. They are
local runtime files with restrictive permissions and do not enter exports. A
worker stops when the supervisor lease expires, preventing an orphaned process
from continuing to accept allocations after a control-service crash.
