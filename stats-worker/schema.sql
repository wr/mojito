-- Mojito anonymous usage stats — D1 schema.
--
-- Everything is a per-UTC-day rollup keyed by an integer day number
-- (floor(unix_seconds / 86400)). The ingest endpoint UPSERTs counters; it
-- never stores a row per request, an identifier, or an IP. Published views
-- are pure marginals (each dimension its own table) — we never cross-tabulate,
-- so a single small count can't single anyone out.

CREATE TABLE IF NOT EXISTS emoji_daily (
  day     INTEGER NOT NULL,
  hexcode TEXT    NOT NULL,            -- emojibase hexcode, e.g. 1F600 or 1F469-200D-1F4BB
  count   INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, hexcode)
);

-- Marginal distributions: os / arch / lang / app / skinTone. One increment
-- per daily ping per dimension.
CREATE TABLE IF NOT EXISTS dim_daily (
  day   INTEGER NOT NULL,
  dim   TEXT    NOT NULL,
  value TEXT    NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, dim, value)
);

-- Feature adoption: how many reporting installs had each feature on.
CREATE TABLE IF NOT EXISTS feature_daily (
  day     INTEGER NOT NULL,
  feature TEXT    NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 0,  -- installs with it on
  total   INTEGER NOT NULL DEFAULT 0,  -- installs reporting at all
  PRIMARY KEY (day, feature)
);

-- Insertion volume + daily-active pings. kind ∈
-- emoji | symbol | gif | emoticon | active | eggs
CREATE TABLE IF NOT EXISTS totals_daily (
  day   INTEGER NOT NULL,
  kind  TEXT    NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, kind)
);

-- Running scalars (e.g. lifetime community easter-egg discoveries — a bare
-- tally, never which egg or how many exist).
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value INTEGER NOT NULL DEFAULT 0
);
