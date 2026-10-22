// model-scan.cjs — [2026-10-23 v30] 扫本机模型盘，把「清单里没有的 gguf」补进页① 启停清单
// 为什么：原来页① 只有内置 11 条（用户机器上的模型），别人机器模型更多/更少就对不上。
//   用户 2026-10-23：「第一页应该是扫描本地模型的清单，根据这个清单来判断启停，而不是固定的」
// 用法：node model-scan.cjs --out console-tiers.scanned.json
// 规则：
//   · 扫 console-paths.json 里 MODELS 指的模型盘（没配就扫脚本所在盘常见位置），递归两层找 *.gguf
//   · 跳过 mmproj（那是视觉模型的附属文件，不单独起）
//   · 跳过清单里已经用到的 gguf（界面/执行器读同一份扫描结果，重复列没意义）
//   · 名字里带 vl/vision/clip 的当视觉条目（act=vl），其余当对话条目（act=27b，走 :8090 路由）
//   · 显存门槛按文件大小粗估：文件 GiB×1024 + 2048（上下文与运行时开销），界面还会用实测校准覆盖
const fs = require('node:fs');
const path = require('node:path');

const args = process.argv.slice(2);
let OUT = 'console-tiers.scanned.json';
for (let i = 0; i < args.length; i++) if (args[i] === '--out' && args[i + 1]) OUT = args[++i];

const HERE = __dirname;
const jread = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } };

// 清单里已用到的 gguf（内置表写在 ps1/run.ps1 里，这里从两个脚本的文本里抓文件名，避免两边规则不一致）
//   注意：不把「本脚本自己生成的那份」算进来 —— 否则第二次扫就把自己扫过的全跳过了，新加的模型文件反而扫不到
const used = new Set();
for (const f of ['model-console.ps1', 'model-console-run.ps1', 'console-tiers.json', 'console-tiers.example.json']) {
  const p = path.join(HERE, f);
  let t = '';
  try { t = fs.readFileSync(p, 'utf8'); } catch { continue; }
  for (const m of t.matchAll(/([A-Za-z0-9._\-\u4e00-\u9fff]+\.gguf)/g)) used.add(m[1].toLowerCase());
}

// 模型盘：优先 console-paths.json 的 MODELS，再退到脚本目录、再退到常见盘
const cfg = jread(path.join(HERE, 'console-paths.json')) || {};
const roots = [];
if (cfg.MODELS) roots.push(String(cfg.MODELS));
roots.push(HERE);
for (const d of ['D:\\03.AImodels', 'C:\\03.AImodels', 'E:\\models', 'D:\\models']) roots.push(d);

function scanDir(root, depth, acc) {
  if (depth > 2 || acc.length > 400) return;
  let ents = [];
  try { ents = fs.readdirSync(root, { withFileTypes: true }); } catch { return; }
  for (const e of ents) {
    const full = path.join(root, e.name);
    if (e.isDirectory()) { if (depth < 2) scanDir(full, depth + 1, acc); continue; }
    if (!/\.gguf$/i.test(e.name)) continue;
    acc.push({ file: e.name, full });
  }
}

const found = [];
const seenRoot = new Set();
for (const r of roots) {
  if (!r || seenRoot.has(r.toLowerCase())) continue;
  seenRoot.add(r.toLowerCase());
  try { if (!fs.statSync(r).isDirectory()) continue; } catch { continue; }
  scanDir(r, 0, found);
  if (found.length) break;   // 命中第一个真实模型盘就够，别把全机器都扫进来
}

const rows = [];
const names = new Set();
for (const f of found) {
  const low = f.file.toLowerCase();
  if (low.includes('mmproj')) continue;
  if (used.has(low)) continue;
  let sz = 0;
  try { sz = fs.statSync(f.full).size; } catch { continue; }
  if (sz < 200 * 1024 * 1024) continue;   // 200MB 以下不是能对话的模型（ tokenizer/投影层之类）
  const isVl = /(vl|vision|clip)/i.test(f.file);
  const isEmbed = /embed/i.test(f.file);
  const gib = sz / 1024 / 1024 / 1024;
  const need = Math.round(gib * 1024 + 2048);
  let key = f.file.replace(/\.gguf$/i, '').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-+|-+$/g, '').toLowerCase();
  if (key.length > 28) key = key.slice(0, 28).replace(/-+$/, '');
  if (!key) key = 'model' + (rows.length + 1);
  while (names.has(key)) key = key + '2';
  names.add(key);
  const row = {
    key,
    name: f.file.replace(/\.gguf$/i, '') + (isVl ? '（视觉）' : isEmbed ? '（嵌入）' : ''),
    need,
    dual: false,
    act: isVl ? 'vl' : '27b',
    engine: 'llama',
    id: key,
    gguf: f.file,
    ctx: isEmbed ? 2048 : 32768,
    note: '本机扫到的（文件 ' + gib.toFixed(1) + ' GB）',
  };
  if (isVl) row.port = 8096;
  rows.push(row);
}

rows.sort((a, b) => a.need - b.need);
const payload = {
  __说明: '本文件由 model-scan.cjs 自动生成（扫本机模型盘得到的补充清单），界面与执行器都会读它。删掉会自动重扫；手写的清单请用 console-tiers.json。',
  __生成时间: new Date().toISOString(),
  __扫描根: roots.filter(r => { try { return fs.statSync(r).isDirectory(); } catch { return false; } })[0] || '',
  entries: rows,
};
try {
  fs.writeFileSync(path.join(HERE, OUT), JSON.stringify(payload, null, 2), 'utf8');
  console.log('SCAN-OK 条目 ' + rows.length + ' 个（扫到 gguf ' + found.length + ' 个，跳过已列 ' + (found.length - rows.length - found.filter(f => f.file.toLowerCase().includes('mmproj')).length) + ' 个）');
  for (const r of rows.slice(0, 12)) console.log('  ' + r.key + '  ' + r.name + '  need=' + r.need + '  act=' + r.act);
} catch (e) { console.log('SCAN-BAD ' + e.message); process.exitCode = 1; }
