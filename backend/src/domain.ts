export type Phase =
  | "beforeDeparture"
  | "onTheWay"
  | "waiting"
  | "riding"
  | "transferring"
  | "completed";
export interface EventTime {
  scheduled: string;
  estimated?: string;
}
export interface StationCall {
  index: number;
  code: string;
  name: string;
  timeZone: string;
  arrival?: EventTime;
  departure?: EventTime;
  reached?: boolean;
}
export interface TrainSnapshot {
  id: string;
  trainNumber: string;
  originServiceDate: string;
  rawKey: string;
  from: string;
  to: string;
  departed: boolean;
  arrived: boolean;
  calls: StationCall[];
  sourceFetchedAt: string;
  version: number;
  position?: { latitude: number; longitude: number; reportedAt?: string; speedKmh?: number; heading?: number };
  alerts: { title: string; body: string; url?: string }[];
  qualityFlags?: string[];
}
export interface TrainLeg {
  id: string;
  trainNumber: string;
  originServiceDate: string;
  boardingCode: string;
  boardingIndex: number;
  alightingCode: string;
  alightingIndex: number;
  planningDeparture: number;
  source: "official" | "reference";
  referenceInstanceID?: string;
  snapshot: TrainSnapshot;
}
export interface Journey {
  id: string;
  title: string;
  createdAt: number;
  legs: TrainLeg[];
  travelToStationMinutes: number;
  currentLegIndex: number;
  manualPhase?: Phase;
  completed: boolean;
  trackingEnded: boolean;
  syncChoice: "ask" | "keep" | "automatic";
  pendingScheduleChange: boolean;
  scheduleChangePrompted: boolean;
}
export interface ActivityState {
  phase: Phase;
  trainNumber: string;
  destination: string;
  origin: string;
  targetEpoch: number;
  scheduledEpoch: number;
  sourceFetchedEpoch: number;
  validUntilEpoch: number;
  progress: number;
  currentLegIndex: number;
  legCount: number;
  waitingForUpdate: boolean;
  reference: boolean;
  targetIsEstimate: boolean;
  nextTrainNumber?: string;
  nextDepartureEpoch?: number;
  connectionMinutes?: number;
  progressStartEpoch?: number;
}
export const epoch = (s?: string) =>
  s && Number.isFinite(Date.parse(s)) ? Date.parse(s) / 1000 : undefined;
/** Countdowns and the Live Activity begin this long before the planned time to leave home. */
export const TRACKING_LEAD_SECONDS = 5 * 3600;
export const trackingStart = (journey: Journey) =>
  journey.legs[0].planningDeparture - journey.travelToStationMinutes * 60 - TRACKING_LEAD_SECONDS;
