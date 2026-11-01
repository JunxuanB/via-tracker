// Shared scenario edits for local and public test consoles. No network or credentials.
import { normalize, trainNumberFromKey } from "./normalize.ts";
export class TestDataError extends Error {}
export type Event = { scheduled: string; estimated?: string };
export type Stop = { station: string; code: string; tz: string; eta?: string; arrival?: Event; departure?: Event; [key: string]: unknown };
export type Train = { instance: string; times: Stop[]; from: string; to: string; departed: boolean; arrived: boolean;
  lat?: number; lng?: number; speed?: number; direction?: number; poll?: string; alerts?: unknown[]; [key: string]: unknown };
export type Feed = Record<string, Train>;
export type Mode = 'healthy' | 'stale' | 'unavailable' | 'empty' | 'failure';
export const modes: Mode[] = ['healthy', 'stale', 'unavailable', 'empty', 'failure'];
function validDate(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const time = Date.parse(value + 'T12:00:00Z');
  return Number.isFinite(time) && new Date(time).toISOString().slice(0, 10) === value;
}
/** Upgrade legacy keys without changing service dates, schedules or saved journey IDs. */
export function datedFeed(raw: Feed): Feed {
  const result: Feed = {};
  for (const [key, train] of Object.entries(raw)) {
    const number = trainNumberFromKey(key);
    if (!number || !train || !validDate(train.instance)) throw new TestDataError('车次号或始发日期无效');
    const id = `${number}:${train.instance}`;
    if (key.includes(':') && key !== id) throw new TestDataError('车次标识与始发日期不一致');
    if (Object.hasOwn(result, id)) throw new TestDataError(`VIA ${number} 在 ${train.instance} 已有一班，不能重复导入`);
    result[id] = train;
  }
  return result;
}
/** Move the origin's wall clock to a calendar date, preserving elapsed route durations. */
function departureOnDate(first: number, date: string, zone: string): number {
  const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric',
    month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
  const wall = (time: number) => {
    const parts = Object.fromEntries(formatter.formatToParts(time).map(part => [part.type, part.value]));
    return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}`;
  };
  const wanted = date + wall(first).slice(10);
  const naive = Date.parse(wanted + 'Z');
  const offsets = new Set<number>();
  for (const hours of [-36, -12, 0, 12, 36]) {
    const probe = naive + hours * 3600000;
    offsets.add(Date.parse(wall(probe) + 'Z') - probe);
  }
  const matches = [...offsets].map(offset => naive - offset).filter(time => wall(time) === wanted);
  if (matches.length !== 1) throw new TestDataError('该日发车时间处于夏令时跳变或重复时段，请先调整模板的计划发车时间');
  return matches[0];
}
function copyDate(raw: Feed, date: unknown, sourceDate: unknown): Feed {
  if (!validDate(date)) throw new TestDataError('请选择有效的始发日期');
  if (sourceDate !== 'latest' && !validDate(sourceDate)) throw new TestDataError('请选择复制来源');
  const next = structuredClone(raw);
  const templates = new Map<string, Train>();
  for (const [key, train] of Object.entries(raw).sort((a, b) => a[1].instance.localeCompare(b[1].instance))) {
    if (sourceDate === 'latest' || train.instance === sourceDate) templates.set(trainNumberFromKey(key)!, train);
  }
  if (!templates.size) throw new TestDataError('来源日期没有可复制的车次');
  let added = 0;
  for (const [number, original] of templates) {
    const key = `${number}:${date}`;
    if (Object.hasOwn(next, key)) continue;
    const train = structuredClone(original);
    const first = train.times[0]?.departure;
    if (!first) throw new TestDataError(`VIA ${number} 缺少始发站计划发车时间`);
    const before = Date.parse(first.scheduled);
    const delta = departureOnDate(before, date, train.times[0].tz) - before;
    for (const stop of train.times) {
      delete stop.estimated; delete stop.scheduled; delete stop.diff; delete stop.diffMin;
      stop.eta = '';
      for (const event of [stop.arrival, stop.departure]) if (event) {
        event.scheduled = iso(Date.parse(event.scheduled) + delta);
        delete event.estimated;
      }
    }
    train.instance = date;
    train.departed = false; train.arrived = false; train.speed = 0;
    train.alerts = []; train.poll = iso(Date.now());
    next[key] = train;
    added++;
  }
  if (!added) throw new TestDataError('所选日期已有这些车次，未覆盖任何已有修改');
  return validate(next);
}
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
function simulateDeparture(train: Train, action: 'departSoon' | 'departNow' | 'riding', value: unknown = 0) {
  const index = Number(value);
  const stop = train.times[index];
  if (!Number.isInteger(index) || index < 0 || index >= train.times.length - 1 || !stop?.departure) {
    throw new TestDataError('请选择有后续停站的上车站');
  }
  const departure = Date.parse(stop.departure.estimated ?? stop.departure.scheduled);
  const nextArrival = train.times.slice(index + 1).find(call => call.arrival)?.arrival;
  const remaining = nextArrival ? Date.parse(nextArrival.estimated ?? nextArrival.scheduled) - departure : 0;
  if (!Number.isFinite(remaining) || remaining <= 0) throw new TestDataError('后续到达时间必须晚于所选站发车时间，请先检查站点时刻');
  // Move before now, but not beyond the next possible alighting stop on a short journey.
  const elapsed = action === 'riding' ? Math.min(600_000, remaining / 2) : Math.min(1000, remaining / 2);
  const target = Date.now() + (action === 'departSoon' ? 120_000 : -elapsed);
  shift(train, target - departure, true);
  train.departed = action !== 'departSoon' || index > 0;
  train.arrived = false;
  train.times.forEach((call, i) => { call.eta = i < index || (i === index && action !== 'departSoon') ? 'ARR' : ''; });
  train.speed = action === 'departSoon' ? 0 : 80;
  train.poll = iso(Date.now());
}
function markArrived(train: Train) {
  train.arrived = true; train.departed = true; train.speed = 0;
  train.times.forEach(stop => { stop.eta = 'ARR'; });
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
  return datedFeed(result);
}
export function validate(value: unknown): Feed {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TestDataError('请输入车次对象');
  const feed = datedFeed(value as Feed);
  const entries = Object.entries(feed);
  if (!entries.length || entries.length > 300) throw new TestDataError('需要 1–300 个车次');
  for (const [key, train] of entries) {
    if (!trainNumberFromKey(key) || !train || !Array.isArray(train.times) || train.times.length < 2 || train.times.length > 300) {
      throw new TestDataError('车次编号或站点数量无效');
    }
    if (typeof train.departed !== 'boolean' || typeof train.arrived !== 'boolean') throw new TestDataError('运行状态必须是 true 或 false');
    if ((train.lat == null) !== (train.lng == null)) throw new TestDataError('纬度与经度需要同时提供或同时留空');
    for (const [field, min, max] of [['lat', -90, 90], ['lng', -180, 180], ['speed', 0, 400], ['direction', 0, 359.999]] as const) {
      const value = train[field];
      if (value != null && (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max)) throw new TestDataError(`${field} 的数值超出范围`);
    }
    for (const stop of train.times) {
      for (const event of [stop.arrival, stop.departure]) {
        if (!event) continue;
        for (const value of [event.scheduled, event.estimated].filter(v => v !== undefined)) {
          if (typeof value !== 'string' || !/(Z|[+-]\d{2}:\d{2})$/.test(value) || !Number.isFinite(Date.parse(value))) throw new TestDataError('时间无效，请使用带时区的 ISO 8601 格式');
        }
      }
    }
  }
  const trains = normalize(feed, iso(Date.now()), Date.now());
  if (trains.length !== entries.length || new Set(trains.map(t => t.id)).size !== trains.length) throw new TestDataError('存在无效或重复的车次');
  trains.forEach((train, index) => {
    if (train.calls.length !== entries[index][1].times.length) throw new TestDataError('站点时间必须包含时区，例如 2026-11-06T14:00:00-05:00');
  });
  return feed;
}
export function editTrain(raw: Feed, body: Record<string, unknown>): Feed {
  const action = String(body.action);
    raw = datedFeed(raw);
    if (action === 'createDate') return copyDate(raw, body.date, body.sourceDate);
    const key = String(body.key);
    if (!Object.hasOwn(raw, key)) throw new TestDataError('找不到车次');
    const next = structuredClone(raw);
    const train = next[key];
    if (action === 'replace') {
      if (!body.train || (body.train as Train).instance !== train.instance) {
        throw new TestDataError('不能直接改写班次日期。请先在左侧选择日期，再复制该日车次；原班次会保留');
      }
      next[key] = body.train as Train;
      // Old pages and JSON edits changed only a flag, leaving the departure time in the future.
      if (next[key].arrived && !train.arrived) markArrived(next[key]);
      else if (next[key].departed && !train.departed && !next[key].arrived) {
        simulateDeparture(next[key], 'departNow', body.index ?? 0);
      }
    } else if (action === 'delay') {
      const minutes = Number(body.minutes);
      if (!Number.isFinite(minutes) || Math.abs(minutes) > 1440) throw new TestDataError('延误范围为 -1440 至 1440 分钟');
      for (const stop of train.times.filter(stop => stop.eta !== 'ARR')) {
        for (const event of [stop.arrival, stop.departure]) if (event) event.estimated = iso(Date.parse(event.estimated ?? event.scheduled) + minutes * 60_000);
      }
    } else if (action === 'departSoon' || action === 'departNow' || action === 'riding') {
      simulateDeparture(train, action, body.index ?? 0);
    } else if (action === 'arrivalSoon') {
      // Keep the identity unchanged so an already saved journey follows the edits.
      const event = train.times.at(-1)?.arrival;
      if (!event) throw new TestDataError('缺少始发或终到时间');
      const delta = Date.now() + 30_000 - Date.parse(event.estimated ?? event.scheduled);
      shift(train, delta, true);
      train.departed = true; train.arrived = false;
      train.times.forEach(stop => { stop.eta = ''; });
      if (train.departed) train.times[0].eta = 'ARR';
      train.speed = train.departed ? 80 : 0;
    } else if (action === 'reached') {
      const index = Number(body.index);
      if (!Number.isInteger(index) || index < 0 || index >= train.times.length) throw new TestDataError('请选择车站');
      train.times.forEach((stop, i) => { stop.eta = i <= index ? 'ARR' : ''; });
      train.departed = true; train.arrived = index === train.times.length - 1;
      if (train.arrived) train.speed = 0;
    } else if (action === 'arrived') {
      markArrived(train);
    } else if (action === 'noPosition') {
      delete train.lat; delete train.lng; delete train.speed; delete train.direction; delete train.poll;
    } else if (action === 'oldPosition') {
      train.poll = iso(Date.now() - 30 * 60_000);
    } else if (action === 'freshPosition') {
      train.poll = iso(Date.now());
    } else throw new TestDataError('未知操作');
    return validate(next);
}
