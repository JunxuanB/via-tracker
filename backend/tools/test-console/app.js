'use strict';
const $ = id => document.getElementById(id);
let state, selected, draft, dirty = false, busy = false, polling = false, jsonDirty = false;
let entries = [], deviceSignature = '', deliverySignature = '';
const scenarioStations = new Map();
const validDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value || '') && Number.isFinite(Date.parse(value + 'T12:00:00Z'))
  && new Date(value + 'T12:00:00Z').toISOString().slice(0, 10) === value;
const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Toronto', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const initialURL = new URL(location.href);
let selectedDate = validDate(initialURL.searchParams.get('date')) ? initialURL.searchParams.get('date') : today();
let preferredNumber = initialURL.searchParams.get('train') || '14';
const numberOf = key => key?.match(/^\d+/)?.[0] || '';
const names = { delay: '延误已应用', departSoon: '已调整为 2 分钟后发车', riding: '已设为正在途中', arrivalSoon: '已调整为 30 秒后到达终点', arrived: '已标记到达终点', reached: '到站状态已更新', noPosition: '已移除定位', oldPosition: '定位已设为 30 分钟前', freshPosition: '定位时间已更新', replace: '车次修改已保存', mode: '数据连接状态已更新', reset: '示例已重置为当前时间', undo: '已撤销上次修改', import: '数据已导入' };
names.departNow = '已设为从所选站发车';
const fold = v => v.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/quebec city|ville de quebec/g, 'quebec');
function message(text, kind = '') { $('message').textContent = text; $('message').className = kind; }
function changed() {
  dirty = true; $('save').disabled = busy || !draft;
  if (!jsonDirty && draft) $('json').value = JSON.stringify(collectDraft(), null, 2);
  message('有未保存的修改 · 点击“保存修改”后 App 才会读取。', 'pending');
}
function discardOK() { return !dirty || window.confirm('当前车次有未保存修改，放弃这些修改？'); }
async function request(path, options) {
  const response = await fetch(path, { cache: 'no-store', signal: AbortSignal.timeout(20000), ...options });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error?.message || data.error?.code || '请求失败');
  return data;
}
function setBusy(value) {
  busy = value;
  document.querySelectorAll('button, input, select, textarea').forEach(control => { control.disabled = value; });
  if (!value) {
    $('save').disabled = !dirty || !draft;
    $('undo').disabled = !state?.undoCount;
    $('exportDraft').disabled = !draft;
    for (const control of document.querySelectorAll('[data-action="departSoon"], [data-action="departNow"], [data-action="riding"]')) {
      control.disabled = !draft || !$('scenarioStation').options.length;
    }
  }
  if (state?.public) remoteStatus(state);
}
function connection(info) {
  $('connection').textContent = info.lastRead ? `最近读取 ${new Date(info.lastRead).toLocaleTimeString()} · ${info.feedReads} 次` : '尚未收到 App 请求';
}
async function load() {
  state = await request('/control/state');
  entries = Object.entries(state.raw).map(([key, train]) => ({ key, train, number: numberOf(key),
    text: fold([numberOf(key), train.from, train.to, ...train.times.flatMap(stop => [stop.station, stop.code])].join(' ')) }))
    .sort((a, b) => Number(a.number) - Number(b.number));
  $('mode').value = state.mode;
  connection(state); remoteStatus(state); renderDates(); chooseDateTrain(); renderList();
}
function rememberSelection() {
  const url = new URL(location.href);
  url.searchParams.set('date', selectedDate);
  if (selected) url.searchParams.set('train', numberOf(selected)); else url.searchParams.delete('train');
  history.replaceState(null, '', url);
}
function renderDates() {
  const dates = [...new Set(entries.map(entry => entry.train.instance))].sort().reverse();
  $('serviceDate').value = selectedDate;
  const previousSource = $('copySource').value || 'latest';
  $('availableDates').replaceChildren(new Option('选择已有日期…', ''));
  $('copySource').replaceChildren(new Option('全部已有线路（每车最新一班）', 'latest'));
  for (const date of dates) {
    const count = entries.filter(entry => entry.train.instance === date).length;
    $('availableDates').add(new Option(`${date} · ${count} 班`, date));
    $('copySource').add(new Option(date, date));
  }
  $('availableDates').value = dates.includes(selectedDate) ? selectedDate : '';
  $('copySource').value = dates.includes(previousSource) ? previousSource : 'latest';
  const hasDate = dates.includes(selectedDate);
  $('emptyDate').hidden = hasDate;
  $('emptyDateTitle').textContent = `${selectedDate} 还没有测试车次`;
  $('createDate').textContent = hasDate ? '补齐这天缺少的车次' : '创建这天的测试车次';
}
function chooseDateTrain() {
  const choices = entries.filter(entry => entry.train.instance === selectedDate);
  selectTrain(choices.find(entry => entry.key === selected)?.key
    || choices.find(entry => entry.number === preferredNumber)?.key || choices[0]?.key);
}
function changeDate(date) {
  if (busy || !validDate(date) || !discardOK()) { $('serviceDate').value = selectedDate; $('availableDates').value = selectedDate; return; }
  selectedDate = date; dirty = false;
  renderDates(); chooseDateTrain(); renderList(); setBusy(false);
  message(`已选择 ${date} · 日期按始发站当地时间计算。`);
}
async function action(action, extra = {}, discard = true) {
  if (busy || (discard && !discardOK())) return;
  setBusy(true);
  try {
    await request('/control', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-VIA-Test': '1' }, body: JSON.stringify({ action, key: selected, revision: state.revision, index: Number($('scenarioStation').value), ...extra }) });
    dirty = false;
    await load();
    message((names[action] || '已更新') + (state.public ? ' · 已安排后台更新，可锁屏查看推送。' : ' · 回到 App 等待自动刷新或下拉刷新。'));
  } catch (error) { message(error.message, 'error'); }
  finally { setBusy(false); }
}
function renderList() {
  const query = fold($('search').value).trim().split(/\s+/).filter(Boolean);
  const matches = entries.filter(entry => entry.train.instance === selectedDate && query.every(word => entry.text.includes(word)));
  $('count').textContent = `${selectedDate} · ${matches.length} 班${query.length ? '匹配' : ''}`;
  const fragment = document.createDocumentFragment();
  matches.forEach(({ key, train, number }) => {
    const button = document.createElement('button');
    button.className = 'train-option' + (key === selected ? ' selected' : '');
    button.setAttribute('aria-pressed', String(key === selected));
    const title = document.createElement('strong'); title.textContent = 'VIA ' + number;
    const route = document.createElement('span'); route.textContent = train.from + ' → ' + train.to;
    button.append(title, route);
    button.addEventListener('click', () => { if (!busy && key !== selected && discardOK()) { selectTrain(key); renderList(); setBusy(false); message(`已选择 ${selectedDate} · VIA ${number}`); } });
    fragment.append(button);
  });
  if (!matches.length) {
    const empty = document.createElement('p'); empty.className = 'muted';
    empty.textContent = query.length ? '当天没有匹配车次，试试车次号或清空搜索。' : '当天暂无数据，可在上方添加。';
    fragment.append(empty);
  }
  $('trains').replaceChildren(fragment);
}
function selectTrain(key) {
  selected = key; draft = key ? structuredClone(state.raw[key]) : undefined; dirty = false; jsonDirty = false;
  if (key) preferredNumber = numberOf(key);
  rememberSelection();
  $('editor').hidden = !draft;
  if (!draft) return;
  $('trainId').textContent = `${draft.instance} · VIA ${numberOf(key)}`;
  $('route').textContent = `${draft.from} → ${draft.to}`;
  $('instance').textContent = draft.instance;
  ['lat', 'lng', 'speed', 'direction', 'poll'].forEach(field => { $(field).value = draft[field] ?? ''; });
  $('runningState').textContent = draft.arrived ? '列车已到达终点' : draft.departed ? '列车已发车' : '列车尚未发车';
  const stationOptions = draft.times.flatMap((stop, index) => stop.departure && index < draft.times.length - 1
    ? [new Option(`${index + 1}. ${stop.station} · ${stop.code}`, String(index))] : []);
  $('scenarioStation').replaceChildren(...stationOptions);
  const remembered = scenarioStations.get(key);
  $('scenarioStation').value = stationOptions.some(option => option.value === remembered) ? remembered : stationOptions[0]?.value ?? '';
  $('json').value = JSON.stringify(draft, null, 2);
  renderStops();
}
function renderStops() {
  const fragment = document.createDocumentFragment();
  draft.times.forEach((stop, index) => {
    const events = ['arrival', 'departure'].filter(kind => stop[kind]);
    events.forEach((kind, eventIndex) => {
      const row = document.createElement('tr');
      if (!eventIndex) {
        const name = document.createElement('td'); name.rowSpan = events.length; name.className = 'station-name';
        name.append(document.createTextNode(`${index + 1}. ${stop.station}`));
        const zone = document.createElement('small'); zone.textContent = stop.code + ' · ' + stop.tz; name.append(zone); row.append(name);
      }
      const eventName = document.createElement('td'); eventName.textContent = kind === 'arrival' ? '到达' : '发车'; row.append(eventName);
      ['scheduled', 'estimated'].forEach(field => {
        const cell = document.createElement('td'), input = document.createElement('input');
        input.type = 'text'; input.value = stop[kind][field] ?? ''; input.placeholder = field === 'estimated' ? '空白表示暂无预计时间' : 'ISO 8601 · 必须包含时区';
        input.setAttribute('aria-label', `${stop.station} ${kind === 'arrival' ? '到达' : '发车'}${field === 'scheduled' ? '计划' : '预计'}时间`);
        input.addEventListener('input', () => { if (!input.value && field === 'estimated') delete stop[kind][field]; else stop[kind][field] = input.value.trim(); changed(); });
        cell.append(input); row.append(cell);
      });
      if (!eventIndex) {
        const cell = document.createElement('td'); cell.rowSpan = events.length;
        const label = document.createElement('label'), checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.checked = stop.eta === 'ARR';
        checkbox.addEventListener('change', () => { stop.eta = checkbox.checked ? 'ARR' : ''; changed(); });
        label.append(checkbox, document.createTextNode('已到站'));
        const button = document.createElement('button'); button.className = 'stop-action'; button.textContent = '到达此站';
        button.addEventListener('click', () => action('reached', { index }));
        cell.append(label, button); row.append(cell);
      }
      fragment.append(row);
    });
  });
  $('stops').replaceChildren(fragment);
}
function collectDraft() {
  const result = structuredClone(draft);
  ['lat', 'lng', 'speed', 'direction'].forEach(field => {
    if ($(field).value === '') delete result[field]; else result[field] = Number($(field).value);
  });
  if ($('poll').value.trim()) result.poll = $('poll').value.trim(); else delete result.poll;
  return result;
}
$('search').addEventListener('input', () => { if (state) renderList(); });
['lat', 'lng', 'speed', 'direction', 'poll'].forEach(field => $(field).addEventListener('input', changed));
$('scenarioStation').addEventListener('change', () => scenarioStations.set(selected, $('scenarioStation').value));
$('json').addEventListener('input', () => { jsonDirty = true; changed(); });
$('serviceDate').addEventListener('change', () => changeDate($('serviceDate').value));
$('availableDates').addEventListener('change', () => changeDate($('availableDates').value));
$('today').addEventListener('click', () => changeDate(today()));
for (const [id, delta] of [['previousDate', -1], ['nextDate', 1]]) $(id).addEventListener('click', () => {
  const date = new Date(selectedDate + 'T12:00:00Z'); date.setUTCDate(date.getUTCDate() + delta);
  changeDate(date.toISOString().slice(0, 10));
});
$('createDate').addEventListener('click', () => action('createDate', { date: selectedDate, sourceDate: $('copySource').value }));
names.createDate = '当天缺少的车次已添加，原有班次保持不变';
$('reload').addEventListener('click', async () => {
  if (busy || !discardOK()) return;
  setBusy(true);
  try { await load(); message('已读取最新数据。'); } catch (error) { message(error.message, 'error'); }
  finally { setBusy(!state); }
});
$('exportDraft').addEventListener('click', () => {
  const content = jsonDirty ? $('json').value : JSON.stringify(collectDraft(), null, 2);
  const url = URL.createObjectURL(new Blob([content], { type: 'application/json' }));
  const link = document.createElement('a'); link.href = url; link.download = `via-${numberOf(selected)}-${selectedDate}-draft.json`; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
window.addEventListener('beforeunload', event => { if (dirty) { event.preventDefault(); event.returnValue = ''; } });
function saveDraft(useJSON = jsonDirty) {
  try { action('replace', { train: useJSON ? JSON.parse($('json').value) : collectDraft() }, false); }
  catch { message('JSON 格式有误，修改尚未保存。', 'error'); }
}
$('save').addEventListener('click', () => saveDraft());
$('jsonApply').addEventListener('click', () => saveDraft(true));
document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', () => action(button.dataset.action)));
$('delayApply').addEventListener('click', () => action('delay', { minutes: Number($('delay').value) }));
$('mode').addEventListener('change', async () => { await action('mode', { mode: $('mode').value }); $('mode').value = state.mode; });
$('reset').addEventListener('click', () => { if (window.confirm('这会替换所有日期的测试班次。仅需添加另一天时，请使用“添加这天的车次”。确定重置全部数据？')) action('reset'); });
$('undo').addEventListener('click', () => action('undo'));
$('import').addEventListener('change', async () => {
  const file = $('import').files[0]; if (!file) return;
  try {
    if (file.size > 1_400_000) throw new Error('JSON 文件不能超过 1.4 MB');
    await action('import', { raw: JSON.parse(await file.text()) });
  } catch (error) { message(error.message, 'error'); }
  $('import').value = '';
});
$('serverURL').textContent = location.origin;
setBusy(true);
load().then(() => message('准备就绪 · 先选始发日期，再选择当天车次。'))
  .catch(error => message('测试台未连接：' + error.message, 'error'))
  .finally(() => setBusy(!state));
setInterval(async () => {
  if (busy || polling || document.hidden || !state) return;
  polling = true;
  try {
    const status = await request('/control/status');
    if (busy) return;
    connection(status); remoteStatus(status);
    if (status.revision !== state.revision) {
      if (dirty) message('另一个页面修改了数据。请下载当前草稿，再点击“重新读取数据”。', 'pending');
      else {
        setBusy(true);
        try { await load(); message('已同步另一个页面的修改。'); } finally { setBusy(false); }
      }
    }
  } catch { $('connection').textContent = '暂时无法连接 · 将自动重试'; }
  finally { polling = false; }
}, 3000);

function remoteStatus(info) {
  if (!info.public) return;
  if (state) Object.assign(state, { public: true, pushConfigured: info.pushConfigured, devices: info.devices, deliveries: info.deliveries });
  $('setup').hidden = true; $('publicSetup').hidden = false; $('pushPanel').hidden = false;
  $('footerNote').textContent = '公网测试数据持久保存，重启服务不会重置。面板无需登录且多人共享；正式 VIA 数据与日常行程独立。';
  $('pushState').textContent = info.pushConfigured ? '推送服务已配置。按 App 环境面板中的设备编号找到你的手机。' : '数据服务可用，推送密钥尚未配置。';
  const nextDeviceSignature = JSON.stringify([info.devices, busy, info.pushConfigured]);
  if (deviceSignature !== nextDeviceSignature) {
  deviceSignature = nextDeviceSignature;
  const devices = document.createDocumentFragment();
  for (const device of info.devices || []) {
    const row = document.createElement('div'); row.className = 'device-row';
    const label = document.createElement('span');
    label.textContent = `${device.code} · ${device.activities} 个实时活动 · ${device.environment === 'sandbox' ? '开发签名' : '发布签名'}`;
    const button = document.createElement('button'); button.textContent = device.notifications ? '发送测试通知' : '尚未允许普通通知';
    button.disabled = busy || !device.notifications || !info.pushConfigured;
    button.addEventListener('click', () => pushAction('/control/notify', { code: device.code }));
    row.append(label, button); devices.append(row);
  }
  if (!info.devices?.length) { const text = document.createElement('p'); text.textContent = '尚未连接测试设备。请先在 App 进入测试环境并允许通知。'; devices.append(text); }
  $('devices').replaceChildren(devices);
  }
  const nextDeliverySignature = JSON.stringify(info.deliveries);
  if (deliverySignature === nextDeliverySignature) return;
  deliverySignature = nextDeliverySignature;
  const logs = document.createDocumentFragment();
  for (const log of info.deliveries || []) {
    const row = document.createElement('p'); row.className = 'delivery-row';
    row.textContent = `${new Date(log.sent_at).toLocaleTimeString()} · ${log.device_code} · ${log.kind === 'activity' ? '实时活动' : log.kind === 'widget' ? '小组件刷新' : '普通通知'} · ${log.accepted ? 'Apple 已接收' : '未接收：' + (log.reason || '未知原因')}`;
    logs.append(row);
  }
  if (!info.deliveries?.length) { const text = document.createElement('p'); text.className = 'muted'; text.textContent = '尚无推送记录'; logs.append(text); }
  $('deliveries').replaceChildren(logs);
}
async function pushAction(path, body = {}) {
  if (busy) return; setBusy(true);
  try {
    const result = await request(path, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-VIA-Test': '1' }, body: JSON.stringify(body) });
    message(result.message, result.ok ? '' : 'error');
    remoteStatus(await request('/control/status'));
  } catch (error) { message(error.message, 'error'); }
  finally { setBusy(false); }
}
$('pushNow').addEventListener('click', () => pushAction('/control/push'));
