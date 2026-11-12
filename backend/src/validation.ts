import { APIError, obj, str, int } from "./http.ts";
import {
  stations,
  epoch,
  type Journey,
  type TrainSnapshot,
  type TrainLeg,
} from "./domain.ts";
import { normalize } from "./normalize.ts";
export interface ActivitySession {
  id: string;
  token: string;
  startedAt: number;
  revision: number;
  /** Present for activities started from the test environment. */
  testSource?: string;
}
export function validateActivity(value: unknown): ActivitySession | undefined {
  if (value == null) return undefined;
  const a = obj(value),
    token = str(a.token, 512);
  if (!/^[a-fA-F0-9]{32,512}$/.test(token) || token.length % 2)
    throw new APIError(400, "invalid_activity_token");
  return {
    id: str(a.id),
    token,
    startedAt: int(a.startedAt, 0, 4e10),
    revision: int(a.revision, 1, 2e9),
    ...(a.testSource == null ? {} : { testSource: str(a.testSource, 300) }),
  };
}
export function validateJourney(value: unknown): Journey {
  const j = obj(value);
  if (!Array.isArray(j.legs) || !j.legs.length || j.legs.length > 16)
    throw new APIError(400, "invalid_legs");
  const phases = [
    "beforeDeparture",
    "onTheWay",
    "waiting",
    "riding",
    "transferring",
    "completed",
  ];
  if (j.manualPhase !== undefined && !phases.includes(String(j.manualPhase)))
    throw new APIError(400, "invalid_phase");
  if (!["ask", "keep", "automatic"].includes(String(j.syncChoice)))
    throw new APIError(400, "invalid_sync_choice");
  for (const flag of [
    "completed",
    "trackingEnded",
    "pendingScheduleChange",
    "scheduleChangePrompted",
  ])
    if (typeof j[flag] !== "boolean") throw new APIError(400, "invalid_flag");
  // Reuse normalization validation for the snapshot's station-event shape; never trust embedded source flags for actual events.
  const legs = j.legs.map((value) => {
    const l = obj(value),
      s = obj(l.snapshot);
    const trainNumber = str(l.trainNumber, 6),
      serviceDate = str(l.originServiceDate, 10);
    if (!/^\d+$/.test(trainNumber) || !/^\d{4}-\d{2}-\d{2}$/.test(serviceDate))
      throw new APIError(400, "invalid_identity");
    if (s.id !== `${trainNumber}:${serviceDate}` || s.trainNumber !== trainNumber || s.originServiceDate !== serviceDate)
      throw new APIError(400, "snapshot_identity_mismatch");
    const fetchedAt = str(s.sourceFetchedAt, 40);
    if (epoch(fetchedAt) === undefined || !/(Z|[+-]\d{2}:\d{2})$/.test(fetchedAt))
      throw new APIError(400, "invalid_source_time");
    const position = s.position == null ? undefined : obj(s.position);
    if (!Array.isArray(s.calls) || s.calls.length > 300)
      throw new APIError(400, "invalid_calls");
    const rawCalls = s.calls.map((v) => {
      const c = obj(v);
      return {
        station: str(c.name),
        code: str(c.code, 20),
        tz: str(c.timeZone, 80),
        arrival: c.arrival,
        departure: c.departure,
        eta: typeof c.reached === "boolean" ? c.reached ? "ARR" : "" : undefined,
      };
    });
    let validated: TrainSnapshot;
    try {
      validated = normalize(
        {
          [trainNumber]: {
            instance: serviceDate,
            from: s.from,
            to: s.to,
            times: rawCalls,
            departed: s.departed === true,
            arrived: s.arrived === true,
            lat: position?.latitude,
            lng: position?.longitude,
            poll: position?.reportedAt,
            speed: position?.speedKmh,
            direction: position?.heading,
          },
        },
        fetchedAt,
        int(s.version, 0, Number.MAX_SAFE_INTEGER),
        { repair: false },
      )[0];
    } catch {
      throw new APIError(400, "invalid_snapshot");
    }
    validated.rawKey = str(s.rawKey, 100);
    if (Array.isArray(s.alerts)) {
      if (s.alerts.length > 50) throw new APIError(400, "too_many_alerts");
      validated.alerts = s.alerts.map(value => {
        const alert = obj(value);
        const title = typeof alert.title === "string" ? alert.title.slice(0, 500) : "";
        const body = typeof alert.body === "string" ? alert.body.slice(0, 5000) : "";
        const url = typeof alert.url === "string" && /^https?:\/\//.test(alert.url)
          ? alert.url.slice(0, 2048) : undefined;
        return { title, body, ...(url ? { url } : {}) };
      });
    }
    if (validated.calls.length !== s.calls.length)
      throw new APIError(400, "invalid_station_event");
    // Client snapshots must preserve a strictly increasing sequence of station indices.
    validated.calls.forEach((c, i) => {
      c.index = int(obj((s.calls as unknown[])[i]).index, 0, 1000);
    });
    if (
      validated.calls.some(
        (c, i) => i > 0 && c.index <= validated.calls[i - 1].index,
      )
    )
      throw new APIError(400, "invalid_station_sequence");
    const source = l.source;
    if (source !== "reference" && source !== "official")
      throw new APIError(400, "invalid_source");
    if (source === "reference") {
      validated.departed = false;
      validated.arrived = false;
      delete validated.position;
      validated.alerts = [];
      for (const call of validated.calls) {
        delete call.reached;
        if (call.arrival) delete call.arrival.estimated;
        if (call.departure) delete call.departure.estimated;
      }
    }
    const leg: TrainLeg = {
      id: str(l.id),
      trainNumber,
      originServiceDate: serviceDate,
      boardingCode: str(l.boardingCode, 20),
      boardingIndex: int(l.boardingIndex, 0, 1000),
      alightingCode: str(l.alightingCode, 20),
      alightingIndex: int(l.alightingIndex, 0, 1000),
      planningDeparture: int(l.planningDeparture, 0, 4e10),
      source,
      snapshot: validated,
      ...(typeof l.referenceInstanceID === "string"
        ? { referenceInstanceID: str(l.referenceInstanceID) }
        : {}),
    };
    const { boarding, alighting } = stations(leg);
    if (
      !boarding?.departure ||
      !alighting?.arrival ||
      boarding.index >= alighting.index ||
      epoch(alighting.arrival.scheduled)! < epoch(boarding.departure.scheduled)!
    )
      throw new APIError(400, "invalid_station_order");
    return leg;
  });
  if (new Set(legs.map(leg => leg.id)).size !== legs.length)
    throw new APIError(400, "duplicate_leg_id");
  for (let i = 1; i < legs.length; i++)
    if (legs[i - 1].alightingCode !== legs[i].boardingCode)
      throw new APIError(400, "different_connection_station");
  const minutes = int(j.travelToStationMinutes, 0, 1440);
  if (minutes % 15) throw new APIError(400, "invalid_travel_minutes");
  return {
    id: str(j.id),
    title: typeof j.title === "string" ? j.title.slice(0, 200) : "",
    createdAt: int(j.createdAt, 0, 4e10),
    legs,
    travelToStationMinutes: minutes,
    currentLegIndex: int(j.currentLegIndex, 0, legs.length - 1),
    manualPhase: j.manualPhase as Journey["manualPhase"],
    completed: j.completed as boolean,
    trackingEnded: j.trackingEnded as boolean,
    syncChoice: j.syncChoice as Journey["syncChoice"],
    pendingScheduleChange: j.pendingScheduleChange as boolean,
    scheduleChangePrompted: j.scheduleChangePrompted as boolean,
  };
}