export function stations(leg: TrainLeg) {
  return {
    boarding: leg.snapshot.calls.find(
      (s) => s.index === leg.boardingIndex && s.code === leg.boardingCode,
    ),
    alighting: leg.snapshot.calls.find(
      (s) => s.index === leg.alightingIndex && s.code === leg.alightingCode,
    ),
  };
}
export function resolvedJourney(journey: Journey, now: number): Journey {
  const result = { ...journey };
  while (!result.completed) {
    const leg = result.legs[result.currentLegIndex];
    if (!leg) break;
    const { alighting } = stations(leg);
    const arrival = epoch(alighting?.arrival?.estimated) ?? epoch(alighting?.arrival?.scheduled);
    const terminal = leg.source === "official" && leg.snapshot.arrived
      && leg.alightingIndex === leg.snapshot.calls.at(-1)?.index
      && !leg.snapshot.calls.at(-1)?.departure;
    const reportedArrival = leg.source === "official" && alighting?.reached === true;
    if (!terminal && !reportedArrival && (arrival === undefined || now < arrival)) break;
    if (result.currentLegIndex + 1 < result.legs.length) result.currentLegIndex++;
    else result.completed = true;
    delete result.manualPhase;
  }
  return result;
}
export function project(journey: Journey, now: number): ActivityState {
  const j = resolvedJourney(journey, now);
  const i = Math.min(Math.max(j.currentLegIndex, 0), j.legs.length - 1),
    leg = j.legs[i];
  if (!leg) throw new Error("empty_journey");
  const { boarding: b, alighting: a } = stations(leg);
  const dep = epoch(b?.departure?.scheduled) ?? leg.planningDeparture;
  const estDep = epoch(b?.departure?.estimated) ?? dep;
  const arr = epoch(a?.arrival?.scheduled) ?? dep;
  const estArr = epoch(a?.arrival?.estimated) ?? arr;
  const leave = j.legs[0].planningDeparture - j.travelToStationMinutes * 60;
  const manualPhase = (j.manualPhase === "onTheWay" || j.manualPhase === "waiting") && now >= estDep
    ? undefined : j.manualPhase;
  let phase: Phase = j.completed
    ? "completed"
    : (manualPhase ??
      (now >= estDep ? "riding" : i > 0
        ? "transferring"
        : now < leave
          ? "beforeDeparture"
          : now < dep - 900
            ? "onTheWay"
            : "waiting"));
  // Whole-train flags are deliberately not evidence for a selected station event.
  const target =
    phase === "beforeDeparture"
      ? leave
      : phase === "onTheWay" || phase === "transferring"
        ? estDep
        : phase === "waiting"
          ? estDep
          : estArr;
  const sourceFetchedEpoch = epoch(leg.snapshot.sourceFetchedAt) ?? 0;
  const next = j.legs[i + 1],
    nextDepartureEpoch = next
      ? epoch(stations(next).boarding?.departure?.estimated) ?? epoch(stations(next).boarding?.departure?.scheduled)
      : undefined;
  return {
    phase,
    trainNumber: leg.trainNumber,
    destination: a?.name ?? leg.alightingCode,
    origin: b?.name ?? leg.boardingCode,
    targetEpoch: target,
    scheduledEpoch: phase === "beforeDeparture" ? leave : phase === "riding" || phase === "completed" ? arr : dep,
    sourceFetchedEpoch,
    validUntilEpoch: sourceFetchedEpoch + 600,
    progressStartEpoch: estDep,
    progress: Math.min(
      1,
      Math.max(0, (now - estDep) / Math.max(1, estArr - estDep)),
    ),
    currentLegIndex: i,
    legCount: j.legs.length,
    waitingForUpdate: phase !== "completed" && now >= target,
    reference: leg.source === "reference",
    targetIsEstimate:
      phase === "riding"
        ? epoch(a?.arrival?.estimated) !== undefined
        : ["onTheWay", "waiting", "transferring"].includes(phase) && epoch(b?.departure?.estimated) !== undefined,
    ...(next ? { nextTrainNumber: next.trainNumber } : {}),
    ...(nextDepartureEpoch !== undefined
      ? {
          nextDepartureEpoch,
          connectionMinutes: Math.trunc((nextDepartureEpoch - estArr) / 60),
        }
      : {}),
  };
}
export function shouldPush(
  previous: ActivityState | undefined,
  next: ActivityState,
  lastSentAt: number,
  now: number,
) {
  return (
    !previous ||
    previous.phase !== next.phase ||
    previous.currentLegIndex !== next.currentLegIndex ||
    previous.waitingForUpdate !== next.waitingForUpdate ||
    previous.targetEpoch !== next.targetEpoch ||
    previous.progressStartEpoch !== next.progressStartEpoch ||
    previous.nextDepartureEpoch !== next.nextDepartureEpoch ||
    previous.reference !== next.reference ||
    now - lastSentAt >= 300
  );
}
export function reconcile(j: Journey, snapshots: TrainSnapshot[]): Journey {
  const copy: Journey = structuredClone(j);
  for (const leg of copy.legs) {
    const latest = snapshots.find(
      (s) =>
        s.trainNumber === leg.trainNumber &&
        s.originServiceDate === leg.originServiceDate,
    );
    if (!latest || latest.version < leg.snapshot.version) continue;
    const boarding = latest.calls.find(
      (s) => s.code === leg.boardingCode && s.index === leg.boardingIndex,
    );
    const alighting = latest.calls.find(
      (s) => s.code === leg.alightingCode && s.index === leg.alightingIndex,
    );
    if (
      !boarding?.departure ||
      !alighting?.arrival ||
      boarding.index >= alighting.index
    )
      continue;
    const official = epoch(boarding.departure.scheduled)!;
    const wasReference = leg.source === "reference";
    leg.snapshot = latest;
    leg.source = "official";
    if (copy.syncChoice === "automatic") leg.planningDeparture = official;
    else if (
      wasReference &&
      Math.abs(official - leg.planningDeparture) >= 1 &&
      !copy.scheduleChangePrompted
    ) {
      copy.pendingScheduleChange = true;
      copy.scheduleChangePrompted = true;
    }
  }
  return copy;
}
