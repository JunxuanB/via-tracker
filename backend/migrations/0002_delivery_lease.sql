ALTER TABLE subscriptions ADD COLUMN delivery_lease_until INTEGER NOT NULL DEFAULT 0;
ALTER TABLE subscriptions ADD COLUMN delivery_owner TEXT;
