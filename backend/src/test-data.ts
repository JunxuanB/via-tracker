// Shared scenario edits for local and public test consoles. No network or credentials.
import { normalize } from "./normalize.ts";
export type Event = { scheduled: string; estimated?: string };
export type Stop = { station: string; code: string; tz: string; eta?: string; arrival?: Event; departure?: Event; [key: string]: unknown };
export type Train = { instance: string; times: Stop[]; from: string; to: string; departed: boolean; arrived: boolean;
  lat?: number; lng?: number; speed?: number; direction?: number; poll?: string; alerts?: unknown[]; [key: string]: unknown };
export type Feed = Record<string, Train>;
export type Mode = 'healthy' | 'stale' | 'unavailable' | 'empty' | 'failure';
export const modes: Mode[] = ['healthy', 'stale', 'unavailable', 'empty', 'failure'];
function iso(milliseconds: number) { return new Date(milliseconds).toISOString(); }
function serviceDate(time: number, zone: string) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(time);
}
function shift(train: Train, milliseconds: number, estimatedOnly = false) {
  for (const call of train.times) {
    for (const kind of ['arrival', 'departure'] as const) {
      const event = call[kind];
      if (!event) continue;
      if (!estimatedOnly) event.scheduled = iso(Date.parse(event.scheduled) + milliseconds);
      event.estimated = iso(Date.parse(event.estimated ?? event.scheduled) + (estimatedOnly || event.estimated ? milliseconds : 0));
    }
  }
}
export function seed(sample: Feed): Feed {
  const result: Feed = {};
  // One service per number avoids duplicate IDs after moving historical examples to today.
  for (const [key, original] of Object.entries(sample).sort((a, b) => a[1].instance.localeCompare(b[1].instance))) {
    const number = key.match(/^\d+/)?.[0];
    const first = original.times[0]?.departure;
    if (!number || !first) continue;
    const train = structuredClone(original);
    const start = Math.ceil((Date.now() + 20 * 60_000) / 60_000) * 60_000;
    for (const stop of train.times) {
      delete stop.estimated; delete stop.scheduled; delete stop.diff; delete stop.diffMin;
      stop.eta = '';
      for (const event of [stop.arrival, stop.departure]) if (event) event.estimated = event.scheduled;
    }
    shift(train, start - Date.parse(first.scheduled));
    train.instance = serviceDate(start, train.times[0].tz);
    train.departed = false; train.arrived = false; train.alerts = [];
    train.speed = 0; train.poll = iso(Date.now());
    result[number] = train;
  }
  return result;
}
export function validate(value: unknown): Feed {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('请输入车次对象');
  const feed = value as Feed;
  const entries = Object.entries(feed);
  if (!entries.length || entries.length > 300) throw new Error('需要 1–300 个车次');
  for (const [key, train] of entries) {
    if (!/^\d+(?:\s+\(\d{2}-\d{2}\))?$/.test(key) || !train || !Array.isArray(train.times) || train.times.length < 2 || train.times.length > 300) {
      throw new Error('车次编号或站点数量无效');
    }
    if (typeof train.departed !== 'boolean' || typeof train.arrived !== 'boolean') throw new Error('运行状态必须是 true 或 false');
    if ((train.lat == null) !== (train.lng == null)) throw new Error('纬度与经度需要同时提供或同时留空');
    for (const [field, min, max] of [['lat', -90, 90], ['lng', -180, 180], ['speed', 0, 400], ['direction', 0, 359.999]] as const) {
      const value = train[field];
      if (value != null && (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max)) throw new Error(`${field} 的数值超出范围`);
    }
    for (const stop of train.times) {
      for (const event of [stop.arrival, stop.departure]) {
        if (!event) continue;
        for (const value of [event.scheduled, event.estimated].filter(v => v !== undefined)) {
          if (typeof value !== 'string' || !/(Z|[+-]\d{2}:\d{2})$/.test(value) || !Number.isFinite(Date.parse(value))) throw new Error('时间无效，请使用带时区的 ISO 8601 格式');
        }
      }
    }
  }
  const trains = normalize(feed, iso(Date.now()), Date.now());
  if (trains.length !== entries.length || new Set(trains.map(t => t.id)).size !== trains.length) throw new Error('存在无效或重复的车次');
  trains.forEach((train, index) => {
    if (train.calls.length !== entries[index][1].times.length) throw new Error('站点时间必须包含时区，例如 2026-11-06T14:00:00-05:00');
  });
  return feed;
}
export function editTrain(raw: Feed, body: Record<string, unknown>): Feed {
  const action = String(body.action);
    const key = String(body.key);
    if (!Object.hasOwn(raw, key)) throw new Error('找不到车次');
    const next = structuredClone(raw);
    const train = next[key];
    if (action === 'replace') {
      next[key] = body.train as Train;
    } else if (action === 'delay') {
      const minutes = Number(body.minutes);
      if (!Number.isFinite(minutes) || Math.abs(minutes) > 1440) throw new Error('延误范围为 -1440 至 1440 分钟');
      for (const stop of train.times.filter(stop => stop.eta !== 'ARR')) {
        for (const event of [stop.arrival, stop.departure]) if (event) event.estimated = iso(Date.parse(event.estimated ?? event.scheduled) + minutes * 60_000);
      }
    } else if (action === 'departSoon' || action === 'riding' || action === 'arrivalSoon') {
      // Keep the identity unchanged so an already saved journey follows the edits.
      const event = action === 'arrivalSoon' ? train.times.at(-1)?.arrival : train.times[0]?.departure;
      if (!event) throw new Error('缺少始发或终到时间');
      const delta = Date.now() + (action === 'riding' ? -10 * 60_000 : action === 'arrivalSoon' ? 30_000 : 2 * 60_000) - Date.parse(event.estimated ?? event.scheduled);
      shift(train, delta, true);
      train.departed = action !== 'departSoon'; train.arrived = false;
      train.times.forEach(stop => { stop.eta = ''; });
      if (train.departed) train.times[0].eta = 'ARR';
      train.speed = train.departed ? 80 : 0;
    } else if (action === 'reached') {
      const index = Number(body.index);
      if (!Number.isInteger(index) || index < 0 || index >= train.times.length) throw new Error('请选择车站');
      train.times.forEach((stop, i) => { stop.eta = i <= index ? 'ARR' : ''; });
      train.departed = true; train.arrived = index === train.times.length - 1;
      if (train.arrived) train.speed = 0;
    } else if (action === 'arrived') {
      train.arrived = true; train.departed = true; train.speed = 0;
      train.times.forEach(stop => { stop.eta = 'ARR'; });
    } else if (action === 'noPosition') {
      delete train.lat; delete train.lng; delete train.speed; delete train.direction; delete train.poll;
    } else if (action === 'oldPosition') {
      train.poll = iso(Date.now() - 30 * 60_000);
    } else if (action === 'freshPosition') {
      train.poll = iso(Date.now());
    } else throw new Error('未知操作');
    return validate(next);
}
