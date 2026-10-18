-- Times are Unix seconds. Ids: players p_<16>, levels lvl_<10> (assigned by the server).
CREATE TABLE players (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  banned INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL
);

CREATE TABLE accounts (
  provider TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  player TEXT NOT NULL,
  PRIMARY KEY (provider, provider_id)
);

CREATE TABLE levels (
  id TEXT PRIMARY KEY,
  owner TEXT NOT NULL,
  based_on TEXT,
  latest INTEGER NOT NULL DEFAULT 0,
  hidden INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL
);

CREATE TABLE versions (
  level TEXT NOT NULL,
  version INTEGER NOT NULL,
  sha256 TEXT NOT NULL UNIQUE,
  approved INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (level, version)
);

CREATE TABLE submissions (
  id INTEGER PRIMARY KEY,
  level TEXT NOT NULL,
  version INTEGER NOT NULL,
  player TEXT NOT NULL,
  pull_request INTEGER,
  status TEXT NOT NULL CHECK (status IN ('open', 'approved', 'rejected')),
  comment TEXT,
  created INTEGER NOT NULL,
  decided INTEGER
);
CREATE UNIQUE INDEX one_open_per_level ON submissions (level) WHERE status = 'open';

CREATE TABLE scores (
  sha256 TEXT NOT NULL,
  player TEXT NOT NULL,
  points INTEGER NOT NULL,
  fuel REAL NOT NULL,
  hull REAL NOT NULL,
  seconds REAL NOT NULL,
  demo TEXT NOT NULL,
  posted INTEGER NOT NULL,
  PRIMARY KEY (sha256, player)
);
CREATE INDEX scores_by_points ON scores (sha256, points DESC);

CREATE TABLE official_levels (
  sha256 TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  release TEXT NOT NULL
);

CREATE TABLE likes (
  player TEXT NOT NULL,
  level TEXT NOT NULL,
  PRIMARY KEY (player, level)
);

CREATE TABLE player_ranking (
  player TEXT PRIMARY KEY,
  points INTEGER NOT NULL,
  rank INTEGER NOT NULL,
  computed INTEGER NOT NULL
);

CREATE TABLE nonces (
  nonce TEXT PRIMARY KEY,
  expires INTEGER NOT NULL
);

CREATE TABLE rate (
  player TEXT NOT NULL,
  action TEXT NOT NULL,
  "window" INTEGER NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY (player, action, "window")
);

CREATE TABLE hidden_levels (
  level TEXT PRIMARY KEY
);

CREATE TABLE reports (
  player TEXT NOT NULL,
  level TEXT NOT NULL,
  PRIMARY KEY (player, level)
);
