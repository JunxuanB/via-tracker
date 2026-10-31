CREATE TABLE test_state (
  id INTEGER PRIMARY KEY CHECK(id=1), raw TEXT, mode TEXT NOT NULL DEFAULT 'healthy',
  revision INTEGER NOT NULL DEFAULT 0, write_token TEXT, last_action TEXT NOT NULL DEFAULT '',
  last_read TEXT, feed_reads INTEGER NOT NULL DEFAULT 0
);
INSERT INTO test_state(id) VALUES(1);
CREATE TABLE test_history (revision INTEGER PRIMARY KEY, raw TEXT NOT NULL, mode TEXT NOT NULL);
CREATE TABLE test_deliveries (
  id TEXT PRIMARY KEY, device_code TEXT NOT NULL, kind TEXT NOT NULL, accepted INTEGER NOT NULL,
  reason TEXT, sent_at INTEGER NOT NULL, environment TEXT NOT NULL
);
CREATE INDEX test_deliveries_time ON test_deliveries(sent_at);
