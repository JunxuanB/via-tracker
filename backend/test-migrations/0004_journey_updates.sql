ALTER TABLE subscriptions ADD COLUMN milestone_state TEXT NOT NULL DEFAULT '';
ALTER TABLE installations ADD COLUMN widget_token TEXT;
ALTER TABLE installations ADD COLUMN widget_state TEXT;
ALTER TABLE installations ADD COLUMN widget_sent_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE installations ADD COLUMN widget_attempt_at INTEGER NOT NULL DEFAULT 0;
