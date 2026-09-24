import { DatabaseSync } from 'node:sqlite';
import { createHash, randomBytes } from 'node:crypto';

// Durable player identity (#16 Step A, docs/coordination/A_DURABLE_IDENTITY_PLAN.md).
// Players hold a long-lived refresh token and trade it for short access tokens.
// Only sha256 hashes of refresh tokens are stored. Each use rotates the token;
// a retired token keeps working for `overlap` seconds so a lost response cannot
// lock a player out, and never after that.
const digest = value => createHash('sha256').update(value, 'utf8').digest('hex');
const REFRESH = /^[a-f0-9]{64}$/;

const MIGRATIONS = [
  `CREATE TABLE players (
     id TEXT PRIMARY KEY,
     created_at INTEGER NOT NULL,
     last_seen_at INTEGER NOT NULL
   );
   CREATE TABLE refresh_tokens (
     hash TEXT PRIMARY KEY,
     player_id TEXT NOT NULL REFERENCES players(id),
     created_at INTEGER NOT NULL,
     retired_at INTEGER
   );
   CREATE INDEX refresh_tokens_player ON refresh_tokens(player_id);`,
];

export const SCHEMA_VERSION = MIGRATIONS.length;
export const validRefreshToken = value => typeof value === 'string' && REFRESH.test(value);

// path ':memory:' (the default) keeps identities only while the process runs;
// an absolute file path on a persistent volume makes them survive restarts.
export function openIdentityStore({ path = ':memory:', overlap = 60 } = {}) {
  if (!Number.isFinite(overlap) || overlap < 0) throw new Error('Invalid refresh overlap');
  const db = new DatabaseSync(path);
  db.exec('PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;');
  db.exec('CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)');
  let version = db.prepare('SELECT version FROM schema_version').get()?.version;
  if (version === undefined) {
    db.prepare('INSERT INTO schema_version (version) VALUES (0)').run();
    version = 0;
  }
  // Never run against a database written by a newer service.
  if (version > MIGRATIONS.length) throw new Error('Identity database is newer than this service');
  for (; version < MIGRATIONS.length; version++) {
    db.exec('BEGIN');
    try {
      db.exec(MIGRATIONS[version]);
      db.prepare('UPDATE schema_version SET version = ?').run(version + 1);
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
  }
  const insertPlayer = db.prepare('INSERT INTO players (id, created_at, last_seen_at) VALUES (?, ?, ?)');
  const insertToken = db.prepare('INSERT INTO refresh_tokens (hash, player_id, created_at) VALUES (?, ?, ?)');
  const findToken = db.prepare('SELECT player_id, retired_at FROM refresh_tokens WHERE hash = ?');
  const retire = db.prepare('UPDATE refresh_tokens SET retired_at = ? WHERE hash = ? AND retired_at IS NULL');
  const seen = db.prepare('UPDATE players SET last_seen_at = ? WHERE id = ?');
  const prune = db.prepare('DELETE FROM refresh_tokens WHERE retired_at IS NOT NULL AND retired_at < ?');
  const issue = (playerId, now) => {
    const token = randomBytes(32).toString('hex');
    insertToken.run(digest(token), playerId, now);
    return token;
  };
  const transaction = fn => {
    db.exec('BEGIN');
    try { const result = fn(); db.exec('COMMIT'); return result; } catch (error) { db.exec('ROLLBACK'); throw error; }
  };
  return {
    durable: path !== ':memory:',
    createPlayer(now) {
      return transaction(() => {
        const id = randomBytes(16).toString('hex');
        const at = Math.floor(now);
        insertPlayer.run(id, at, at);
        return { playerId: id, refreshToken: issue(id, at) };
      });
    },
    // Returns the player and a fresh refresh token, or null when the token is
    // unknown or was retired longer ago than the overlap.
    rotate(refreshToken, now) {
      if (!validRefreshToken(refreshToken)) return null;
      return transaction(() => {
        const at = Math.floor(now);
        const hash = digest(refreshToken);
        const row = findToken.get(hash);
        if (!row || (row.retired_at !== null && at - row.retired_at > overlap)) return null;
        retire.run(at, hash);
        prune.run(at - overlap);
        seen.run(at, row.player_id);
        return { playerId: row.player_id, refreshToken: issue(row.player_id, at) };
      });
    },
    playerCount() { return db.prepare('SELECT COUNT(*) AS count FROM players').get().count; },
    close() { if (db.isOpen) db.close(); },
  };
}
