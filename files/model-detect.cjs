// model-detect.cjs — 本机环境自检与路径自动定位：pwsh / node / nvidia-smi / openclaw / Strata / llama-server / 模型盘
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const { execSync } = require('node:child_process');

const args = process.argv.slice(2);
let OUT = 'console-selfcheck.json';
let WRITE = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--out' && args[i + 1]) { OUT = args[++i]; }
  else if (args[i] === '--write') { WRITE = true; }
}
const HERE = __dirname;
const UP = process.env.USERPROFILE || process.env.HOME || '';

function sh(cmd) {
  try { return execSync(cmd, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 9000 }).trim(); } catch { return ''; }
}
function where(c) {
  const o = sh('where.exe ' + c);
  if (!o) return '';
  const lines = o.split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  return lines[0] || '';
}
function ex(p) { try { return !!p && fs.existsSync(p); } catch { return false; } }
function jread(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } }
function portOpen(port) {
  return new Promise(res => {
    const s = net.createConnection({ host: '127.0.0.1', port }, () => { s.destroy(); res(true); });
    s.setTimeout(400, () => { s.destroy(); res(false); });
    s.on('error', () => { s.destroy(); res(false); });
  });
}
// 浅扫某盘根目录（两层），找匹配目录/文件；找不到返回 ''
function scan(dr, dirRe, fileRe, maxDepth) {
  const hits = [];
  const seen = new Set();
  function walk(dir, depth) {
    if (depth > maxDepth || hits.length >= 6) return;
    let ents;
    try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (dirRe && dirRe.test(e.name)) { hits.push(p); if (seen.size > 4000) return; seen.add(p); }
        if (depth < maxDepth && !/Windows|Program Files|node_modules|\$Recycle/i.test(e.name)) walk(p, depth + 1);
      } else if (fileRe && fileRe.test(e.name)) { hits.push(p); seen.add(p); }
    }
  }
  try { if (fs.existsSync(dr)) walk(dr, 1); } catch {}
  return hits[0] || '';
}
function firstExisting(list) { for (const p of list) if (ex(p)) return p; return ''; }

