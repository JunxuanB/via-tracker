CREATE TABLE train_feeds (
  service_date TEXT PRIMARY KEY,
  snapshots TEXT NOT NULL CHECK(length(CAST(snapshots AS BLOB)) < 1800000),
  fetched_at TEXT NOT NULL
);
INSERT INTO train_feeds(service_date,snapshots,fetched_at)
SELECT service_date,json_group_object(id,json(snapshot)),max(fetched_at)
FROM trains GROUP BY service_date;
