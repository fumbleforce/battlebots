# Durable identity and match results: plan (#16)

Status: **proposal**, 24 September 2026. Step A is implemented in its
reversible form (mvp-ab-44): the refresh-token flow and SQLite store run **in
memory** in production, so no volume, retention or backup has been decided or
provisioned. Everything else here still awaits the decisions at the end.
This covers acceptance item 1 of #16: break the next slice into concrete service,
schema, security, migration and failure-behaviour work before anyone writes it.
The decisions that belong to the user are listed at the end. Implementation
starts only after those are answered.

## Where things stand

- **Identity** is an anonymous guest. `POST /v1/guests` mints a random
  `player_id` and a 64-hex bearer token, valid for 2 h with no refresh
  (`services/matchmaking/service.mjs:259-271`). The service keeps only
  `sha256(token)`.
- **Client storage:** the client holds the token in memory only
  (`battlebots/scripts/services/public_service_client.gd:3,12-13`), so every
  launch creates a new player.
- **Service storage:** all service state lives in Maps in one Node process
  (`service.mjs:38-43`). A restart or deploy forgets every guest, room and code.
  There is no database, volume or secret (`services/matchmaking/fly.toml`).
- **Match results** are built by the Godot worker (`mvp_session.gd:849-861`) and
  sent only to clients over ENet. The client banks credits in
  `user://wallet.cfg`, which says it is not tamper-proof
  (`battlebots/scripts/services/credit_wallet.gd:6-8`). Nothing records a result
  on the server.
- **What the worker knows:** it does know each seat's `service_player_id` from
  admission (`mvp_session.gd:453-460`), so results can be attributed.
- **Deployment:** one Fly Machine in `arn`, which must stay one (the allocator
  and UDP workers are local to it). The container is `node:24-bookworm-slim`,
  and the service has no npm dependencies.

## Proposed next slice: "same player next launch, results that count"

Two steps, each shippable on its own.

### Step A: durable player identity (no login)

The player keeps the same identity across launches and restarts without an
account. The client stores a long-lived **refresh credential** and trades it for
the short-lived access token it already uses.

- **Service**
  - `POST /v1/players`: same version check and IP rate limit as `/v1/guests`.
    Creates a player row and returns `player_id`, a `refresh_token` (32 random
    bytes, shown once) and an access token.
  - `POST /v1/sessions` `{refresh_token}`: returns a new access token and
    **rotates** the refresh token. The old one stays valid for a short overlap
    (for example 60 s) so a lost response cannot lock the player out.
  - Keep `/v1/guests` for clients that opt out (see decision 2).
  - Access-token checks stay in memory as today. Only player rows and refresh
    hashes are persisted.
- **Client**
  - `public_service_client.gd` stores the refresh token in
    `user://identity.cfg`, file mode 0600 where the OS allows.
  - On launch it calls `/v1/sessions`. On `401 invalid_refresh` it discards the
    file and creates a new player, telling the user their progress could not be
    restored.
  - Tokens never appear in logs or error text (current rule, `DEPLOYMENT.md:160-164`).
- **Storage:** SQLite on a Fly volume, using Node 24's built-in `node:sqlite`,
  so the service keeps zero npm dependencies.
  - This fits the one-Machine rule. The volume pins the Machine to its host.
  - Fly snapshots the volume daily by default, which gives point-in-time backups.
- **Schema v1**
  ```sql
  CREATE TABLE schema_version (version INTEGER NOT NULL);
  CREATE TABLE players (
    id TEXT PRIMARY KEY,            -- existing 32-hex player id format
    created_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    display_name TEXT,              -- optional, validated server side
    credits INTEGER NOT NULL DEFAULT 0
  );
  CREATE TABLE refresh_tokens (
    hash TEXT PRIMARY KEY,          -- sha256(token); raw token never stored
    player_id TEXT NOT NULL REFERENCES players(id),
    created_at INTEGER NOT NULL,
    retired_at INTEGER              -- set on rotation; accepted briefly after
  );
  ```
- **Migrations:** the service applies numbered migrations at startup inside one
  transaction and refuses to start on a newer `schema_version` than it knows.
  The deploy tool already rolls back an image whose acceptance check fails. Its
  acceptance check gains a persistence probe: create a player, restart,
  resume with the refresh token.

### Step B: server-recorded results and server-held credits

The server records every hosted match result and owns each player's credit
balance. The local wallet becomes a cache.