async function main() {
  // ---------- 探测 ----------
  const pwsh = firstExisting(['C:\\Program Files\\PowerShell\\7\\pwsh.exe']) || where('pwsh');
  const node = where('node');
  const smi = where('nvidia-smi');
  const npmRoot = path.join(UP, 'AppData', 'Roaming', 'npm', 'node_modules');
  const ocCli = firstExisting([path.join(npmRoot, 'openclaw', 'openclaw.mjs')]);
  const ocPkg = firstExisting([path.join(npmRoot, 'openclaw', 'package.json')]);
  const ocDir = firstExisting([path.join(UP, '.openclaw')]);

  // Strata 引擎目录：先认常见位置，再扫盘
  let tierDir = firstExisting(['D:\\06.AItools\\Strata', 'D:\\Strata', 'C:\\Strata']);
  if (!tierDir) tierDir = scan('D:\\', /^strata$/i, null, 2) || scan('C:\\', /^strata$/i, null, 2);
  // 工具目录 = 放 strata-router.py / strata-start-all-hidden.vbs 的那个目录
  let toolDir = '';
  for (const cand of ['D:\\06.AItools', path.dirname(tierDir || ''), 'C:\\']) {
    if (cand && (ex(path.join(cand, 'strata-router.py')) || ex(path.join(cand, 'strata-start-all-hidden.vbs')))) { toolDir = cand; break; }
  }
  if (!toolDir) toolDir = scan('D:\\', null, /^strata-router\.py$/i, 2) ? path.dirname(scan('D:\\', null, /^strata-router\.py$/i, 2)) : '';

  // llama.cpp 引擎与模型盘
  let llamaExe = firstExisting(['D:\\06.AItools\\llama.cpp\\b11541\\llama-server.exe']);
  if (!llamaExe) {
    const hit = scan('D:\\', /^llama\.cpp$/i, /^llama-server\.exe$/i, 3);
    if (hit) llamaExe = hit;
  }
  let modelsDir = firstExisting(['D:\\03.AImodels\\llama-router', 'D:\\03.AImodels']);
  if (!modelsDir) modelsDir = scan('D:\\', /^llama-router$/i, /\.gguf$/i, 3);

  const gwRescue = toolDir ? path.join(toolDir, 'openclaw', 'workspace', 'tools', 'gateway-rescue.ps1') : '';
  const cacheClr = toolDir ? path.join(toolDir, 'strata-cache-clear.ps1') : '';
  const llmSvc = toolDir ? path.join(toolDir, 'llm-service.ps1') : '';

  // 版本
  let ocVer = '';
  const pk = jread(ocPkg); if (pk && pk.version) ocVer = String(pk.version);
  let enVer = '';
  const bj = jread(path.join(tierDir || '', 'engine', 'BUILD.json')); if (bj && bj.version) enVer = String(bj.version);

  // 服务在跑状态
  const p8080 = await portOpen(8080);
// 大块头端口不写死：8080 是自建路由，官方 Strata 默认 8095。找「回 /health 且 service=strata」的那个口。
async function healthAt(port) {
  try {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 900);
    const r = await fetch('http://127.0.0.1:' + port + '/health', { signal: ctl.signal });
    clearTimeout(t);
    if (!r.ok) return null;
    const j = await r.json();
    return (j && j.service === 'strata') ? j : null;
  } catch { return null; }
}
let bigPort = 0, bigModel = '';
for (const p of [8080, 8095, 8081, 8082, 8100]) {
  if (!(await portOpen(p))) continue;
  const h = await healthAt(p);
  if (h) { bigPort = p; bigModel = String(h.model || ''); break; }
}
  const p18789 = await portOpen(18789);
  const p8090 = await portOpen(8090);
  const p8096 = await portOpen(8096);

  // 显卡
  let gpuLine = '';
  let gpuCount = 0;
  if (smi) {
    const o = sh('"' + smi + '" --query-gpu=index,name,memory.total --format=csv,noheader,nounits');
    const rows = (o || '').split(/\r?\n/).filter(l => l.trim());
    gpuCount = rows.length;
    gpuLine = rows.map(r => { const p = r.split(','); return (p[1] || '').trim() + ' ' + Math.round(parseInt(p[2] || '0', 10) / 1024) + 'G'; }).join(' + ');
  }

  const items = [
    { k: 'pwsh', name: 'PowerShell 7（起停/换模型要用）', ok: !!pwsh, path: pwsh, note: pwsh ? '' : '没装：装 PowerShell 7（winget install Microsoft.PowerShell）' },
    { k: 'node', name: 'node（读窗口/任务/版本要用）', ok: !!node, path: node, note: node ? '' : '没装：装 node LTS' },
    { k: 'nvidia-smi', name: 'nvidia-smi（显存与功率要用）', ok: !!smi, path: smi, note: smi ? (gpuCount + ' 张卡：' + gpuLine) : '没装：装 NVIDIA 驱动' },
    { k: 'openclaw', name: 'OpenClaw 命令行（定时任务/换窗口模型要用）', ok: !!ocCli, path: ocCli, note: (ocCli ? ('版本 ' + (ocVer || '?')) : '没装：npm install -g openclaw') },
    { k: 'gateway', name: 'OpenClaw 网关（:18789）', ok: p18789, path: p18789 ? 'http://127.0.0.1:18789/' : '', note: p18789 ? '在跑' : '未在跑（页②有救援按钮）' },
    { k: 'strata', name: 'Strata 引擎目录（档位配置在这儿）', ok: !!tierDir, path: tierDir, note: tierDir ? ('引擎版本 ' + (enVer || '?')) : '找不到 Strata 目录' },
    { k: 'router', name: '大块头服务（自动找端口）', ok: bigPort > 0, path: bigPort ? ('http://127.0.0.1:' + bigPort + '/') : '', note: bigPort ? ('在跑 :' + bigPort + (bigModel ? '，模型 ' + bigModel : '')) : '没找到（试了 8080/8095/8081/8082/8100；页①点「起」会自动拉起）' },
    { k: 'tools', name: '启动脚本目录（strata-router.py / 启动 vbs）', ok: !!toolDir, path: toolDir, note: toolDir ? '' : '找不到启动脚本，起大块头会失败' },
    { k: 'llama', name: 'llama-server.exe（27B / 视觉要用）', ok: !!llamaExe, path: llamaExe, note: llamaExe ? '' : '找不到 llama-server.exe，27B 与视觉起不来' },
    { k: 'models', name: '模型盘（gguf 文件）', ok: !!modelsDir, path: modelsDir, note: modelsDir ? '' : '找不到模型目录' },
    { k: 'llmrouter', name: '27B 路由（:8090）', ok: p8090, path: p8090 ? 'http://127.0.0.1:8090/' : '', note: p8090 ? '在跑' : '未在跑（页①点「起」会拉起）' },
    { k: 'vision', name: '视觉模型（:8096）', ok: p8096, path: p8096 ? 'http://127.0.0.1:8096/' : '', note: p8096 ? '在跑' : '未在跑' },
    { k: 'helpers', name: '辅助脚本（网关救援 / 清缓存 / llm-service）', ok: !!(gwRescue && ex(gwRescue)), path: gwRescue, note: (gwRescue && ex(gwRescue)) ? '' : '缺网关救援脚本，页②按钮会失败' },
  ];

  // ---------- 路径建议 ----------
  const sugg = {
    PWSH: pwsh, NODE: node, NVIDIA_SMI: smi, OPENCLAW_CLI: ocCli,
    TIER_DIR: tierDir, TOOLDIR: toolDir, MODELS: modelsDir, LLAMA_EXE: llamaExe,
    GWRESCUE: (gwRescue && ex(gwRescue)) ? gwRescue : '', CACHECLR: ex(cacheClr) ? cacheClr : '', LLMSVC: ex(llmSvc) ? llmSvc : '',
  };

  const pf = path.join(HERE, 'console-paths.json');
  let fixed = [];
  if (WRITE) {
    const cur = jread(pf) || {};
    const bak = pf + '.bak-detect-' + (new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14));
    const out = Object.assign({}, cur);
    for (const [k, v] of Object.entries(sugg)) {
      if (!v) continue;
      const nowv = String(cur[k] || '');
      if (nowv && nowv !== v && !ex(nowv)) { out[k] = v; fixed.push(k + ': ' + nowv + ' → ' + v); }
      else if (!nowv) { out[k] = v; fixed.push(k + ': (空) → ' + v); }
    }
    if (fixed.length) {
      try { fs.writeFileSync(bak, JSON.stringify(cur, null, 2), 'utf8'); } catch {}
      fs.writeFileSync(pf, JSON.stringify(out, null, 2), 'utf8');
    }
  }

  const res = {
// 用本地时间：界面别处（日志/功率/模型清单）都是本地时间，这里写 UTC 会让用户看错 8 小时
    at: (function () {
      const d = new Date();
      const p = n => String(n).padStart(2, '0');
      return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
    })(),
    okCount: items.filter(i => i.ok).length,
    missCount: items.filter(i => !i.ok).length,
    items, sugg, fixed,
  };
  fs.writeFileSync(OUT, JSON.stringify(res, null, 2), 'utf8');
  console.log('selfcheck ok=' + res.okCount + ' miss=' + res.missCount + ' fixed=' + fixed.length + ' -> ' + OUT);
  for (const i of items) if (!i.ok) console.log('  缺：' + i.name + ' — ' + i.note);
}
main().catch(e => { console.log('detect 失败: ' + e.message); process.exit(1); });
