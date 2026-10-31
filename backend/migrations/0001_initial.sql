CREATE TABLE source_state (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL DEFAULT 0, fetched_at TEXT, status TEXT NOT NULL DEFAULT 'unavailable', lease_until INTEGER NOT NULL DEFAULT 0, lease_owner TEXT);
INSERT INTO source_state(id) VALUES(1);
CREATE TABLE trains (id TEXT PRIMARY KEY, number TEXT NOT NULL, service_date TEXT NOT NULL, snapshot TEXT NOT NULL, fetched_at TEXT NOT NULL);
CREATE INDEX trains_number ON trains(number, service_date);
CREATE TABLE installations (id TEXT PRIMARY KEY, credential_hash TEXT NOT NULL, push_token TEXT, environment TEXT NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE subscriptions (id TEXT PRIMARY KEY, installation_id TEXT NOT NULL REFERENCES installations(id) ON DELETE CASCADE, revision INTEGER NOT NULL, journey TEXT NOT NULL, activity TEXT, last_sent TEXT, last_sent_at INTEGER, last_apns_timestamp INTEGER NOT NULL DEFAULT 0, notification_state TEXT NOT NULL DEFAULT '', expires_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE INDEX subscriptions_owner ON subscriptions(installation_id);
CREATE INDEX subscriptions_expiry ON subscriptions(expires_at);
