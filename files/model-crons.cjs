// model-crons.cjs — 定时任务（automation/cron）定义清单与换模型工具（v16，2026-10-19）
// 用法：
//   node model-crons.cjs list [--out <文件>] [--hbfile <文件>]   只读：定时任务定义（中文名 + 何时跑 + 用哪个模型）+ 心跳/压缩模型
//   node model-crons.cjs set --model <provider/model> [--dry]    把「要模型」的定时任务换成该模型（读回确认）
//   node model-crons.cjs set --model <ref> --name <任务名>        [v18] 只改这一个任务（--id <uuid> 也行）
//   node model-crons.cjs hb                                       只读：心跳与压缩现在用哪个模型（读 openclaw.json）
// 走网关 RPC cron.list / CLI cron edit —— 不重启服务、不碰对话窗口。
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

function cliPath() {
  const cand = [
    process.env.OPENCLAW_CLI,
    path.join(process.env.USERPROFILE || '', 'AppData', 'Roaming', 'npm', 'node_modules', 'openclaw', 'openclaw.mjs'),
  ].filter(Boolean);
  for (const c of cand) { try { if (fs.existsSync(c)) return c; } catch (e) {} }
  return null;
}
const CLI = cliPath();
const CWD = CLI ? path.dirname(CLI) : process.cwd();

// shell:false 是关键：借 shell 会让 Node 把 DEP0190 警告塞进 stdout，JSON 就废了（v15 的坑）
function call(args) {
  const r = spawnSync('node', [CLI, 'gateway', 'call', ...args], {
    shell: false, cwd: CWD, encoding: 'utf8', timeout: 45000,
  });
  if (r.status !== 0) { throw new Error('网关调用失败 exit=' + r.status + ' ' + String(r.stderr || '').slice(0, 200)); }
  const t = String(r.stdout || '').trim();
  if (!t) return null;
  return JSON.parse(t);
}
function cliCall(args) {
  const r = spawnSync('node', [CLI, ...args], { shell: false, cwd: CWD, encoding: 'utf8', timeout: 60000 });
  return { ok: r.status === 0, out: String(r.stdout || ''), err: String(r.stderr || '') };
}

// cron 表达式/间隔 → 一句人话（用户：别显示英文、也不知道是干嘛的）
function whenText(sch) {
  if (!sch) return '未设';
  if (sch.kind === 'every') {
    const ms = Number(sch.everyMs || 0);
    if (ms >= 604800000) return '每 ' + Math.round(ms / 604800000) + ' 周';
    if (ms >= 86400000) return '每 ' + Math.round(ms / 86400000) + ' 天';
    if (ms >= 3600000) return '每 ' + Math.round(ms / 3600000) + ' 小时';
    if (ms >= 60000) return '每 ' + Math.round(ms / 60000) + ' 分钟';
    return '每 ' + Math.round(ms / 1000) + ' 秒';
  }
  if (sch.kind === 'cron') {
    const e = String(sch.expr || '').trim().split(/\s+/);
    // 本机时区就是 Asia/Shanghai，写出来只会拉长行，所以省略
    const tz = (sch.tz && sch.tz !== 'Asia/Shanghai') ? '（' + sch.tz + '）' : '';
    if (e.length >= 5) {
      const [min, hr, dom, mon, dow] = e;
      const pad = (x) => String(x).padStart(2, '0');
      if (dom === '*' && mon === '*' && dow === '*') {
        if (hr === '*' && min === '*/15') return '每天每 15 分钟' + tz;
        if (hr === '*' && min === '*/30') return '每天每 30 分钟' + tz;
        if (hr === '*' && /^\d+$/.test(min)) return '每天每小时第 ' + min + ' 分钟' + tz;
        if (/^\d+$/.test(hr) && /^\d+$/.test(min)) return '每天 ' + hr + ':' + pad(min) + tz;
        if (/^\d+-\d+$/.test(hr)) return '每天 ' + hr + ' 时段内每 ' + (min.startsWith('*/') ? min.slice(2) : '1') + ' 分钟' + tz;
      }
      if (dom === '*' && mon === '*' && dow !== '*') {
        const wd = ['日', '一', '二', '三', '四', '五', '六'][Number(dow) % 7] || '?';
        return '每周' + wd + (hr === '*' ? '' : ' ' + hr + ':' + pad(min)) + tz;
      }
      if (dom === '1' && mon === '1') return '每年1月1日00:00(靠触发器)';
    }
    return 'cron: ' + String(sch.expr || '');
  }
  if (sch.kind === 'once' || sch.kind === 'at') return '一次性';
  return sch.kind || '未设';
}

function kindText(k) {
  if (k === 'script') return '纯脚本·不用模型';
  if (k === 'agentTurn') return '要模型';
  if (k === 'heartbeat') return '心跳';
  if (k === 'systemEvent') return '系统事件';
  return k || '?';
}