- **Worker to service:** the worker writes a `results.json` beside
  `status.json` in its private state directory (0600, same trust boundary as
  today). The supervisor reads it once when the match reaches `results`.
  - It carries `match_id`, mode, arena, build, start and end time, and per
    seat: `service_player_id`, team, placement, and the stats the results
    screen shows.
  - No network hop and no new credential are needed, because worker and service
    share the Machine.
- **Service**
  - Writes the match and one row per participant in a single transaction,
    keyed by `match_id` so a re-read cannot double count.
  - Adds each participant's reward to `players.credits`, with the reward rule
    moved to the service.
  - New endpoint: `GET /v1/me` (bearer) returns the balance and recent results.
- **Schema v2**
  ```sql
  CREATE TABLE matches (
    id TEXT PRIMARY KEY, mode TEXT NOT NULL, arena TEXT NOT NULL,
    build TEXT NOT NULL, started_at INTEGER, ended_at INTEGER NOT NULL
  );
  CREATE TABLE match_players (
    match_id TEXT NOT NULL REFERENCES matches(id),
    player_id TEXT NOT NULL REFERENCES players(id),
    team INTEGER NOT NULL, placement INTEGER NOT NULL,
    stats TEXT NOT NULL,            -- JSON, bounded size
    credits_awarded INTEGER NOT NULL,
    PRIMARY KEY (match_id, player_id)
  );
  ```
- **Client**
  - The results screen still shows the ENet results at once.
  - The wallet shows the server balance after `GET /v1/me`.
  - Offline Practice and LAN keep the local wallet, so hosted and local credits
    need a clear rule (decision 4).
- **Anti-abuse:** only hosted-worker results earn server credits. A LAN host's
  claims are never accepted. The existing IP and player rate limits also cap
  player creation.

### Not in this slice (tracked, not expanded)

- Linking to a real account (email, Steam, Discord) so identity survives a new
  computer.
- Parties.
- Region selection or several regions: the one-Machine rule and the volume
  would need rethinking.
- Skill rating: `match_players` above is the input it needs later.
- Larger modes stay deferred (#24).

## Failure behaviour (proposed)

- **Database unreadable at start:** the service starts guest-only. `/healthz`
  reports `persistence: "degraded"`, and `/v1/players` and `/v1/sessions` return
  503. Play continues, and the client keeps its refresh token for later.
- **Write fails while recording a result:** retry from `results.json`, which
  stays until it is committed. After a bounded number of retries, log the match
  id (no tokens) and drop the file. The players keep their ENet results screen
  either way.
- **Volume lost:** restore from the latest Fly snapshot. Players who
  refreshed after that snapshot fall back to a new identity (see decision 5).
- **Deploys:** they still wait for `active_rooms: 0`. The persistence probe
  becomes part of acceptance, with automatic rollback on failure.

## Test plan

- Service unit tests with a temporary database, covering:
  - migrations from empty and from v1
  - refresh rotation and its overlap window
  - a reused retired token is refused after the window
  - duplicate `results.json` counts once
  - degraded start
- Worker test: a real hosted match writes `results.json` with the admitted
  `service_player_id`s.
- Client test: a restart resumes the same `player_id`, and `401 invalid_refresh`
  starts fresh with a notice.
- Live acceptance after deploy: the persistence probe, plus one real Quick Play
  match whose result appears in `GET /v1/me`.

## Rough size

- Step A: service about 250 lines plus tests, client about 80 lines, and
  deployment (volume, fly.toml mount, acceptance probe). One session.
- Step B: service about 200 lines, worker about 60, client wallet changes, and
  tests. One session.
- Cost: a 1 GB Fly volume adds a few cents a month to the ~USD 13.83 now.

## Decisions for the user

1. **Go ahead with Step A and then B as described?** (Or change the order,
   for example results before identity.)
2. **Identity model:** a device-bound identity with no login, as proposed, or
   accounts from the start? A device identity is lost with the computer unless
   linking is added later.
3. **Retention:** how long to keep players who never come back, and match
   history (for example delete players inactive for 12 months; keep matches
   for 6 months)? Is a "delete my data" request path needed now?
4. **Credits:** should hosted matches alone earn server credits, and is the
   current local balance imported once (untrusted) or reset?
5. **Loss tolerance:** is losing up to a day of progress on a volume failure
   acceptable, or is continuous backup (for example Litestream to object
   storage, a new dependency and secret) wanted?
6. **Display names:** needed in this slice? They bring moderation (length,
   characters, offensive names).
