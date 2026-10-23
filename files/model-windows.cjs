// model-windows.cjs —— OpenClaw 各窗口（会话）模型批量切换工具
// 被「模型服务控制台」的执行器调用，也可手动跑。
//   node model-windows.cjs list                          # 列对话窗口：谁在用哪个模型、上下文多少
//   node model-windows.cjs list --scope sys # 列定时任务/心跳窗口
//   node model-windows.cjs list --scope all              # 两类都列
//   node model-windows.cjs set --model strata/qwen3.8-flash-next-iq2x            # 换所有对话窗口
//   node model-windows.cjs set --model ... --scope sys # 只换定时任务/心跳窗口
//   node model-windows.cjs set --model ... --sys         # 对话 + 系统窗口都换
//   node model-windows.cjs set --model ... --compact    # 换完再压缩上下文（防切小模型爆上下文）
//   node model-windows.cjs set --model ... --dry        # 只报「会换谁」，不动任何窗口
//   node model-windows.cjs models # 列可用模型及其上下文上限
// 原理：走网关 RPC sessions.list / sessions.patchMany（一次调用改多个窗口，实测 2 秒改 3 个）
// 注意：换模型不重启服务、不中断正在跑的回答（网关把切换排队到下一次安全时机）
const { spawn } = require('node:child_process');
const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');

// 找 openclaw 命令行入口（本机实测：直接 spawn `openclaw` + shell:true 会
//   把 DEP0190 弃用警告混进 stdout，导致 JSON 解析失败 → 界面「刷新列表」出不来）。
//   现在优先用 node + openclaw.mjs（shell:false，无警告、无引号问题），找不到才退回 shell:true。
function cliPath() {
  if (process.env.OPENCLAW_CLI && fs.existsSync(process.env.OPENCLAW_CLI)) return process.env.OPENCLAW_CLI;
  const home = os.homedir();
  const cands = process.platform === 'win32'
    ? [path.join(home, 'AppData', 'Roaming', 'npm', 'node_modules', 'openclaw', 'openclaw.mjs')]
    : ['/usr/local/lib/node_modules/openclaw/openclaw.mjs', '/usr/lib/node_modules/openclaw/openclaw.mjs',
       path.join(home, '.npm-global', 'lib', 'node_modules', 'openclaw', 'openclaw.mjs')];
  for (const c of cands) { if (fs.existsSync(c)) return c; }
  return null;
}
const CLI = cliPath();

