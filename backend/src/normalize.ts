import { epoch, type TrainSnapshot, type EventTime } from "./domain.ts";
const record = (v: unknown): Record<string, unknown> | undefined =>
  v && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : undefined;
const text = (v: unknown) => (typeof v === "string" ? v : undefined);
function event(v: unknown): EventTime | undefined {
  const r = record(v),
    scheduled = text(r?.scheduled),
    estimated = text(r?.estimated);
  if (
    !scheduled ||
    !/(Z|[+-]\d{2}:\d{2})$/.test(scheduled) ||
    epoch(scheduled) === undefined
  )
    return undefined;
  return {
    scheduled,
    ...(estimated &&
    /(Z|[+-]\d{2}:\d{2})$/.test(estimated) &&
    epoch(estimated) !== undefined
      ? { estimated }
      : {}),
  };
}
export function normalize(
  raw: unknown,
  fetchedAt: string,
  version: number,
): TrainSnapshot[] {
  const root = record(raw);
  if (!root) throw new Error("invalid_source_shape");
  const trains: TrainSnapshot[] = [];
  for (const [rawKey, value] of Object.entries(root)) {
    const r = record(value),
      number = rawKey.match(/^(\d+)(?:\s+\(\d{2}-\d{2}\))?$/)?.[1];
    if (
      !r ||
      !number ||
      typeof r.instance !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(r.instance) ||
      !Number.isFinite(Date.parse(r.instance + "T12:00:00Z")) ||
      new Date(r.instance + "T12:00:00Z").toISOString().slice(0, 10) !==
        r.instance ||
      !Array.isArray(r.times)
    )
      continue;
    const calls = r.times.flatMap((v, index) => {
      const s = record(v);
      if (!s || !text(s.code) || !text(s.station) || !text(s.tz)) return [];
      try {
        new Intl.DateTimeFormat("en", { timeZone: s.tz as string });
      } catch {
        return [];
      }
      const arrival = event(s.arrival),
        departure = event(s.departure);
      if (!arrival && !departure) return [];
      return [
        {
          index,
          code: s.code as string,
          name: s.station as string,
          timeZone: s.tz as string,
          ...(typeof s.eta === "string" ? { reached: s.eta === "ARR" } : {}),
          ...(arrival ? { arrival } : {}),
          ...(departure ? { departure } : {}),
        },
      ];
    });
    if (!calls.length) continue;
    const validPosition =
      typeof r.lat === "number" &&
      typeof r.lng === "number" &&
      Number.isFinite(r.lat) &&
      Number.isFinite(r.lng) &&
      Math.abs(r.lat) <= 90 &&
      Math.abs(r.lng) <= 180 &&
      !(r.lat === 0 && r.lng === 0);
    trains.push({
      id: `${number}:${r.instance}`,
      trainNumber: number,
      originServiceDate: r.instance,
      rawKey,
      from: text(r.from) ?? "",
      to: text(r.to) ?? "",
      departed: r.departed === true,
      arrived: r.arrived === true,
      calls,
      sourceFetchedAt: fetchedAt,
      version,
      qualityFlags: [
        "station_actual_events_unverified",
        ...(calls.length < r.times.length ? ["incomplete_station_events"] : []),
        ...(validPosition && epoch(text(r.poll)) === undefined
          ? ["position_time_unknown"]
          : []),
      ],
      ...(validPosition
        ? {
            position: {
              latitude: r.lat as number,
              longitude: r.lng as number,
              ...(typeof r.speed === "number" && Number.isFinite(r.speed) && r.speed >= 0 && r.speed <= 400
                ? { speedKmh: r.speed } : {}),
              ...(typeof r.direction === "number" && Number.isFinite(r.direction) && r.direction >= 0 && r.direction < 360
                ? { heading: r.direction } : {}),
              ...(epoch(text(r.poll)) !== undefined
                ? { reportedAt: r.poll as string }
                : {}),
            },
          }
        : {}),
      alerts: (Array.isArray(r.alerts) ? r.alerts : []).flatMap((v) => {
        const a = record(v);
        if (!a) return [];
        const title =
          text(record(a.header)?.en) ?? text(record(a.header)?.fr) ?? "";
        const body =
          text(record(a.description)?.en) ??
          text(record(a.description)?.fr) ??
          "";
        const url = text(record(a.url)?.en) ?? text(record(a.url)?.fr);
        return [
          { title, body, ...(url && /^https?:\/\//.test(url) ? { url } : {}) },
        ];
      }),
    });
  }
  if (!trains.length) throw new Error("empty_source");
  return trains;
}
