'use strict';
const $ = id => document.getElementById(id);
let state, selected, draft, dirty = false, busy = false;
const names = { delay: '延误已应用', departSoon: '已调整为 2 分钟后发车', riding: '已设为正在途中', arrivalSoon: '已调整为 30 秒后到达终点', arrived: '已标记到达终点', reached: '到站状态已更新', noPosition: '已移除定位', oldPosition: '定位已设为 30 分钟前', freshPosition: '定位时间已更新', replace: '车次修改已保存', mode: '数据连接状态已更新', reset: '示例已重置为当前时间', undo: '已撤销上次修改', import: '数据已导入' };
const fold = v => v.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/quebec city|ville de quebec/g, 'quebec');
function message(text, kind = '') { $('message').textContent = text; $('message').className = kind; }
function changed() { dirty = true; message('有未保存的修改 · 点击“保存修改”后 App 才会读取。', 'pending'); }
function discardOK() { return !dirty || window.confirm('当前车次有未保存修改，放弃这些修改？'); }
async function request(path, options) {
  const response = await fetch(path, { cache: 'no-store', ...options });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error?.message || data.error?.code || '请求失败');
  return data;
}
function setBusy(value) {
  busy = value;
  document.querySelectorAll('button').forEach(button => { button.disabled = value; });
  $('mode').disabled = value; $('import').disabled = value;
  if (!value && state?.public) remoteStatus(state);
}
function connection(info) {
  $('connection').textContent = info.lastRead ? `最近读取 ${new Date(info.lastRead).toLocaleTimeString()} · ${info.feedReads} 次` : '尚未收到 App 请求';
}
async function load() {
  state = await request('/control/state');
  if (!selected || !state.raw[selected]) selected = state.raw['14'] ? '14' : Object.keys(state.raw)[0];
  $('mode').value = state.mode;
  connection(state); remoteStatus(state); renderList(); selectTrain(selected);
}
async function action(action, extra = {}, discard = true) {
  if (busy || (discard && !discardOK())) return;
  setBusy(true);
  try {
    await request('/control', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-VIA-Test': '1' }, body: JSON.stringify({ action, key: selected, revision: state.revision, ...extra }) });
    await load();
    message((names[action] || '已更新') + (state.public ? ' · 已安排后台更新，可锁屏查看推送。' : ' · 回到 App 等待自动刷新或下拉刷新。'));
  } catch (error) { message(error.message, 'error'); }
  finally { setBusy(false); }
}
function renderList() {
  const query = fold($('search').value).trim().split(/\s+/).filter(Boolean);
  const keys = Object.keys(state.raw).filter(key => {
    const t = state.raw[key];
    const text = fold([key, t.from, t.to, ...t.times.flatMap(s => [s.station, s.code])].join(' '));
    return query.every(word => text.includes(word));
  }).sort((a, b) => parseInt(a) - parseInt(b));
  $('count').textContent = `${keys.length} 个测试车次`;
  const fragment = document.createDocumentFragment();
  keys.forEach(key => {
    const button = document.createElement('button');
    button.className = 'train-option' + (key === selected ? ' selected' : '');
    button.setAttribute('aria-pressed', String(key === selected));
    const title = document.createElement('strong'); title.textContent = 'VIA ' + key;
    const route = document.createElement('span'); route.textContent = state.raw[key].from + ' → ' + state.raw[key].to;
    button.append(title, route);
    button.addEventListener('click', () => { if (!busy && key !== selected && discardOK()) { selectTrain(key); renderList(); message('已选择 VIA ' + key); } });
    fragment.append(button);
  });
  $('trains').replaceChildren(fragment);
}
function selectTrain(key) {
  selected = key; draft = structuredClone(state.raw[key]); dirty = false;
  $('editor').hidden = !draft;
  if (!draft) return;
  $('trainId').textContent = `VIA ${key} · ${draft.instance}`;
  $('route').textContent = `${draft.from} → ${draft.to}`;
  ['instance', 'lat', 'lng', 'speed', 'direction', 'poll'].forEach(field => { $(field).value = draft[field] ?? ''; });
  ['departed', 'arrived'].forEach(field => { $(field).checked = draft[field] === true; });
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
  result.instance = $('instance').value;
  ['departed', 'arrived'].forEach(field => { result[field] = $(field).checked; });
  ['lat', 'lng', 'speed', 'direction'].forEach(field => {
    if ($(field).value === '') delete result[field]; else result[field] = Number($(field).value);
  });
  if ($('poll').value.trim()) result.poll = $('poll').value.trim(); else delete result.poll;
  return result;
}
$('search').addEventListener('input', renderList);
['instance', 'lat', 'lng', 'speed', 'direction', 'poll', 'departed', 'arrived'].forEach(field => $(field).addEventListener('input', changed));
$('json').addEventListener('input', changed);
$('save').addEventListener('click', () => action('replace', { train: collectDraft() }, false));
$('jsonApply').addEventListener('click', () => {
  try { action('replace', { train: JSON.parse($('json').value) }, false); } catch { message('JSON 格式有误，修改尚未保存。', 'error'); }
});
document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', () => action(button.dataset.action)));
$('delayApply').addEventListener('click', () => action('delay', { minutes: Number($('delay').value) }));
$('mode').addEventListener('change', async () => { await action('mode', { mode: $('mode').value }); $('mode').value = state.mode; });
$('reset').addEventListener('click', () => { if (window.confirm('把全部测试车次恢复为当前时间的示例？可用“撤销”恢复。')) action('reset'); });
$('undo').addEventListener('click', () => action('undo'));
$('import').addEventListener('change', async () => {
  const file = $('import').files[0]; if (!file) return;
  try {
    if (file.size > 8 * 1024 * 1024) throw new Error('JSON 文件不能超过 8 MB');
    await action('import', { raw: JSON.parse(await file.text()) });
  } catch (error) { message(error.message, 'error'); }
  $('import').value = '';
});
$('serverURL').textContent = location.origin;
setBusy(true);
load().then(() => message('准备就绪 · 选择场景或编辑站点时间。'))
  .catch(error => message('测试台未连接：' + error.message, 'error'))
  .finally(() => setBusy(!state));
setInterval(async () => {
  if (busy || document.hidden || !state) return;
  try {
    const status = await request('/control/status'); connection(status); remoteStatus(status);
    if (status.revision !== state.revision) {
      if (dirty) message('另一个页面修改了数据。请先导出或复制当前编辑内容，再刷新页面。', 'pending');
      else { await load(); message('已同步另一个页面的修改。'); }
    }
  } catch { $('connection').textContent = '测试台已断开 · 重新启动后刷新网页'; }
}, 3000);

function remoteStatus(info) {
  if (!info.public) return;
  if (state) Object.assign(state, { public: true, pushConfigured: info.pushConfigured, devices: info.devices, deliveries: info.deliveries });
  $('setup').hidden = true; $('publicSetup').hidden = false; $('pushPanel').hidden = false;
  $('footerNote').textContent = '公网测试数据持久保存，重启服务不会重置。面板无需登录且多人共享；正式 VIA 数据与日常行程独立。';
  $('pushState').textContent = info.pushConfigured ? '推送服务已配置。按 App 环境面板中的设备编号找到你的手机。' : '数据服务可用，推送密钥尚未配置。';
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
  const logs = document.createDocumentFragment();
  for (const log of info.deliveries || []) {
    const row = document.createElement('p'); row.className = 'delivery-row';
    row.textContent = `${new Date(log.sent_at).toLocaleTimeString()} · ${log.device_code} · ${log.kind === 'activity' ? '实时活动' : '普通通知'} · ${log.accepted ? 'Apple 已接收' : '未接收：' + (log.reason || '未知原因')}`;
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
