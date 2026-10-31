/* Local presentation interactions. No API calls or persisted trip data. */
const creationStops = [
  {code:'TRTO',name:'Toronto',time:'14:00'},
  {code:'KGON',name:'Kingston',time:'16:20'},
  {code:'SMFL',name:'Smiths Falls',time:'17:30'},
  {code:'OTTA',name:'Ottawa',time:'18:30'}
];
const creationPlan = {board:0,alight:3,travel:30};
const originalTransfer = {...screens['add-transfer']};
const originalTransferReview = {...screens['transfer-review']};
const minuteValue = value => {const [h,m]=value.split(':').map(Number);return h*60+m};
const timeValue = value => `${String(Math.floor(((value%1440)+1440)%1440/60)).padStart(2,'0')}:${String(((value%60)+60)%60).padStart(2,'0')}`;
function stationControl(kind,name,cls='list-row') {
  return `<button type="button" class="${cls} station-control" data-open-station="${kind}" aria-haspopup="dialog"><span class="row">${I(kind==='board'?'location':'mappin.and.ellipse')}<span>${kind==='board'?'上车站':'下车站'}</span></span><span class="row"><span class="station-value">${name}</span>${I('chevron.right','chev')}</span></button>`;
}
function selectedTimeline() {
  return timeline(creationStops.slice(creationPlan.board,creationPlan.alight+1).map((stop,n,items)=>[
    stop.name,stop.time,n===0?'上车站 · 计划发车':n===items.length-1?'下车站 · 计划到达':'计划到达','',n===0?'current':''
  ]),true);
}
function choiceList(kind,sheet=false) {
  const selected=creationPlan[kind];
  return `<div class="station-choices" role="group" aria-label="${kind==='board'?'上车站':'下车站'}列表">${creationStops.map((stop,n)=>{
    const disabled=kind==='board'?n>=creationPlan.alight:n<=creationPlan.board;
    return `<button type="button" class="station-option ${n===selected?'is-selected':''}" data-select-station="${kind}" data-station-index="${n}" aria-pressed="${n===selected}" ${disabled?'disabled':''}><span class="col"><span class="station-choice-name">${stop.name}</span><span class="small muted">${disabled?'不在可选区间':kind==='board'?'计划发车':'计划到达'} ${stop.time}</span></span><span class="selection-circle ${n===selected?'selected':''}">${n===selected?I('checkmark'):''}</span></button>`;
  }).join('')}</div>`;
}
function creationRouteCard() {
  const a=creationStops[creationPlan.board],b=creationStops[creationPlan.alight];
  return `<div class="card"><div class="row"><span class="train-mark">${I('tram.fill','sm')}VIA 44</span>${pill('11月6日','neutral')}</div><div class="route-title" style="margin:14px 0 18px">${a.name} ${I('arrow.right')} ${b.name}</div><div class="journey-line"><div class="track"></div><div class="journey-stops"><div class="station-row"><span class="name">${a.name}</span><span class="time mono">${a.time}</span></div><div class="station-row"><span class="name">${b.name}</span><span class="time mono">${b.time}</span></div></div></div></div>`;
}
function refreshCreationScreens() {
  const a=creationStops[creationPlan.board],b=creationStops[creationPlan.alight];
  const leave=timeValue(minuteValue(a.time)-creationPlan.travel);
  add(phone('stations',`${formTitle('选择上下车站','点击车站，从本班列车的停靠站中选择。')}<div class="card compact">${row('<span class="train-mark">VIA 44</span>',dateLabel)}</div><div class="list-group">${stationControl('board',a.name)}${stationControl('alight',b.name)}</div>${section('本段停靠',`<div class="card">${selectedTimeline()}</div>`)}<div class="spacer"></div>${button('下一步','primary','','departure')}`,{title:'乘车区间',back:'返回',right:'',time:'12:55',backTarget:'search'}),'03 · 点击选择上下车站');
  for(const [kind,id] of [['board','boarding-picker'],['alight','alighting-picker']]) {
    add(phone(id,`<h1>选择${kind==='board'?'上车站':'下车站'}</h1><div class="form-subtitle">VIA 44 · 11月6日 · 按停靠顺序显示</div>${choiceList(kind)}<div class="small muted">${kind==='board'?'上车站需在下车站之前。':'下车站需在上车站之后。'}</div><div class="spacer"></div>${button('完成','primary','checkmark','stations')}`,{title:'选择车站',back:'返回',right:'',time:'12:55',backTarget:'stations'}),kind==='board'?'03a · 上车站列表':'03b · 下车站列表');
  }
  const [hour,minute]=a.time.split(':').map(Number);
  add(phone('departure',`${formTitle('确认发车时间','此设置仅用于出门前的时间规划。',2)}<div class="card compact">${row(`<span class="train-mark">VIA 44 · ${a.name}</span>`,pill('官方计划'))}<div class="small muted" style="margin-top:10px">11月6日 周五 · America/Toronto</div></div><div class="time-picker"><div class="picker-col"><span>${String((hour+23)%24).padStart(2,'0')}</span><span class="picked">${String(hour).padStart(2,'0')}</span><span>${String((hour+1)%24).padStart(2,'0')}</span></div><span class="colon">:</span><div class="picker-col"><span>${String((minute+59)%60).padStart(2,'0')}</span><span class="picked">${String(minute).padStart(2,'0')}</span><span>${String((minute+1)%60).padStart(2,'0')}</span></div></div>${field('官方计划',a.time,'')}${notice('调整仅影响计划出门时间。候车和乘车阶段仍使用官方时刻。')}<div class="spacer"></div>${button('设置前往耗时','primary','','travel')}`,{title:'规划时间',back:'返回',right:'',time:'12:55',backTarget:'stations'}),'04 · 确认发车时间');
  const travelStep=stepper(String(creationPlan.travel)).replace('aria-label="减少15分钟"','aria-label="减少15分钟" data-travel-step="-15"').replace('aria-label="增加15分钟"','aria-label="增加15分钟" data-travel-step="15"');
  add(phone('travel',`${formTitle('前往车站耗时','包含前往车站及自行预留的时间。',2)}<div class="card compact">${row(`<div class="col"><span class="small muted">前往上车站</span><h3>${a.name}</h3></div>`,I('figure.walk','lg'))}</div>${travelStep}<div class="tiny muted" style="text-align:center;margin-top:-10px">每次调整 15 分钟 · 最少 0 分钟</div><div class="card tint"><div class="small accent">计划出门时间</div><div class="mono" style="font-size:46px;font-weight:400;letter-spacing:-2px;margin:8px 0">${leave}</div><div class="small muted">规划发车 ${a.time} − 前往耗时 ${creationPlan.travel} 分钟</div></div><div class="spacer"></div><div class="tiny muted">按你的设置计算，不额外增加候车时间。</div>${button('预览行程','primary','','review')}`,{title:'前往耗时',back:'返回',right:'',time:'12:55',backTarget:'departure'}),'05 · 前往耗时 / 计划出门');
  add(phone('review',`${formTitle('确认行程','核对乘车区间和计划出门时间。',3)}${creationRouteCard()}<div class="list-group">${listRow('计划出门',leave,'house')}${listRow('前往车站',creationPlan.travel+' 分钟','figure.walk')}${listRow('实时活动','开启','antenna.radiowaves.left.and.right')}</div>${button('添加同站换乘','outline','plus','add-transfer')}<div class="spacer"></div>${notice('实时活动最长持续 8 小时。到期后可打开 App 续开。')}<div class="button-stack">${button('开启实时活动','primary','','before')}<div class="tiny muted" style="text-align:center">行程同时保存在本机</div></div>`,{title:'确认行程',back:'返回',right:'',time:'12:55',backTarget:'travel'}),'06 · 单程确认');
  add(phone('transfer-unavailable',`${formTitle('暂无同站换乘','下一段上车站须与上一段下车站相同。',3)}<div class="card compact">${row('<span class="small muted">上一段下车站</span>','<b>Kingston</b>')}</div><div class="empty-graphic">${I('arrow.triangle.branch')}</div><div class="empty-copy"><h2>没有从 Kingston 出发的班次</h2><p>可以更换日期或列车。<br>也可以先保存当前行程。</p></div><div class="spacer"></div>${button('返回选择列车','primary','','search')}${button('保留单段行程','outline','','review')}`,{title:'添加换乘',back:'返回',right:'',time:'12:55',backTarget:'review'}),'08 · 暂无同站接续列车');
  screens['add-transfer']={...originalTransfer};
  screens['transfer-review']={...originalTransferReview};
  if(b.name!=='Ottawa') {
    const unavailable=screens['transfer-unavailable'].html.replaceAll('Kingston',b.name).replace('art-transfer-unavailable','art-add-transfer');
    screens['add-transfer'].html=unavailable;
  } else {
    screens['transfer-review'].html=originalTransferReview.html
      .replace('Toronto → Ottawa → Montréal',`${a.name} → Ottawa → Montréal`)
      .replace(leg('44','Toronto','Ottawa','14:00','18:30'),leg('44',a.name,'Ottawa',a.time,'18:30'))
      .replace(field('计划出门','13:30',''),field('计划出门',leave,''));
  }
  add({id:'ipad-create',type:'tablet',width:1194,height:834,html:`<article id="art-ipad-create" class="art tablet">${status('12:55',true)}<div class="ipad-layout">${sidebar('待出发','12:55')}<div class="ipad-main"><div class="ipad-title"><h2>添加行程</h2><span class="small accent">取消</span></div><div class="ipad-setup-cols"><div class="ipad-column"><div class="small muted">第 2 步 · 出门规划</div><h2 style="font-size:30px;margin:0">前往车站耗时</h2><div class="list-group">${stationControl('board',a.name)}${stationControl('alight',b.name)}</div>${travelStep}<div class="card tint"><div class="small accent">计划出门</div><div class="mono" style="font-size:48px;letter-spacing:-2px;margin:8px 0">${leave}</div><div class="small muted">规划发车 ${a.time} − 前往耗时 ${creationPlan.travel} 分钟</div></div></div><div class="ipad-summary-panel"><div class="section-label"><span>乘车区间</span><span class="muted">11月6日</span></div><span class="train-mark">${I('tram.fill','sm')}VIA 44</span><div class="route-title">${a.name} ${I('arrow.right')} ${b.name}</div>${selectedTimeline()}<div class="spacer"></div>${notice('计划出门按你的设置计算。官方计划和预计时刻独立保留。')}${button('下一步：确认行程','primary','','review')}</div></div></div></div>${footer()}</article>`},'40 · iPad 横屏 · 添加行程');
}
refreshCreationScreens();