// [2026-10-20 v18] provider → 中文归属（用户：分不清是 DS 官方还是云端服务商的 deepseek）
// 真相源：openclaw.json 里每个 provider 的 baseUrl。改 provider 域名时这张表也要改。
const PROV = {
  scnet:    { tag: '云端',  full: '国家云端服务商 DeepSeek',  host: 'api.scnet.cn' },
  deepseek: { tag: 'DS官方', full: 'DeepSeek 官方',        host: 'api.deepseek.com' },
  dashscope:{ tag: '阿里云', full: '阿里云 DashScope',     host: 'dashscope.aliyuncs.com' },
  strata:   { tag: '本地',  full: '本地 Strata（127.0.0.1:8080）', host: '127.0.0.1:8080' },
  llamacpp: { tag: '本地',  full: '本地 llama.cpp（127.0.0.1:8090）', host: '127.0.0.1:8090' },
  'llamacpp-vision': { tag: '本地', full: '本地视觉（127.0.0.1:8096）', host: '127.0.0.1:8096' },
  ollama:   { tag: '本地',  full: '本地 Ollama（127.0.0.1:11434）', host: '127.0.0.1:11434' },
};
function splitRef(m) {
  const s = String(m || '').trim();
  if (!s) return { prov: '', model: '' };
  const i = s.indexOf('/');
  return i < 0 ? { prov: '', model: s } : { prov: s.slice(0, i), model: s.slice(i + 1) };
}
// 返回 { tag, full, host }；未知 provider 用 provider 名本身当标签
function provOf(m) {
  const { prov } = splitRef(m);
  if (!prov) return { tag: '未设', full: '未设 provider', host: '' };
  return PROV[prov] || { tag: prov, full: prov + '（归属未登记）', host: '' };
}

function modelOf(job) {
  const m = (job.payload && job.payload.model) || job.model || '';
  return String(m || '');
}
function fallbacksOf(job) {
  const p = (job && job.payload) || {};
  const fb = p.fallbacks || job.fallbacks || [];
  return Array.isArray(fb) ? fb.map(x => String(x)).filter(Boolean) : [];
}
function thinkingOf(job) {
  const p = (job && job.payload) || {};
  return String(p.thinking || job.thinking || '');
}

function rowsFrom(jobs) {
  return (jobs || []).map(x => {
    const kind = (x.payload && x.payload.kind) || x.kind || '';
    const m = modelOf(x);
    const fb = fallbacksOf(x);
    const pr = provOf(m);
    const fbt = fb.map(f => provOf(f).tag);
    return {
      id: x.id || '',
      name: String(x.displayName || x.name || ''),
      desc: String(x.description || '').slice(0, 140),
      enabled: !!x.enabled,
      kind,
      kindText: kindText(kind),
      model: m,
      // [2026-10-20 v18] 归属标签：云端 / DS官方 / 阿里云 / 本地 —— 用户一眼分辨
      provTag: m ? pr.tag : '',
      provFull: m ? pr.full : '',
      provHost: m ? pr.host : '',
      fallbacks: fb,
      fallbackTags: fbt,
      thinking: thinkingOf(x),
      when: whenText(x.schedule),
      needsModel: kind === 'agentTurn' || kind === 'heartbeat',
    };
  }).sort((a, b) =>
    // [2026-10-19 v17] 用户要求：「要模型」的任务放上面，纯脚本放下面；停用的排最后
    (b.enabled ? 1 : 0) - (a.enabled ? 1 : 0) || (b.needsModel ? 1 : 0) - (a.needsModel ? 1 : 0) || a.name.localeCompare(b.name, 'zh'));
}

function hbInfo() {
  const p = path.join(process.env.USERPROFILE || '', '.openclaw', 'openclaw.json');
  try {
    const d = JSON.parse(fs.readFileSync(p, 'utf8'));
    const def = (d.agents && d.agents.defaults) || {};
    return {
      heartbeat: (def.heartbeat && def.heartbeat.model) || '',
      compaction: (def.compaction && def.compaction.model) || '',
      primary: (def.model && def.model.primary) || '',
      source: 'openclaw.json（改需网关重启）',
    };
  } catch (e) { return { heartbeat: '', compaction: '', primary: '', source: '读不到 openclaw.json' }; }
}

function writeOut(p, txt) { if (!p) return; try { fs.writeFileSync(p, txt, 'utf8'); } catch (e) {} }

const argv = process.argv.slice(2);
const cmd = (argv[0] || 'list').toLowerCase();
const flag = (n) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : ''; };
const has = (n) => argv.includes(n);

