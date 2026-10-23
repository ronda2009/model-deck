// model-hb.cjs — 读/改心跳与上下文压缩用的模型（写 openclaw.json，改前先备份）
const fs = require('node:fs');
const path = require('node:path');

function cfgPath() {
  const c = [
    process.env.OPENCLAW_CONFIG,
    path.join(process.env.USERPROFILE || '', '.openclaw', 'openclaw.json'),
  ].filter(Boolean);
  for (const p of c) { try { if (fs.existsSync(p)) return p; } catch (e) {} }
  return null;
}
const P = cfgPath();
if (!P) { console.log('找不到 openclaw.json'); process.exit(1); }

function read() { return JSON.parse(fs.readFileSync(P, 'utf8')); }
function info(d) {
  const def = (d.agents && d.agents.defaults) || {};
  return {
    heartbeat: (def.heartbeat && def.heartbeat.model) || '',
    compaction: (def.compaction && def.compaction.model) || '',
    primary: (def.model && def.model.primary) || '',
    heartbeatTarget: (def.heartbeat && def.heartbeat.target) || '',
    source: P,
    note: '改这两项需重启网关才生效（官方 hot-reload 分类：需重启类）',
  };
}

const argv = process.argv.slice(2);
const cmd = (argv[0] || 'get').toLowerCase();
const flag = (n) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : ''; };

if (cmd === 'get') {
  console.log(JSON.stringify(info(read()), null, 1));
  process.exit(0);
}

if (cmd === 'set') {
  const model = flag('--model');
  if (!model) { console.log('缺 --model <provider/model>'); process.exit(1); }
  const dry = argv.includes('--dry');
  const d = read();
  const before = info(d);
  if (dry) {
    console.log(JSON.stringify({ mode: 'dry', willChange: ['agents.defaults.heartbeat.model', 'agents.defaults.compaction.model'], from: before.heartbeat + ' / ' + before.compaction, to: model, note: before.note }));
    process.exit(0);
  }
  // 备份：带时间戳，同目录，名字含 hb-bak
  const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 15);
  const bak = path.join(path.dirname(P), 'openclaw.json.hb-bak-' + stamp);
  fs.writeFileSync(bak, fs.readFileSync(P, 'utf8'), 'utf8');
  const def = d.agents.defaults = d.agents.defaults || {};
  if (def.heartbeat) def.heartbeat.model = model;
  if (def.compaction) def.compaction.model = model;
  fs.writeFileSync(P, JSON.stringify(d, null, 2), 'utf8');
  // 读回确认：重新读文件，数出真正生效的两项
  const back = info(read());
  const ok = (back.heartbeat === model) && (back.compaction === model);
  console.log(JSON.stringify({
    tried: 2, confirmed: (back.heartbeat === model ? 1 : 0) + (back.compaction === model ? 1 : 0),
    model: model, ok: ok, backup: bak,
    before: { heartbeat: before.heartbeat, compaction: before.compaction },
    after: { heartbeat: back.heartbeat, compaction: back.compaction },
    note: ok ? '写回确认成功；需重启网关才生效' : '读回不一致，检查文件',
  }));
  process.exit(0);
}

console.log('未知命令 ' + cmd + '；用 get / set --model <ref> [--dry]');
process.exit(1);
