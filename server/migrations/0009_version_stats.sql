-- The server receipt time of the latest report on the version; the rating's reference window reads it. NULL before the backfill below.
ALTER TABLE play_summaries ADD COLUMN last_ms INTEGER;
UPDATE play_summaries SET last_ms = (SELECT MAX(received_ms) FROM play_attempts a WHERE a.player = play_summaries.player AND a.sha256 = play_summaries.sha256);

-- Derived, rebuilt by the cron: one row per approved version of a visible level that has starters. The model columns are
-- NULL while the version is Estimating; `curve` is a JSON array, the share of starters who cleared by attempt t = 1..30.
CREATE TABLE version_stats (
  sha256 TEXT PRIMARY KEY REFERENCES versions (sha256),
  starters INTEGER NOT NULL,
  clears INTEGER NOT NULL,
  not_cleared_20 INTEGER NOT NULL,
  curve TEXT NOT NULL,
  beta REAL,
  rating_sd REAL,
  p10_low REAL,
  p10_high REAL,
  rated TEXT,
  rated_high TEXT,
  audience REAL,
  computed_ms INTEGER NOT NULL
);