// [2026-10-20 v18] 实测：cron.list 默认只给「在跑」的 13 个；带 includeDisabled:true 才给全部 17 个
// （停用里有 2 个要模型的 + 1 个心跳任务，用户怀疑「还有没分辨出来的」是对的）
function fetchJobs() {
  let j = call(['cron.list', '--json', '--params', JSON.stringify({ limit: 100, includeDisabled: true }), '--timeout', '25000']);
  let jobs = (j && j.jobs) || [];
  if (!jobs.some(x => x.enabled === false)) {
    try {
      const j2 = call(['cron.list', '--json', '--params', JSON.stringify({ limit: 100 }), '--timeout', '25000']);
      jobs = (j2 && j2.jobs) || jobs;
    } catch (e) {}
  }
  return jobs;
}

if (cmd === 'list') {
  const rows = rowsFrom(fetchJobs());
  const txt = JSON.stringify(rows, null, 1);
  writeOut(flag('--out'), txt);
  writeOut(flag('--hbfile'), JSON.stringify(hbInfo(), null, 1));
  console.log(txt);
  process.exit(0);
}

if (cmd === 'hb') {
  const txt = JSON.stringify(hbInfo(), null, 1);
  writeOut(flag('--out'), txt);
  console.log(txt);
  process.exit(0);
}

// 拼 cron edit 的参数（--model / --thinking / --fallbacks），返回 {args, note}
function editArgs(model, thinking, fallbacks) {
  const a = [];
  if (model) a.push('--model', model);
  if (thinking) a.push('--thinking', thinking);
  if (fallbacks && fallbacks.length) a.push('--fallbacks', fallbacks.join(','));
  return a;
}

if (cmd === 'set') {
  const model = flag('--model');
  if (!model) { console.log('缺 --model <provider/model>'); process.exit(1); }
  const dry = has('--dry');
  const thinking = flag('--thinking');
  const oneId = flag('--id');
  const oneName = flag('--name');
  const all = rowsFrom(fetchJobs());
  // [2026-10-20 v18] 「单个」模式：--id 或 --name 指定一个任务，只改它（用户：批量的要保留，个别的也要能做）
  let targets;
  if (oneId || oneName) {
    const want = oneId || oneName;
    // [2026-10-20 v18] 先精确同名；没有精确同名才退而求其次「包含」，且只取「要模型」的任务
    // （实测坑：--name 开机早报 曾把「开机早报触发器」也带上，那是纯脚本，不该改）
    const exact = all.filter(x => (oneId ? x.id === oneId : x.name === want));
    if (exact.length) targets = exact;
    else {
      const loose = all.filter(x => x.needsModel && (oneId ? x.id === want : x.name.includes(want)));
      targets = loose;
    }
    if (!targets.length) { console.log(JSON.stringify({ tried: 0, sent: 0, confirmed: 0, note: '找不到这个「要模型」的定时任务：' + want })); process.exit(1); }
  } else {
    targets = all.filter(x => x.enabled && x.needsModel);
  }
  const scriptCount = all.filter(x => x.enabled && !x.needsModel).length;
  if (dry) {
    console.log(JSON.stringify({ mode: 'dry', scope: (oneId || oneName) ? 'one' : 'batch', willChange: targets.length, scriptUntouched: scriptCount, model: model,
      list: targets.map(t => ({ name: t.name, when: t.when, now: t.model || '默认', nowTag: t.provTag })) }));
    process.exit(0);
  }
  if (!targets.length) { console.log(JSON.stringify({ tried: 0, sent: 0, confirmed: 0, note: '没有「要模型」的定时任务（全是纯脚本）' })); process.exit(0); }
  let sent = 0;
  const errs = [];
  for (const t of targets) {
    const r = cliCall(['cron', 'edit', t.id, ...editArgs(model, thinking, null), '--json']);
    if (r.ok) { sent++; } else { errs.push(t.name + ': ' + r.err.slice(0, 90)); }
  }
  // 读回确认：改完再读一次定义清单，数出真正生效的个数（patch 返回 ok ≠ 生效）
  const back = rowsFrom(fetchJobs());
  const backMap = new Map(back.map(x => [x.id, x.model]));
  let confirmed = 0;
  const done = [];
  for (const t of targets) { if (backMap.get(t.id) === model) { confirmed++; done.push(t.name + '(' + provOf(model).tag + ')'); } }
  console.log(JSON.stringify({ tried: targets.length, sent: sent, confirmed: confirmed, model: model, provTag: provOf(model).tag, scope: (oneId || oneName) ? 'one' : 'batch', changed: done, scriptUntouched: scriptCount, errors: errs }));
  process.exit(0);
}

console.log('未知命令 ' + cmd + '；用 list / set --model <ref> [--id <uuid> | --name <名>] [--thinking <级>] [--dry] / hb');
process.exit(1);
