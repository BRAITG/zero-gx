-- Attempts the app reports for the difficulty votes. Times are Unix milliseconds: started_ms and ended_ms are the app's
-- own clock (ordering hints only), received_ms is the server's. Revision 1 is the start, revision 2 the result.
CREATE TABLE play_attempts (
  player TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  sha256 TEXT NOT NULL REFERENCES versions (sha256),
  started_ms INTEGER NOT NULL,
  revision INTEGER NOT NULL CHECK (revision IN (1, 2)),
  outcome TEXT CHECK (outcome IN ('failed', 'abandoned', 'cleared')),
  ended_ms INTEGER,
  received_ms INTEGER NOT NULL,
  PRIMARY KEY (player, id),
  CHECK ((revision = 1 AND outcome IS NULL AND ended_ms IS NULL) OR (revision = 2 AND outcome IS NOT NULL AND ended_ms IS NOT NULL))
);
CREATE INDEX play_attempts_by_version ON play_attempts (player, sha256, started_ms);

-- Per player and version: the counted attempts, and the end of the earliest clear (NULL while none has cleared).
CREATE TABLE play_summaries (
  player TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  sha256 TEXT NOT NULL REFERENCES versions (sha256),
  attempts INTEGER NOT NULL,
  first_clear_ms INTEGER,
  PRIMARY KEY (player, sha256)
);
