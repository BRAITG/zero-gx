-- The moderator's label of a version: NULL until a reviewed version is approved.
ALTER TABLE versions ADD COLUMN reviewed_difficulty TEXT CHECK (reviewed_difficulty IN ('easy', 'normal', 'hard', 'expert'));

-- One editable vote per player and version. The server admits a vote only while the history unlocks that version.
CREATE TABLE difficulty_votes (
  player TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  sha256 TEXT NOT NULL REFERENCES versions (sha256),
  difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'normal', 'hard', 'expert')),
  PRIMARY KEY (player, sha256)
);
CREATE INDEX difficulty_votes_by_version ON difficulty_votes (sha256);

-- The feedback statistics read every player's summary of one version.
CREATE INDEX play_summaries_by_version ON play_summaries (sha256);
