CREATE INDEX likes_by_level ON likes (level);
CREATE INDEX scores_by_demo ON scores (demo);

-- Where the last demo sweep stopped: the last key it listed. No row means the next run starts from the beginning.
CREATE TABLE sweep (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  last_key TEXT NOT NULL
);
