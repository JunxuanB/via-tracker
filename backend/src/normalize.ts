import { epoch, type TrainSnapshot, type EventTime } from "./domain.ts";
const record = (v: unknown): Record<string, unknown> | undefined =>
  v && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : undefined;
const text = (v: unknown) => (typeof v === "string" ? v : undefined);
// VIA uses number + optional month/day; the test console uses a full dated identity.
export const trainNumberFromKey = (key: string) =>
  key.match(/^(\d+)(?:\s+\(\d{2}-\d{2}\)|:\d{4}-\d{2}-\d{2})?$/)?.[1];
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
export interface NormalizeOptions {
  /** Last stored snapshots by ID. Events that vanish from a later poll are kept. */
  previous?: ReadonlyMap<string, TrainSnapshot>;
  /** Client-supplied snapshots are validated as-is; only the upstream feed is repaired. */
  repair?: boolean;
}
type Call = TrainSnapshot["calls"][number];
const later = (a?: string, b?: string) =>
  a && b ? (epoch(a)! >= epoch(b)! ? a : b) : (a ?? b);
/**
 * VIA publishes partial records, typically overnight: a stop may carry only an
 * arrival, only the station-level time, or no usable time at all. A stop that
 * cannot be boarded makes the whole train unusable as a schedule reference, so
 * the feed is repaired in two steps: keep what an earlier poll already knew,
 * then derive the missing side of a stop from the side that is present.
 */
function repairCalls(
  parsed: (Call & { station?: EventTime })[],
  rawCodes: (string | undefined)[],
  previous: TrainSnapshot | undefined,
): { calls: Call[]; retained: boolean; inferred: boolean } {
  let retained = false,
    inferred = false;
  const known = new Map(previous?.calls.map((c) => [c.index, c]));
  // Station indices are array positions. Only trust the earlier poll while every
  // stop still sits where it was; otherwise the route itself has changed.
  const aligned =
    !!previous &&
    rawCodes.every((code, index) => !known.has(index) || !code || known.get(index)!.code === code);
  const byIndex = new Map(parsed.map((c) => [c.index, c]));
  if (aligned)
    for (const old of previous!.calls) {
      if (old.index >= rawCodes.length) continue;
      const current = byIndex.get(old.index);
      if (!current) {
        // The stop is still listed upstream but lost its name, zone or times.
        const { reached: _reached, ...rest } = old;
        byIndex.set(old.index, structuredClone(rest));
        retained = true;
        continue;
      }
      for (const side of ["arrival", "departure"] as const) {
        if (current[side] || !old[side]) continue;
        // Keep the published schedule, but never an estimate older than the live one.
        const live = current.arrival?.estimated ?? current.departure?.estimated ?? current.station?.estimated;
        const estimated = later(old[side]!.estimated, live);
        current[side] = { scheduled: old[side]!.scheduled, ...(estimated ? { estimated } : {}) };
        retained = true;
      }
    }
  const lastIndex = rawCodes.length - 1;
  const calls: Call[] = [];
  for (const { station, ...call } of [...byIndex.values()].sort((a, b) => a.index - b.index)) {
    const first = call.index === 0,
      last = call.index === lastIndex;
    if (!call.arrival && !call.departure && station) {
      // The station-level time is the arrival, or the departure at the origin.
      if (!first || last) call.arrival = { ...station };
      if (!last) call.departure = { ...station };
      inferred = true;
    }
    // A terminus keeps no departure: its absence marks the end of the run.
    if (!call.departure && call.arrival && !last) {
      call.departure = { ...call.arrival };
      inferred = true;
    }
    if (!call.arrival && call.departure && !first) {
      call.arrival = { ...call.departure };
      inferred = true;
    }
    if (call.arrival || call.departure) calls.push(call);
  }
  return { calls, retained, inferred };
}
export function normalize(
  raw: unknown,
  fetchedAt: string,
  version: number,
  options: NormalizeOptions = {},
): TrainSnapshot[] {
  const root = record(raw);
  if (!root) throw new Error("invalid_source_shape");
  const repair = options.repair !== false;
  const trains: TrainSnapshot[] = [];
  for (const [rawKey, value] of Object.entries(root)) {
    const r = record(value),
      number = trainNumberFromKey(rawKey);
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
    const parsed = r.times.flatMap((v, index) => {
      const s = record(v);
      if (!s || !text(s.code) || !text(s.station) || !text(s.tz)) return [];
      try {
        new Intl.DateTimeFormat("en", { timeZone: s.tz as string });
      } catch {
        return [];
      }
      const arrival = event(s.arrival),
        departure = event(s.departure),
        station = repair ? event(s) : undefined;
      if (!arrival && !departure && !station) return [];
      return [
        {
          index,
          code: s.code as string,
          name: s.station as string,
          timeZone: s.tz as string,
          ...(typeof s.eta === "string" ? { reached: s.eta === "ARR" } : {}),
          ...(arrival ? { arrival } : {}),
          ...(departure ? { departure } : {}),
          ...(station ? { station } : {}),
        },
      ];
    });
    const id = `${number}:${r.instance}`;
    const repaired = repair
      ? repairCalls(parsed, r.times.map((v) => text(record(v)?.code)), options.previous?.get(id))
      : { calls: parsed as Call[], retained: false, inferred: false };
    const calls = repaired.calls;
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
      id,
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
        ...(repaired.retained ? ["retained_station_events"] : []),
        ...(repaired.inferred ? ["inferred_station_events"] : []),
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
