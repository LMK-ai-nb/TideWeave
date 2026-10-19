import {replay} from './engine.js';
const $ = id => document.getElementById(id);
const NS = 'http://www.w3.org/2000/svg';
let input,report,step=0;
const text = (tag,value,cls) => {const e=document.createElement(tag);e.textContent=value;if(cls)e.className=cls;return e;};
const svg = (tag,attrs={},value) => {const e=document.createElementNS(NS,tag);for(const [k,v] of Object.entries(attrs))e.setAttribute(k,v);if(value!==undefined)e.textContent=value;return e;};
const identity=w=>JSON.stringify([w.key,w.start,w.end]);
const labels={accepted:'已提交',rejected:'已拒绝',duplicate:'已去重',conflict:'ID 冲突'};
const reasons={
  'correction would change a finalized window':'这次修正会改变已经终结的窗口。整笔事务已拒绝，现有结果保持一致。',
  'correction would change a finalized event':'修正涉及已终结窗口的原始事件。即使聚合数值相同，也不能改写已经封存的事实。',
  'correction would create an already finalized window':'修正会产生一个已经过期的历史窗口，因此整笔拒绝。',
};
function materialize(n){
  const rows=new Map();
  for(const o of report.steps.slice(0,n)) for(const d of o.deltas){if(d.kind==='delete')rows.delete(identity(d.before));else rows.set(identity(d.after),d.after);}
  return [...rows.values()].sort((a,b)=>a.key<b.key?-1:a.key>b.key?1:a.start-b.start||a.end-b.end);
}
function draw(rows,events,wm){
  const chart=$('chart');chart.replaceChildren();
  const s=svg('svg',{viewBox:'0 0 620 178',role:'img','aria-label':'按事件时间绘制的窗口、成员和水位线'});chart.append(s);
  const min=Math.min(0,...rows.map(r=>r.start)),max=Math.max(35,wm+5,...rows.map(r=>r.end+5));
  const x=t=>95+(t-min)/(max-min)*496;
  for(let i=0;i<=5;i++){const t=min+(max-min)*i/5;const px=x(t);s.append(svg('line',{x1:px,x2:px,y1:19,y2:147,stroke:'#283642','stroke-dasharray':'2 5'}));s.append(svg('text',{x:px,y:167,'text-anchor':'middle',class:'axis-label'},Math.round(t)));}
  const keys=[...new Set([...rows.map(r=>r.key),...events.map(e=>e.key)])];
  const byId=new Map(events.map(e=>[e.id,e]));
  const yrow=i=>36+(i%4)*30;
  if(!rows.length)s.append(svg('text',{x:335,y:85,'text-anchor':'middle'},'点击「下一步」，观察窗口随输入变化'));
  rows.slice(0,4).forEach((r,i)=>{const y=yrow(i),color=r.phase==='closing'?'#dfbc74':r.phase==='final'?'#8297a8':'#78e3c9';
    s.append(svg('text',{x:8,y:y+4,class:'key-label'},r.key.length>12?r.key.slice(0,10)+'…':r.key));
    const box=svg('rect',{x:x(r.start),y:y-11,width:Math.max(2,x(r.end)-x(r.start)),height:23,rx:4,fill:color,'fill-opacity':'.09',stroke:color,'stroke-opacity':'.55'});box.append(svg('title',{},`${r.key} [${r.start}, ${r.end}) · sum ${r.sum}`));s.append(box);
    r.members.forEach(id=>{const e=byId.get(id);if(!e)return;const dot=svg('circle',{cx:x(e.at),cy:y,r:4,fill:color,stroke:'#151c25','stroke-width':2});dot.append(svg('title',{},`${id} · t=${e.at} · value=${e.value}`));s.append(dot);});
  });
  if(rows.length>4)s.append(svg('text',{x:96,y:149,class:'axis-label'},`另有 ${rows.length-4} 个窗口，完整结果见下表`));
  s.append(svg('line',{x1:x(wm),x2:x(wm),y1:17,y2:147,stroke:'#dfbc74','stroke-dasharray':'4 4'}));
  s.append(svg('text',{x:x(wm),y:11,'text-anchor':'middle',fill:'#dfbc74'},`WM ${wm}`));
}
function narrative(o){
  if(!o)return '这是起点。输入中的到达顺序不等于事件发生顺序，点击下一步开始回放。';
  if(o.status==='rejected')return reasons[o.message]||`整笔命令已拒绝：${o.message}`;
  if(o.status==='duplicate')return '相同命令已提交过。此次重试不重复写入，也不推进提交版本。';
  if(o.status==='conflict')return '这个命令 ID 已被其他内容使用，当前请求没有产生任何变化。';
  const cmd=input.commands[step-1];
  if(cmd.kind==='watermark')return `水位推进到 ${cmd.to}。窗口先进入 closing，再在 end + lateness 时终结；终结后拒绝历史改写。`;
  const deletes=o.deltas.filter(d=>d.kind==='delete').length,ups=o.deltas.filter(d=>d.kind==='upsert').length;
  if(deletes===2&&ups===1)return '迟到的桥接事件连接了两个会话。原来的两行被撤回，一个新的合并窗口原子地替代它们。';
  if(deletes===1&&ups===2)return '桥接事件被撤回，连接断开。旧窗口被删除，两个独立会话重新出现，成员与聚合一并修正。';
  return `原子提交 ${cmd.changes.length} 项事件变更，生成 ${o.deltas.length} 条窗口修正。下游可按版本与 before image 检查是否漏接更新。`;
}
function render(){
  if(!report)return;
  const o=report.steps[step-1],rows=materialize(step),wm=o?.watermark??0,ver=o?.version??0;
  const events=new Map();
  input.commands.slice(0,step).forEach((c,i)=>{if(report.steps[i].status!=='accepted'||c.kind!=='transaction')return;for(const m of c.changes){if(m.op==='put')events.set(m.event.id,m.event);else events.delete(m.event_id);}});
  $('event-count').textContent=events.size;$('window-count').textContent=rows.length;$('watermark').textContent=wm;$('version').textContent=String(ver).padStart(2,'0');
  $('commit-description').textContent=o?`${o.id} · ${labels[o.status]}`:'等待第一条命令';
  $('step-count').textContent=`${step} / ${report.steps.length}`;$('step-progress').style.width=`${report.steps.length?100*step/report.steps.length:0}%`;
  $('previous').disabled=step===0;$('reset').disabled=step===0;$('next').disabled=step===report.steps.length;$('finish').disabled=step===report.steps.length;
  const w=input.config.window;$('window-kind').textContent=w.kind==='session'?`会话窗口 · gap ${w.gap}`:w.kind==='tumbling'?`滚动窗口 · size ${w.size}`:`滑动窗口 · ${w.size} / ${w.slide}`;
  $('narrative').replaceChildren(text('span','⌁'),text('p',narrative(o)));
  draw(rows,[...events.values()],wm);
  $('rows').replaceChildren();
  for(const r of rows){const tr=document.createElement('tr');tr.className='aggregate-row';for(const v of [r.key,`[${r.start}, ${r.end})`,r.count,r.sum])tr.append(text('td',v));const td=document.createElement('td');td.append(text('span',r.phase,`phase ${r.phase}`));tr.append(td,text('td',r.members.join(', ')));$('rows').append(tr);}
  if(!rows.length){const tr=document.createElement('tr');const td=text('td','等待事件进入窗口','empty');td.colSpan=6;tr.append(td);$('rows').append(tr);}
  $('commands').replaceChildren();$('command-total').textContent=report.steps.length;
  input.commands.forEach((c,i)=>{const done=i<step,button=document.createElement('button');button.className=`command ${done?'done':''} ${i===step-1?'current':''} ${done?report.steps[i].status:''}`;button.append(text('span',String(i+1).padStart(2,'0'),'number'));const name=document.createElement('span');name.append(text('b',c.id),text('small',c.kind==='watermark'?`WATERMARK → ${c.to}`:`TRANSACTION · ${c.changes.length} changes`));button.append(name,text('span',done?labels[report.steps[i].status]:'待执行','status'));button.addEventListener('click',()=>{step=i+1;render();});$('commands').append(button);});
  $('changes').replaceChildren();$('delta-count').textContent=`${o?.deltas.length??0} 条变更`;
  if(!o)$('changes').append(text('p','从第一条命令开始，查看精确的变更前后状态。','empty'));
  else if(!o.deltas.length)$('changes').append(text('p',o.status==='accepted'?'命令已提交，没有聚合行发生变化。':narrative(o),'explanation'));
  else for(const d of o.deltas){const row=d.after||d.before,div=text('div','','delta'),body=text('div','','delta-body');body.append(text('b',`${row.key}  [${row.start}, ${row.end})`),text('small',`${d.before?`sum ${d.before.sum}`:'∅'} → ${d.after?`sum ${d.after.sum}`:'∅'}  ·  ${row.members.join(', ')}`));div.append(text('span',d.kind==='delete'?'− DELETE':'+ UPSERT',`delta-mark ${d.kind}`),body);$('changes').append(div);}
}
function load(source,initialStep=0){
  const result=JSON.parse(replay(source));
  if(result.error){report=null;$('error').hidden=false;$('error').textContent=`输入校验未通过：${result.error.message}`;for(const id of ['event-count','window-count','watermark','version'])$(id).textContent='—';for(const id of ['export','export-report','next','previous','reset','finish'])$(id).disabled=true;$('rows').replaceChildren();$('chart').replaceChildren();$('changes').replaceChildren();$('commands').replaceChildren();return;}
  input=JSON.parse(source);report=result;step=Math.min(initialStep,result.steps.length);$('error').hidden=true;$('export').disabled=false;$('export-report').disabled=false;render();
}
async function example(name){
  try{const response=await fetch(`data/${name}`);if(!response.ok)throw Error('示例文件无法加载');const source=await response.text();$('input').value=source;load(source,1);document.querySelectorAll('.scenario').forEach(b=>b.classList.toggle('selected',b.dataset.example===name));}
  catch(e){$('error').hidden=false;$('error').textContent=e.message;}
}
for(const b of document.querySelectorAll('.scenario'))b.addEventListener('click',()=>example(b.dataset.example));
$('next').onclick=()=>{if(report&&step<report.steps.length){step++;render();}};
$('previous').onclick=()=>{if(report&&step>0){step--;render();}};
$('reset').onclick=()=>{step=0;render();};$('finish').onclick=()=>{if(report){step=report.steps.length;render();}};
$('apply').onclick=()=>{document.querySelectorAll('.scenario').forEach(b=>b.classList.remove('selected'));load($('input').value,0);};
function download(name,value){const link=document.createElement('a'),url=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)+'\n'],{type:'application/json'}));link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),2000);}
function currentReport(){return JSON.parse(replay(JSON.stringify({...input,commands:input.commands.slice(0,step)})));}
$('export').onclick=()=>{if(report)download('tideweave-checkpoint.json',currentReport().checkpoint);};
$('export-report').onclick=()=>{if(report)download('tideweave-report.json',currentReport());};
example('session-correction.json');