let stationDialogFocus=null;
function openStationSheet(art,kind) {
  if(!art)return;
  stationDialogFocus=document.activeElement;
  const shade=document.createElement('div');
  shade.className='station-sheet-shade';
  shade.innerHTML=`<section class="station-sheet" role="dialog" aria-modal="true" aria-label="选择${kind==='board'?'上车站':'下车站'}"><div class="sheet-grabber"></div><div class="row"><h2>选择${kind==='board'?'上车站':'下车站'}</h2><button type="button" class="icon-button" data-close-station aria-label="关闭车站选择">${I('xmark')}</button></div><div class="small muted" style="margin:5px 0 19px">VIA 44 · 11月6日 · 按停靠顺序显示</div>${choiceList(kind,true)}<div class="tiny muted" style="margin-top:20px">仅可选择有效的前后站区间。</div></section>`;
  art.append(shade);
  shade.querySelector('.station-option[aria-pressed="true"]:not(:disabled)')?.focus({preventScroll:true});
}
function closeStationSheet(){document.querySelectorAll('.station-sheet-shade').forEach(el=>el.remove());stationDialogFocus?.focus({preventScroll:true})}
document.addEventListener('click',e=>{
  const opener=e.target.closest('[data-open-station]');
  if(opener){openStationSheet(opener.closest('.art'),opener.dataset.openStation);return}
  if(e.target.closest('[data-close-station]')||e.target.classList.contains('station-sheet-shade')){closeStationSheet();return}
  const selected=e.target.closest('[data-select-station]');
  if(selected&&!selected.disabled){
    const kind=selected.dataset.selectStation,index=Number(selected.dataset.stationIndex);
    if(!Number.isInteger(index)||index<0||index>=creationStops.length)return;
    if(kind==='board'&&index>=creationPlan.alight||kind==='alight'&&index<=creationPlan.board)return;
    const sheet=!!selected.closest('.station-sheet');
    const artId=selected.closest('.art').id;
    creationPlan[kind]=index;
    refreshCreationScreens();
    renderGroup(currentGroup,false);
    if(sheet)document.querySelector(`#${artId} [data-open-station="${kind}"]`)?.focus({preventScroll:true});
    return;
  }
  const step=e.target.closest('[data-travel-step]');
  if(step){const amount=Number(step.dataset.travelStep);creationPlan.travel=Math.max(0,creationPlan.travel+amount);refreshCreationScreens();renderGroup(currentGroup,false)}
});
document.addEventListener('keydown',e=>{
  const dialog=document.querySelector('.station-sheet');
  if(!dialog)return;
  if(e.key==='Escape'){e.preventDefault();closeStationSheet();return}
  if(e.key==='Tab'){
    const items=[...dialog.querySelectorAll('button:not(:disabled)')],first=items[0],last=items.at(-1);
    if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus({preventScroll:true})}
    else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus({preventScroll:true})}
  }
});