function call(method, paramsObj, timeoutMs) {
  return new Promise((res) => {
    const extra = [];
    if (paramsObj) extra.push('--params', JSON.stringify(paramsObj));
    if (timeoutMs) extra.push('--timeout', String(timeoutMs));
    let p;
    if (CLI) {
      // shell:false → 参数原样传递，不需要转义引号，也不产生 DEP0190 警告
      p = spawn('node', [CLI, 'gateway', 'call', method, ...extra], { shell: false });
    } else {
      const args = ['gateway', 'call', method];
      if (paramsObj) args.push('--params', JSON.stringify(paramsObj).replace(/"/g, '\\"'));
      if (timeoutMs) args.push('--timeout', String(timeoutMs));
      p = spawn('openclaw', args, { shell: true });
    }
    const ch = [];
    p.stdout.on('data', d => ch.push(d));
    p.stderr.on('data', d => ch.push(d));
    p.on('error', e => res({ code: 1, text: 'spawn 失败：' + e.message }));
    p.on('exit', c => res({ code: c, text: Buffer.concat(ch).toString('utf8') }));
  });
}

// 目标模型的上下文上限：实测本机 strata 五档 = 262144，llamacpp 27B = 131072。
//   切到上限更短的模型时，旧窗口已用量可能超过新上限 → 必须先压上下文，否则一开口就爆。
async function modelCap(modelRef) {
  const r = await call('models.list', {}, 60000);
  const p = parse(r);
  if (!p.ok) { return null; }
  const list = p.json.models || [];
  const want = modelRef.includes('/') ? modelRef : null;
  const bare = modelRef.includes('/') ? modelRef.split('/').slice(1).join('/') : modelRef;
  for (const m of list) {
    const k = String(m.key || m.id || '');
    if ((want && k === want) || k === bare || k === modelRef) {
      const cap = Number(m.contextTokens || m.contextWindow || 0);
      if (cap > 0) return cap;
    }
  }
  return null;
}

function parse(r) {
  // 只取第一个 { 之后的内容；警告/说明行在 stdout 里也不会干扰（shell:false 已消除警告）
  const i = r.text.indexOf('{');
  if (i < 0) return { ok: false, raw: r.text.slice(0, 300).replace(/\s+/g, ' ') };
  try { return { ok: true, json: JSON.parse(r.text.slice(i)) }; }
  catch (e) { return { ok: false, raw: r.text.slice(i, i + 300).replace(/\s+/g, ' ') }; }
}

// 窗口分类：只有「用户真正用的对话窗口」才要换模型。
// 实测（2026-10-19 本机 32 个会话）：真对话窗口 = createdVia='channel'（飞书/微信/webchat）或 isMain=true；
//   其余是系统自己建的：定时任务(cron)、「[OpenClaw exec completion]」回投窗口、「心跳工作间」等 —— 这些按用户
//   2026-10-16 的决定「心跳/压缩不跟本地大块头抢活」，故意不动。
function classify(s) {
  const k = String(s.key || '');
  if (k.includes(':cron:')) return 'sys';
  if (s.isMain) return 'chat';
  if (s.createdVia === 'channel') return 'chat';
  const nm = String(s.label || s.subject || s.displayName || '');
  if (nm.includes('exec completion') || nm.includes('心跳')) return 'sys';
  return 'sys';
}
function nameOf(s) {
  return String(s.label || s.subject || s.displayName || s.key).slice(0, 34);
}
function whereOf(s) {
  const c = s.channel || '?';
  if (s.isMain) return '主会话';
  if (c === 'feishu') return s.peerKind === 'group' ? '飞书群' : '飞书私聊';
  if (c === 'webchat') return '网页对话';
  if (c && c !== '?') return c;
  return '其它';
}

function pickScope(rows, scope) {
  const live = rows.filter(s => !s.archived);
  if (scope === 'sys') return live.filter(s => classify(s) === 'sys');
  if (scope === 'all') return live;
  return live.filter(s => classify(s) === 'chat');   // 默认：只对话窗口
}

async function list() {
  const r = await call('sessions.list', { limit: 100 });
  const p = parse(r);
  if (!p.ok) { console.log('读窗口清单失败：' + p.raw); return 1; }
  const rows = p.json.sessions || [];
  const scope = (get('scope') || 'chat').toLowerCase();
  const chat = rows.filter(s => classify(s) === 'chat' && !s.archived);
  const sys = rows.filter(s => classify(s) === 'sys' && !s.archived);
  if (has('json')) {
    // 给界面用的机器可读输出；同时直接落盘（避开 shell 重定向的编码问题：本机 ACP=936）
    const dump = pickScope(rows, scope).map(s => ({
      key: s.key, name: nameOf(s), where: whereOf(s), model: s.model || '-',
      kind: classify(s),
      used: s.totalTokens === undefined ? null : s.totalTokens,
      cap: s.contextTokens === undefined ? null : s.contextTokens,
      running: !!s.hasActiveRun,
    }));
    const txt = JSON.stringify(dump);
    if (get('out')) { try { require('node:fs').writeFileSync(get('out'), txt, 'utf8'); } catch (e) { /* ignore */ } }
    console.log(txt);
    return 0;
  }
  console.log('对话窗口 ' + chat.length + ' 个 / 系统窗口 ' + sys.length + ' 个（共 ' + rows.length + '）');
  console.log('--- 对话窗口（换模型要换的就是这些）---');
  for (const s of chat) {
    const run = s.hasActiveRun ? ' [正在跑]' : '';
    console.log('  ' + nameOf(s) + ' (' + whereOf(s) + ')' + run +
      ' | 模型 ' + (s.model || '-') +
      ' | 已用上下文 ' + (s.totalTokens === undefined ? '-' : s.totalTokens) + ' / ' + (s.contextTokens === undefined ? '-' : s.contextTokens));
  }
  console.log('--- 系统窗口（定时任务/心跳/回投，默认不动）---');
  for (const s of sys.slice(0, 12)) {
    console.log('  ' + nameOf(s) + ' | 模型 ' + (s.model || '-') +
      ' | 已用上下文 ' + (s.totalTokens === undefined ? '-' : s.totalTokens));
  }
  if (sys.length > 12) console.log('  … 另有 ' + (sys.length - 12) + ' 个');
  return 0;
}

async function set(modelRef, opts) {
  if (!modelRef) { console.log('缺 --model'); return 1; }
  const r = await call('sessions.list', { limit: 100 });
  const p = parse(r);
  if (!p.ok) { console.log('读窗口清单失败：' + p.raw); return 1; }
  const rows = (p.json.sessions || []).filter(s => !s.archived);
  const scope = opts.sys ? 'all' : (opts.scope || 'chat');
  const targets = pickScope(rows, scope);
  const note = scope === 'sys' ? '（只定时任务/心跳窗口）'
    : scope === 'all' ? '（对话 + 系统/定时任务窗口）'
    : '（系统窗口不动，按既定设置：心跳/压缩不与本地模型抢资源）';
  if (targets.length === 0) { console.log('没有要换的窗口'); return 0; }
  console.log('目标模型：' + modelRef);
  console.log('要换的窗口：' + targets.length + ' 个' + note);
  for (const s of targets) {
    console.log('  ' + nameOf(s) + ' (' + whereOf(s) + ') | 现在 ' + (s.model || '-') + ' → ' + modelRef + (s.hasActiveRun ? ' [正在跑：切换排队，不打断当前回答]' : ''));
  }
  if (opts.dry && !has('json')) { console.log('[DryRun] 一个窗口都没动'); return 0; }
  const targets2 = targets.map(s => ({ key: s.key }));
  if (has('json')) {
    const payload = JSON.stringify({ target: modelRef, windows: targets.map(s => ({ name: nameOf(s), where: whereOf(s), model: s.model || '-', used: s.totalTokens === undefined ? null : s.totalTokens })) });
    if (get('out')) { try { require('node:fs').writeFileSync(get('out'), payload, 'utf8'); } catch (e) { /* ignore */ } }
    console.log(payload);
    if (opts.dry) return 0;
  }
  const pr = await call('sessions.patchMany', { patch: { model: modelRef }, targets: targets2 }, 120000);
  const pp = parse(pr);
  if (!pp.ok) { console.log('批量换失败：' + pp.raw); return 1; }
  const outs = pp.json.outcomes || [];
  let okN = 0, bad = [];
  for (const o of outs) { if (o.ok) okN++; else bad.push(nameOf({ key: o.key }) + ': ' + String(o.error && o.error.message).slice(0, 70)); }
  console.log('换成功 ' + okN + ' / ' + outs.length + ' 个窗口');
  for (const b of bad) console.log('  未成功：' + b);
  // 读回确认：重新列窗口，看实际生效的模型
  const back = await call('sessions.list', { limit: 100 });
  const bp = parse(back);
  if (bp.ok) {
    const want = modelRef.includes('/') ? modelRef.split('/').slice(1).join('/') : modelRef;
    let match = 0;
    for (const s of (bp.json.sessions || [])) {
      if (targets2.some(t => t.key === s.key)) {
        const m = String(s.model || '');
        if (m === want || m === modelRef) match++;
      }
    }
    console.log('读回确认：' + match + ' / ' + targets2.length + ' 个窗口已实际生效为 ' + modelRef);
  }
  if (opts.compact) {
    console.log('--- 压缩上下文（防切到上下文短的模型时爆上下文）---');
    const targetCap = await modelCap(modelRef);
    console.log('  目标模型上下文上限：' + (targetCap ? targetCap : '读不到（按各窗口自己的上限判断）'));
    for (const s of targets) {
      const used = Number(s.totalTokens || 0);
      // 用「目标模型上限」与「该窗口当前上限」里更小的那个做判断，切短上下文才不会漏压
      const ownCap = Number(s.contextTokens || 0);
      const cap = targetCap > 0 ? (ownCap > 0 ? Math.min(targetCap, ownCap) : targetCap) : ownCap;
      // 已用量低于上限八成：不用压（省时间、省显存）
      if (cap && used && used < cap * 0.8) {
        console.log('  ' + nameOf(s) + ' → 已用 ' + used + ' 低于上限 ' + cap + '，不用压');
        continue;
      }
      const cr = await call('sessions.compact', { key: s.key }, 180000);
      const cp = parse(cr);
      if (!cp.ok) { console.log('  ' + nameOf(s) + ' 压缩失败：' + cp.raw.slice(0, 80)); continue; }
      const o = cp.json;
      console.log('  ' + nameOf(s) + ' → ' + (o.compacted ? '已压缩' : '不用压缩（' + (o.reason || '已压缩过') + ')'));
    }
  }
  return 0;
}

async function models() {
  const r = await call('models.list', {}, 60000);
  const p = parse(r);
  if (!p.ok) { console.log('读模型清单失败：' + p.raw); return 1; }
  const list = (p.json.models || []).filter(m => m.available !== false);
  if (has('json')) {
    const dump = list.map(m => ({ key: String(m.key || m.id || ''), name: m.name || m.key || '', provider: m.provider || m.providerId || '', ctx: Number(m.contextTokens || m.contextWindow || 0) || null, think: m.thinkingDefault === undefined ? null : String(m.thinkingDefault), local: /^(strata|llamacpp|llamacpp-vision)$/.test(String(m.provider || m.providerId || '')) }));
    const txt = JSON.stringify(dump);
    if (get('out')) { try { fs.writeFileSync(get('out'), txt, 'utf8'); } catch (e) { /* ignore */ } }
    console.log(txt);
    return 0;
  }
  for (const m of list) {
    console.log('  ' + (m.key || '') + ' | ' + (m.contextTokens || m.contextWindow || '上限不明') + ' | ' + (m.local ? '本地' : '云端') + ' | ' + (m.name || ''));
  }
  return 0;
}

const argv = process.argv.slice(2);
const cmd = (argv[0] || 'list').toLowerCase();
const get = (f) => { const i = argv.indexOf('--' + f); return i >= 0 ? argv[i + 1] : null; };
const has = (f) => argv.includes('--' + f);
if (cmd === 'list') { list().then(c => process.exit(c || 0)); }
else if (cmd === 'models') { models().then(c => process.exit(c || 0)); }
else if (cmd === 'set') {
  set(get('model'), { sys: has('sys'), compact: has('compact'), dry: has('dry'), scope: (get('scope') || 'chat').toLowerCase() })
    .then(c => process.exit(c || 0));
} else {
  console.log('用法:');
  console.log('  node model-windows.cjs list [--scope chat|sys|all] [--json --out <文件>]   # 看各窗口现在用哪个模型');
  console.log('  node model-windows.cjs models [--json --out <文件>]                        # 列可用模型与上下文上限');
  console.log('  node model-windows.cjs set --model <provider/模型名> --dry                 # 只报会换谁');
  console.log('  node model-windows.cjs set --model <...>                                   # 换所有对话窗口');
  console.log('  node model-windows.cjs set --model <...> --scope sys                       # 只换定时任务/心跳窗口');
  console.log('  node model-windows.cjs set --model <...> --sys                             # 对话 + 系统窗口都换');
  console.log('  node model-windows.cjs set --model <...> --compact                         # 换完再压上下文（切小模型时用）');
  process.exit(1);
}
