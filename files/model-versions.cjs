// model-versions.cjs — 只读：读本机版本 + 官方最新，写 console-versions.json（页⑤用）
// 用法：node model-versions.cjs [--out <文件>]
// 本机：OpenClaw = npm 全局 package.json；Strata = <TIER_DIR>\engine\BUILD.json
// 官方：GitHub Releases API（tag_name + published_at），失败则留空不崩
const fs = require('node:fs');
const path = require('node:path');

const PACKDIR = path.dirname(path.resolve(__filename));
const argv = process.argv.slice(2);
const outIdx = argv.indexOf('--out');
const OUT = outIdx >= 0 ? argv[outIdx + 1] : path.join(PACKDIR, 'console-versions.json');

function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } }

// 本机 OpenClaw 版本
function localOpenclaw() {
  const cands = [
    path.join(process.env.APPDATA || '', 'npm', 'node_modules', 'openclaw', 'package.json'),
  ];
  for (const c of cands) { const j = readJson(c); if (j && j.version) return String(j.version); }
  return '';
}
// 本机 Strata 引擎版本
function localStrata() {
  const cands = [
    'D:\\06.AItools\\Strata\\engine\\BUILD.json',
    path.join(PACKDIR, 'engine', 'BUILD.json'),
  ];
  const pj = readJson(path.join(PACKDIR, 'console-paths.json'));
  if (pj && pj.TIER_DIR) cands.unshift(path.join(String(pj.TIER_DIR), 'engine', 'BUILD.json'));
  for (const c of cands) { const j = readJson(c); if (j && j.version) return String(j.version); }
  return '';
}

async function ghLatest(repo) {
  try {
    const r = await fetch('https://api.github.com/repos/' + repo + '/releases?per_page=5', {
      headers: { 'User-Agent': 'model-console/1.0', 'Accept': 'application/vnd.github+json' },
      signal: AbortSignal.timeout(12000),
    });
    if (!r.ok) return { latest: '', when: '', note: 'HTTP ' + r.status };
    const list = await r.json();
    const pre = (Array.isArray(list) ? list : []).filter(x => x && x.tag_name);
    if (!pre.length) return { latest: '', when: '', note: '无 release' };
    return { latest: String(pre[0].tag_name).replace(/^v/, ''), when: String(pre[0].published_at || '').slice(0, 10), note: '' };
  } catch (e) { return { latest: '', when: '', note: String(e && e.message || e).slice(0, 60) }; }
}

(async () => {
  const [oc, st] = await Promise.all([ghLatest('openclaw/openclaw'), ghLatest('Niko1221/Strata')]);
  const data = {
    ts: new Date().toISOString().slice(0, 19).replace('T', ' '),
    openclawLocal: localOpenclaw(),
    openclawLatest: oc.latest,
    openclawLatestDate: oc.when,
    openclawNote: oc.note,
    strataLocal: localStrata(),
    strataLatest: st.latest,
    strataLatestDate: st.when,
    strataNote: st.note,
    links: {
      openclaw: 'https://github.com/openclaw/openclaw/releases',
      docs: 'https://docs.openclaw.ai',
      strata: 'https://github.com/Niko1221/Strata/releases',
      llama: 'https://github.com/ggml-org/llama.cpp/releases',
      model: 'https://huggingface.co/Qwen/Qwen3.8-Flash-Next',
    },
  };
  fs.writeFileSync(OUT, JSON.stringify(data, null, 1), 'utf8');
  console.log('本机 OpenClaw=' + data.openclawLocal + ' Strata=' + data.strataLocal);
  console.log('官方最新 OpenClaw=' + (data.openclawLatest || '?') + ' (' + (data.openclawLatestDate || '?') + ') Strata=' + (data.strataLatest || '?') + ' (' + (data.strataLatestDate || '?') + ')');
  if (data.openclawNote) console.log('openclaw 抓取提示：' + data.openclawNote);
  if (data.strataNote) console.log('strata 抓取提示：' + data.strataNote);
  console.log('已写 ' + OUT);
})();
