-- Remote Live Activity start: the app-wide push-to-start token, the passenger's
-- opt-in per journey, and the tracking window a start was already sent for.
ALTER TABLE installations ADD COLUMN activity_start_token TEXT;
ALTER TABLE subscriptions ADD COLUMN auto_start TEXT;
ALTER TABLE subscriptions ADD COLUMN auto_start_sent_for INTEGER NOT NULL DEFAULT 0;
