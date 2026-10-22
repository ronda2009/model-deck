# model-console.ps1 — 模型服务控制台 v30（按卡起停 · 页③下拉选模型 · 页④定时任务(要模型在上)+单个切换+心跳可切 · 页⑤功率(要管理员)+版本+链接 · 先弹窗后采集 · exe 内置程序文件+图标+版本信息 · 右上角 5 秒自动刷新）
# 源码改完必须重新编译：pwsh -File D:\06.AItools\model-console-build.ps1
param([switch]$Test, [switch]$Layout, [string]$Shot = '', [int]$ShotPage = 1, [switch]$AutoRefresh, [switch]$NoPower)   # [2026-10-19 v17] -NoPower = 页⑤不读功率信息（显卡读不到时防崩）   # [2026-10-19 v13] -Shot <png> : 窗口自己截图后自动关闭（无鼠标、无黑框，用于自查美观）；-ShotPage 2 = 截页②；[2026-10-19 v16] -AutoRefresh = 打开后自动跑两个「刷新列表」（只读），配合 -Shot 自查列表能否真被填上
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ---------- [2026-10-19 v15] 便携包：脚本指向自己所在文件夹 ----------
# 本文件夹 = 唯一家：状态文件、日志、窗口清单缓存都写这里；拷走整个文件夹就能搬到别的机器。
# 同目录若有 console-paths.json，用它的值覆盖下面的绝对路径（换机器只改那个文件，不改代码）。
$PACKDIR  = $PSScriptRoot
$PATHF    = Join-Path $PACKDIR 'console-paths.json'
# [2026-10-20 v22] 用户要「装到任何电脑、打开自己检测」：启动脚本目录（strata-router.py / 启动 vbs 所在）与 node 路径
$TOOLDIR  = 'D:\06.AItools'   # [2026-10-21 v25] 修隐藏坏字符：原值是 'D:' + 控制字符0x06 + '.AItools'（写补丁时反斜杠06 被当成八进制转义），配置文件一缺就是废路径
$NODE     = 'node'
$SELFJS   = Join-Path $PACKDIR 'model-detect.cjs'
$SELFF    = Join-Path $PACKDIR 'console-selfcheck.json'
$CALF     = Join-Path $PACKDIR 'console-calib.json'   # [2026-10-20 v22] 每档实测显存占用（自动校准，界面读）
$RUN      = Join-Path $PACKDIR 'model-console-run.ps1'
# [2026-10-23 v29] pwsh 位置运行时解析：商店版装在 WindowsApps 下，写死 MSI 路径在别人机器上不存在，
#   点任何按钮都报「系统找不到指定的文件」。顺序 $PSHOME → MSI 默认 → PATH；console-paths.json 的 PWSH 可覆盖。
$mcPsHome = if ($PSHOME -and (Test-Path (Join-Path $PSHOME 'pwsh.exe'))) { Join-Path $PSHOME 'pwsh.exe' } else { '' }
$mcPsMsi   = 'C:\Program Files\PowerShell\7\pwsh.exe'
$mcPsPath   = if ((Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)) { (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)[0].Source } else { '' }
$PWSH       = if ($mcPsHome) { $mcPsHome } elseif (Test-Path $mcPsMsi) { $mcPsMsi } elseif ($mcPsPath) { $mcPsPath } else { '' }
$LOGDIR   = Join-Path $PACKDIR 'logs'
$TIER_DIR = 'D:\06.AItools\Strata'
$STATEF   = Join-Path $PACKDIR 'console-state.json'
$WINF     = Join-Path $PACKDIR 'console-windows.json'    # 对话窗口清单缓存（执行器写、界面读）
$SYSF     = Join-Path $PACKDIR 'console-syswindows.json' # [2026-10-19 v15] 定时任务/心跳窗口缓存（v16 起界面不用它）
$CRONF    = Join-Path $PACKDIR 'console-crons.json'      # [2026-10-19 v16] 定时任务定义缓存
$MODF     = Join-Path $PACKDIR 'console-models.json'     # [2026-10-19 v17] 可换模型清单（页③下拉菜单的数据源）
$VERF     = Join-Path $PACKDIR 'console-versions.json'     # [2026-10-19 v17] 版本与官方链接（页⑤）
# [2026-10-20 v18] 后台采集直接调这三个工具（不绕执行器，省一次 pwsh 启动）
$WINCJS    = Join-Path $PACKDIR 'model-windows.cjs'
$CRONJS    = Join-Path $PACKDIR 'model-crons.cjs'
$VERJS     = Join-Path $PACKDIR 'model-versions.cjs'
$HBCJS     = Join-Path $PACKDIR 'model-hb.cjs'
$CRONF2   = Join-Path $PACKDIR 'console-crons.json'      # [2026-10-19 v16] 定时任务「定义」清单：中文名 + 何时跑 + 用哪个模型
$HBF      = Join-Path $PACKDIR 'console-hbmodel.json'    # [2026-10-19 v16] 心跳/压缩现在用哪个模型（只读 openclaw.json）
$CFGENT = $null; $CFGNOTES = $null; $CFGFNOTE = $null   # [2026-10-22 v26] 页⑥ 的清单/说明（数组类配置，单独接）
if (Test-Path $PATHF) {
  try {
    $pj = Get-Content $PATHF -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($pj.ENTRIES)    { $CFGENT   = $pj.ENTRIES }
    if ($pj.ENTRYNOTES) { $CFGNOTES = $pj.ENTRYNOTES }
    if ($pj.FILENOTES)  { $CFGFNOTE = $pj.FILENOTES }
    foreach ($p in @($pj.PSObject.Properties)) {
      if ($p.Value -is [System.Array]) { continue }
      $v = [string]$p.Value
      if ($v -and $p.Name -notlike '_*') { Set-Variable -Name $p.Name -Value $v }
    }
  } catch { }
}
# [2026-10-22 v26] 发布准备：页⑥「常用文件」要用这两个位置，从配置/环境变量推，不再写死本机路径
$MODELDISK = if ($pj -and $pj.MODELS) { [string]$pj.MODELS } else { 'D:\03.AImodels' }
$DOCSF = if ($env:OPENCLAW_DOCS) { $env:OPENCLAW_DOCS } elseif ($GWRESCUE) { Join-Path (Split-Path (Split-Path $GWRESCUE -Parent) -Parent) 'docs' } else { '' }
$RUNLOG   = Join-Path $LOGDIR 'console-run.log'   # 覆盖完再算，避免用旧 LOGDIR

function LogErr([string]$m) {
  try { if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Force -Path $LOGDIR | Out-Null }
    ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m) | Out-File -FilePath $RUNLOG -Append -Encoding UTF8 } catch {}
}

LogErr 'v30 启动（显卡识别前）'

# ---------- 显卡自动识别 ----------
$GPUS = @()
foreach ($r in @(& nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>$null)) {
  $p = "$r" -split ','
  if ($p.Count -lt 3) { continue }
  $dig = ($p[2] -replace '[^0-9]', '')
  if (-not $dig) { continue }
  $mib = [int]$dig
  if ($mib -le 0) { continue }
  $name = ($p[1].Trim() -replace 'NVIDIA GeForce ', '') -replace 'NVIDIA ', ''
  $GPUS += [pscustomobject]@{ Id = [int]$p[0].Trim() + 1; Smi = [int]$p[0].Trim(); Name = $name; MiB = $mib; GB = [math]::Round($mib / 1024) }
}
if ($GPUS.Count -eq 0) { LogErr '读不到显卡'; Write-Host '读不到显卡'; return }
# 首卡 = strata 配置里 gpu 数组的第一个 = nvidia-smi 索引最小的那张（本机 3090），不是显存最小的
$FIRST_CARD_ID  = ($GPUS | Sort-Object Smi)[0].Id
$ANCHOR_CARD_ID = ($GPUS | Sort-Object MiB)[-1].Id

function ReadReserve {
  $f = Join-Path $TIER_DIR 'strata-q2x.json'   # [2026-10-16] 读无删减 Q2X 档的安全垫（五档同值）  try { $t = Get-Content $f -Raw } catch { return @{ first = 1536; later = 300 } }
  $a = [regex]::Match($t, '--vram-reserve-mib",\s*"(\d+)"')
  $b = [regex]::Match($t, '--vram-reserve-later-mib",\s*"(\d+)"')
  return @{ first = $(if ($a.Success) { [int]$a.Groups[1].Value } else { 1536 }); later = $(if ($b.Success) { [int]$b.Groups[1].Value } else { 300 }) }
}
# [2026-10-20 v22] 显存需求自动校准：console-calib.json 里有该档实测占用就用实测（+512 余量），没有才用表里的占位值
$global:CAL = @{}
function LoadCalib {
  try {
    if (-not (Test-Path $CALF)) { return }
    $j = Get-Content $CALF -Raw -Encoding UTF8 | ConvertFrom-Json
    $h = @{}
    foreach ($r in @($j)) { if ($r.tier) { $h[[string]$r.tier] = [int]$r.used } }
    if ($h.Count -gt 0) { $global:CAL = $h }
  } catch { }
}
LoadCalib
# [2026-10-22 v27] 起停用的「档位清单」可外置：同目录这个文件存在且读得进去就用它，否则用内置表。
#   注意别和 console-models.json 搞混：那个是页③「可换模型」下拉的缓存（执行器自动生成，内容完全不同）。
$MODELSF = Join-Path $PACKDIR 'console-tiers.json'

function NeedOf($m) {
  $k = [string]$m.Key
  if ($global:CAL.ContainsKey($k)) { return [int]$global:CAL[$k] + 512 }
  return [int]$m.Need
}
$RES = ReadReserve
function CardReserve([int]$id) { if ($id -eq $FIRST_CARD_ID) { return $RES.first } return $RES.later }

# ---------- 模型表（顺序同旧 bat 菜单） ----------
# [2026-10-22 v27] 同目录有 console-tiers.json 就用它（复制 console-tiers.example.json 改内容）；读不到用下面的内置表。
$MODELS_DEF = @(
  # Need = 两卡合计需占用 MiB。Q2X 为实测（2026-10-19 09:05 运行中：3090 用 23713 + 3080 用 16734 = 40447）；
  # 其余四档同基座模型，引擎按可用显存自适应，暂同值，待各档真起后用 nvidia-smi 校准。
  [pscustomobject]@{ Key='iq2x';  Name='大块头 IQ2X（无删减 IQ2_XS）·默认'; Need=40450; Dual=$true;  Act='big'  }
  [pscustomobject]@{ Key='q2x';   Name='大块头 Q2X（无删减 Q2_0）';        Need=40450; Dual=$true;  Act='big'  }
  [pscustomobject]@{ Key='iq3x';  Name='大块头 IQ3X（无删减 IQ3_XXS）';     Need=40450; Dual=$true;  Act='big'  }
  [pscustomobject]@{ Key='siq2x'; Name='S-IQ2x（Swift 无删减 IQ2_XS）';     Need=40450; Dual=$true;  Act='big'  }
  [pscustomobject]@{ Key='siq3x'; Name='S-IQ3x（Swift 无删减 IQ3_S）';      Need=40450; Dual=$true;  Act='big'  }
  [pscustomobject]@{ Key='c390';  Name='Qwen3.8-27B-coder390（编程27B）';                  Need=19000; Dual=$false; Act='27b'; Gguf='coder390-27b.gguf' }
  [pscustomobject]@{ Key='under'; Name='Qwen3.8-27B-GSQ-RCO（Underdog）';                  Need=8200;  Dual=$false; Act='27b'; Gguf='underdog-27b.gguf' }
  [pscustomobject]@{ Key='j27bx'; Name='Qwen3.8-27B-Abl（J27bX）';                         Need=16300; Dual=$false; Act='27b'; Gguf='j27bx.gguf' }
  [pscustomobject]@{ Key='b27bx'; Name='Qwen3.8-27B-BF16（B27bX）';                        Need=16300; Dual=$false; Act='27b'; Gguf='b27bx.gguf' }
  [pscustomobject]@{ Key='b27ks'; Name='Qwen3.8-27B-BF16-ks（B27bX-ks）';                  Need=15400; Dual=$false; Act='27b'; Gguf='b27bx-ks.gguf' }
  [pscustomobject]@{ Key='vl8';   Name='Qwen3-VL-8B-Q8_0（视觉·调图）';                     Need=9200;  Dual=$false; Act='vl';  Gguf='Qwen3-VL-8B-Instruct-Unredacted-MAX.Q8_0.gguf' }   # [2026-10-19 v14] 原名带 Instruct- 太长，240px 标签装不下被截断 → 缩短
)
$MODELS = $MODELS_DEF
if (Test-Path $MODELSF) {
  try {
    $mj = @(Get-Content $MODELSF -Raw -Encoding UTF8 | ConvertFrom-Json)
    $arr = @(); $seen = @{}
    foreach ($e in $mj) {
      $k = [string]$e.key
      if (-not $k) { continue }
      if ($k.StartsWith('__')) { continue }   # 带 __ 的键是说明文字，不算条目（同 console-paths.json 的约定）
      if ($seen[$k]) { LogErr ('档位清单里有重复 key，已跳过后面的：' + $k); continue }
      if ('big','27b','vl' -notcontains [string]$e.act) { LogErr ('档位清单里 ' + $k + ' 的 act 不认识（要 big / 27b / vl），已跳过：' + [string]$e.act); continue }
      if ([int]$e.need -le 0) { LogErr ('档位清单里 ' + $k + ' 的 need 不是正数，已跳过：' + $k); continue }
      $seen[$k] = $true
      $arr += [pscustomobject]@{ Key = $k; Name = [string]$e.name; Need = [int]$e.need; Dual = [bool]$e.dual; Act = [string]$e.act; Tier = [string]$e.tier; Port = [int]$e.port; Gguf = [string]$e.gguf }
    }
    if ($arr.Count -gt 0) { $MODELS = $arr; LogErr ('档位清单读自 console-tiers.json（' + $arr.Count + ' 个）') }
    else { LogErr '档位清单 console-tiers.json 里没有有效条目，本次改用内置表' }
  } catch { LogErr ('档位清单 console-tiers.json 读不了（多半是 JSON 写法不对：Windows 路径的反斜杠要写两个）：' + $_.Exception.Message + ' —— 本次改用内置表') }
}

# ---------- [2026-10-23 v30] 本机模型清单：扫模型盘，把内置清单没有的模型补进页① ----------
#   没有 console-tiers.scanned.json 就跑 model-scan.cjs 扫一次，要重扫就删掉它。
#   只做补充，不覆盖手写的 console-tiers.json（那份优先）。
$SCANJS = Join-Path $PACKDIR 'model-scan.cjs'
$SCNF   = Join-Path $PACKDIR 'console-tiers.scanned.json'
if (-not (Test-Path $SCNF) -and (Test-Path $SCANJS)) {
  try {
    LogErr '本机模型清单：开始扫描模型盘（首次启动扫一次，之后读缓存；删 console-tiers.scanned.json 可重扫）'
    $null = & $NODE $SCANJS --out $SCNF 2>&1
  } catch { LogErr ('本机模型清单扫描失败（内置清单照用，不影响）：' + $_.Exception.Message) }
}
if (Test-Path $SCNF) {
  try {
    $sj = Get-Content $SCNF -Raw -Encoding UTF8 | ConvertFrom-Json
    $seen2 = @{}
    foreach ($m in $MODELS) { $seen2[[string]$m.Key] = $true }
    $addN = 0
    foreach ($e in @($sj.entries)) {
      $k = [string]$e.key
      if (-not $k) { continue }
      if ($seen2[$k]) { continue }                                        # 内置/手写清单里已有 → 不重复列
      if ('big','27b','vl' -notcontains [string]$e.act) { continue }
      if ([int]$e.need -le 0) { continue }
      $seen2[$k] = $true
      $MODELS += [pscustomobject]@{ Key = $k; Name = [string]$e.name; Need = [int]$e.need; Dual = [bool]$e.dual; Act = [string]$e.act; Tier = [string]$e.tier; Port = [int]$e.port; Gguf = [string]$e.gguf }
      $addN++
    }
    if ($addN -gt 0) { LogErr ('本机模型清单：扫到内置清单没有的模型 ' + $addN + ' 个，已补进页①（共 ' + $MODELS.Count + ' 条）') }
  } catch { LogErr ('本机扫描清单读不了（删掉 console-tiers.scanned.json 会自动重扫）：' + $_.Exception.Message) }
}

# ---------- [2026-10-23 v30] 本机到底有没有这个模型 ----------
#   内置清单是我这台机器的模型；别人机器上这些模型可能根本没有，原来照样列出来还写「可起」，点了才知道没文件。
#   big 档：看引擎目录里有没有这个档（strata-<档>.json 或 run-<档>.bat）；27b/视觉：看模型盘里有没有那个 gguf。
#   目录本身不存在 → 判「不知道」（不标灰），避免在别人机器上把全部条误标灰。结果缓存在 $global:PRESENT。
$global:PRESENT = @{}
$GGUFROOTS = @($MODELDISK, $PACKDIR)
if (Test-Path $SCNF) {
  try {
    $sr = [string]((Get-Content $SCNF -Raw -Encoding UTF8 | ConvertFrom-Json).'__扫描根')
    if ($sr) { $GGUFROOTS = @($sr) + $GGUFROOTS }
  } catch { }
}
function ScanPresent {
  $h = @{}
  $roots = @($GGUFROOTS | Where-Object { $_ -and (Test-Path $_) })
  $tierOk = Test-Path $TIER_DIR
  foreach ($m in $MODELS) {
    $ok = $null                                       # $null = 判不了（不标灰）
    if ($m.Act -eq 'big') {
      if ($tierOk) {
        $t = TierOf $m.Key
        $ok = (Test-Path (Join-Path $TIER_DIR ('strata-' + $t + '.json'))) -or (Test-Path (Join-Path $TIER_DIR ('run-' + $t + '.bat')))
      }
    } elseif ($m.Gguf) {
      if ($roots.Count -gt 0) {
        $ok = $false
        foreach ($r in $roots) { if (Test-Path (Join-Path $r ([string]$m.Gguf))) { $ok = $true; break } }
      }
    }
    $h[[string]$m.Key] = $ok
  }
  $global:PRESENT = $h
}

# [2026-10-19 v14] 端口检查提速：实测 4 次 `Get-NetTCPConnection -LocalPort` = 2046 ms，
#   而一次枚举全部监听端口 = 360 ms → 旧版每次刷新白等 2 秒，这就是「点几次才打开」的主因。
#   现在一次枚举填 $LISTEN（端口 → pid），Up / PortPidOf 只读哈希，不再反复查系统。
$LISTEN = @{}
function ScanPorts {
  $m = @{}
  try {
    foreach ($c in @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)) {
      $k = [string]$c.LocalPort
      if (-not $m.ContainsKey($k)) { $m[$k] = [int]$c.OwningProcess }
    }
  } catch { }
  # 注意：函数里直接写 `$LISTEN = $m` 会变成局部变量（PowerShell 赋值规则），
  #   必须原地清空再填同一个哈希对象，外面才看得到新值。
  $LISTEN.Clear()
  foreach ($k in $m.Keys) { $LISTEN[$k] = $m[$k] }
}
ScanPorts
function Up([int]$port) { return $LISTEN.ContainsKey([string]$port) }
# [2026-10-23 v30] 大块头端口不写死：8080 只是我这台自建路由的口，官方 Strata 默认是 8095。
#   配置 BIGPORT 优先；那个口没在听就从正在监听的口里找「回 /health 且 service=strata」的那个。
#   只在启动和点「刷新」时探（5 秒定时器里同步等 HTTP 会重演 v25 卡死）。
if (-not $BIGPORT) { $BIGPORT = 8080 }
$global:BIGPORT = [int]$BIGPORT
function BigPortProbe {
  $cands = @($global:BIGPORT, 8080, 8095, 8081, 8082, 8100) | Select-Object -Unique
  foreach ($p in $cands) {
    if (-not (Up $p)) { continue }
    try {
      $hv = Invoke-WebRequest ('http://127.0.0.1:' + $p + '/health') -TimeoutSec 1 -UseBasicParsing | ConvertFrom-Json
      if ($hv -and $hv.service -eq 'strata') { $global:BIGPORT = [int]$p; return }
    } catch { }
  }
}
BigPortProbe   # 窗口还没显示就先探好（顶部链接与页⑥入口在建窗口时就要用对端口）
function PortPidOf([int]$port) {
  $k = [string]$port
  if ($LISTEN.ContainsKey($k)) { return $LISTEN[$k] }
  return '-'
}
function LiveFree {
  $out = @{}
  foreach ($r in @(& nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits 2>$null)) {
    $p = ($r -split ',')
    if ($p.Count -ge 2) { $out[[int]$p[0] + 1] = [int]$p[1] }
  }
  return $out
}
# [2026-10-21 v25] 状态不能在界面线程同步死等 :8080 —— 服务刚停时端口半开，一次要等 6 秒，比 5 秒定时器还长 → 卡死。
#   现在后台发起、界面线程最多等 150ms，没回来先用上一次的值；3 秒超时后置空，界面才显示「未在跑」。
Add-Type -AssemblyName System.Net.Http
if (-not $global:HTTP8080) {
  $global:HTTP8080 = New-Object System.Net.Http.HttpClient
  $global:HTTP8080.Timeout = [TimeSpan]::FromMilliseconds(3000)
}
$global:STask = $null
$global:STask2 = $null
$global:ST = $null
# [2026-10-23 v30] /__status 是自建路由的私有接口，官方 Strata 没有它 → 别人机器上 404，页① 永远显示「无」。
#   两条路：先 /__status，问不到再问官方自带的 /health（回 model 与 loaded），拼成同形状对象给下游。
function TierFromModel([string]$m) {
  # 官方 /health 只给模型名（如 qwen3.8-flash-next-iq3x），把它对回清单里的档位名
  if (-not $m) { return '' }
  $mm = ([string]$m).ToLower()
  $tiers = @()
  foreach ($x in $MODELS) {
    if ($x.Act -ne 'big') { continue }
    $t = ([string](TierOf $x.Key)).ToLower()
    if ($t -and ($tiers -notcontains $t)) { $tiers += $t }
  }
  # 先精确/后缀匹配；第二轮按名字从长到短（q2x 是 siq2x 的子串，顺序反了会认错）
  foreach ($t in $tiers) { if ($mm -eq $t -or $mm.EndsWith('-' + $t)) { return $t } }
  foreach ($t in ($tiers | Sort-Object { $_.Length } -Descending)) { if ($mm.Contains($t)) { return $t } }
  return $m   # 对不上就直接报模型名原文 —— 总之不再显示「无」
}
# [2026-10-23 v30b] 任务失败（404/连不上）时 $task.Wait() 会抛异常，把后面的兜底整段跳过 → 等任务单独包住。
function WaitTask($task, [int]$ms) {
  try { if ($task -and -not $task.IsCompleted) { $null = $task.Wait($ms) } } catch { }
}
function StrataStatus {
  try {
    if (-not $global:STask) { $global:STask = $global:HTTP8080.GetStringAsync('http://127.0.0.1:' + $global:BIGPORT + '/__status') }
    WaitTask $global:STask 150
    if ($global:STask.IsCompleted) {
      if ($global:STask.Status -eq 'RanToCompletion') { $global:ST = ($global:STask.Result | ConvertFrom-Json) }
      else { $global:ST = $null }   # 连不上/超时/没回话 → 明确置空，界面才会显示「未在跑」
      $global:STask = $null
    }
    if (-not $global:ST) {
      # /__status 问不到（多半是官方 Strata）→ 改问官方自带的 /health
      if (-not $global:STask2) { $global:STask2 = $global:HTTP8080.GetStringAsync('http://127.0.0.1:' + $global:BIGPORT + '/health') }
      WaitTask $global:STask2 150
      if ($global:STask2.IsCompleted) {
        if ($global:STask2.Status -eq 'RanToCompletion') {
          $hv = $null
          try { $hv = ($global:STask2.Result | ConvertFrom-Json) } catch { $hv = $null }
          $global:STask2 = $null
          if ($hv -and $hv.model) {
            $ld = $true   # 老引擎没回 loaded 字段时不误判成「没跑」
            if ($hv.PSObject.Properties['loaded']) { $ld = [bool]$hv.loaded }
            if ($ld) {
              $global:ST = [pscustomobject]@{
                current  = (TierFromModel ([string]$hv.model))
                model    = [string]$hv.model
                pid      = (PortPidOf $global:BIGPORT)
                official = $true
              }
            } else { $global:ST = $null }
          }
        } else { $global:STask2 = $null }   # 连不上/404 → 置空，别把上一次的旧值一直挂着
      }
    }
  } catch { $global:STask = $null; $global:STask2 = $null }
  return $global:ST
}
function StateFile {
  if (-not (Test-Path $STATEF)) { return @{} }
  try {
    $j = Get-Content $STATEF -Raw -Encoding UTF8 | ConvertFrom-Json
    $h = @{}
    foreach ($p in @($j.PSObject.Properties)) { $h[[string]$p.Name] = $p.Value }
    return $h
  } catch { return @{} }
}
function TierOf($key) {
  # [2026-10-22 v27] 先按清单里的 tier（外置的模型也能起）；清单没给就走下面的老逻辑（内置档不变）
  foreach ($m in $MODELS) { if ([string]$m.Key -eq [string]$key -and $m.Tier) { return [string]$m.Tier } }
  switch ($key) { 'iq2x' { return 'iq2x' } 'q2x' { return 'q2x' } 'iq3x' { return 'iq3x' } 'siq2x' { return 'siq2x' } 'siq3x' { return 'siq3x' } default { return 'x' } }
}
ScanPresent   # [2026-10-23 v30] 必须在 TierOf 之后跑（big 档要靠它认档位名）
function RunningMap {  # [2026-10-19 v14] 可传入已读到的状态，避免同一轮里两次调 :8080/__status
  param($sPre = $null)
  $map = @{}
  $s = if ($sPre) { $sPre } else { StrataStatus }
  if ($s -and $s.current) {
    foreach ($m in $MODELS) {
      if ($m.Act -eq 'big' -and $s.current -eq (TierOf $m.Key)) { $map[$m.Key] = $ANCHOR_CARD_ID }
    }
  }
  $st = StateFile
  if (Up 8090) {
    $k = 'b27bx'; $g = 1
    if ($st['8090']) {
      if ($st['8090'].key) { $k = [string]$st['8090'].key }
      $g = [int]$st['8090'].gpu + 1
    }
    $map[$k] = $g
  }
  # [2026-10-22 v27] 不再写死 vl8/8096：按清单里 act=vl 的条目逐个判（内置条目没给 port 时用 8096）
  foreach ($m in $MODELS) {
  if ($m.Act -ne 'vl') { continue }
  $vp = if ([int]$m.Port -gt 0) { [int]$m.Port } else { 8096 }
  if (Up $vp) { $map[$m.Key] = 2 }
  }
  return $map
}

# ---------- 无窗口模式 ----------
if ($Test) {
  $lines = @()
  foreach ($g in $GPUS) { $lines += ('显卡' + $g.Id + ' ' + $g.Name + ' ' + $g.GB + ' GB 安全垫 ' + (CardReserve $g.Id)) }
  $live = LiveFree
  foreach ($g in $GPUS) {
    $lines += ('显卡' + $g.Id + ' 空闲 ' + $live[$g.Id] + ' MiB')
    foreach ($m in $MODELS) {
      if ($m.Dual) {
        $sum = 0; foreach ($gg in $GPUS) { $sum += $live[$gg.Id] }
        if ($g.Id -eq $ANCHOR_CARD_ID) { $lines += ('  ' + $(if ($sum -ge $m.Need) { '[可]' } else { '[灰]' }) + ' ' + $m.Name) }
        else { $lines += ('  [灰] ' + $m.Name + ' 双卡→显卡' + $ANCHOR_CARD_ID) }
      } else {
        $lines += ('  ' + $(if ($live[$g.Id] -ge $m.Need) { '[可]' } else { '[灰]' }) + ' ' + $m.Name)
      }
    }
  }
  if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Force -Path $LOGDIR | Out-Null }
  ($lines -join [char]10) | Out-File -FilePath (Join-Path $LOGDIR 'console-scenarios.txt') -Encoding UTF8
  Write-Host ('written ' + $lines.Count + ' lines')
  return
}

# ---------- 窗口 ----------
try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  Add-Type -AssemblyName Microsoft.VisualBasic   # [2026-10-20 v20] 读内存用量用 ComputerInfo（实测 4ms，不卡界面）

  $ON   = [System.Drawing.Color]::FromArgb(0, 110, 60)
  $OFF  = [System.Drawing.Color]::FromArgb(110, 110, 110)
  # [2026-10-19 v17] 用户要求加点颜色：状态行用深蓝、警告橙、标题加粗；卡片标题不变（GroupBox 无文字颜色属性）
  $ACC  = [System.Drawing.Color]::FromArgb(0, 86, 155)
  $WARN = [System.Drawing.Color]::FromArgb(170, 60, 0)
  # [2026-10-20 v18] 按钮配色（用户：按钮换个颜色）：起=绿、停/危险=橙红、动作=蓝、中性=浅灰蓝
  $BG_ON   = [System.Drawing.Color]::FromArgb(0, 110, 60)
  $BG_STOP= [System.Drawing.Color]::FromArgb(170, 60, 0)
  $BG_GO   = [System.Drawing.Color]::FromArgb(0, 86, 155)
  $BG_NEU  = [System.Drawing.Color]::FromArgb(222, 231, 240)
  $BG_DIS  = [System.Drawing.Color]::FromArgb(214, 214, 214)
  $WHT     = [System.Drawing.Color]::FromArgb(255, 255, 255)
  $TTL  = New-Object System.Drawing.Font('Microsoft YaHei', 10.5, [System.Drawing.FontStyle]::Bold)

  $frm = New-Object System.Windows.Forms.Form
  $frm.Text = '模型服务控制台 v30'
  # 窗口固定 1000x620、不可拖动：页内可用高 360，日志框 170 放在两页共用的底部
  $frm.Width = 1000
  $frm.Height = 620
  $frm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
  $frm.MaximumSize = [System.Drawing.Size]::new(1000, 620)
  $frm.MinimumSize = [System.Drawing.Size]::new(1000, 620)
  $frm.MaximizeBox = $false
  $frm.MinimizeBox = $false
  $frm.Font = New-Object System.Drawing.Font('Microsoft YaHei', 9)

  $tabs = New-Object System.Windows.Forms.TabControl
  # [2026-10-20 v18] 用户：当前模型 / 显卡空闲放右上角、字大一点 —— 顶部状态条，标签页往下挪
  # [2026-10-20 v20] 用户：「就页面按钮的上方、和当前模型显示的左边，把 strata 监控的链接搞上去」
  #   → 这一行最左边放可点链接（:8080 监控台），状态文字整体往右挪；链接与状态条都在按钮上方
  $hdrLink = New-Object System.Windows.Forms.LinkLabel
  $hdrLink.Text = 'Strata 监控'
  $hdrLink.Tag = ('http://127.0.0.1:' + $global:BIGPORT + '/')
  $hdrLink.Location = [System.Drawing.Point]::new(8, 10)
  $hdrLink.Size = [System.Drawing.Size]::new(112, 24)
  $hdrLink.Font = New-Object System.Drawing.Font('Microsoft YaHei', 11, [System.Drawing.FontStyle]::Bold)
  $hdrLink.LinkColor = $ACC
  $hdrLink.ActiveLinkColor = $WARN
  $hdrLink.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  $hdrLink.Add_Click({ try { Start-Process ([string]$this.Tag) } catch {} })
  $frm.Controls.Add($hdrLink)
  $hdrLbl = New-Object System.Windows.Forms.Label
  $hdrLbl.Text = '正在准备界面…'
  $hdrLbl.Location = [System.Drawing.Point]::new(124, 6)
  $hdrLbl.Size = [System.Drawing.Size]::new(852, 34)   # [2026-10-21 v24] 30 → 34：11 号粗体一行高 19px，旧值一旦换行就把第二行切一半（用户：「字被盖住了一半」）
  $hdrLbl.AutoEllipsis = $true   # [2026-10-21 v24] 万一还是放不下，宁可显示省略号，也不把字切成半截
  # [2026-10-20 v20b] 11.5 → 11：加了「内存」段后 11.5 号字会把最后一段挤到第二行（自截图 v20-p1.png 实测）
  $hdrLbl.Font = New-Object System.Drawing.Font('Microsoft YaHei', 11, [System.Drawing.FontStyle]::Bold)
  $hdrLbl.ForeColor = $ACC
  $hdrLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
  $frm.Controls.Add($hdrLbl)
  $tabs.Location = [System.Drawing.Point]::new(8, 40)
  # [2026-10-19 v13] 宽度 984 → 968：旧值等于客户区宽（984），右侧被裁 8px、贴边；现在左右留白都是 8
  $tabs.Size = [System.Drawing.Size]::new(968, 390)   # 页内可用高 = 390 - 30（标签栏）= 360
  $frm.Controls.Add($tabs)

  function GB([int]$x, [int]$y, [int]$w, [int]$h, [string]$t) {
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $t
    $g.Location = [System.Drawing.Point]::new($x, $y)
    $g.Size = [System.Drawing.Size]::new($w, $h)
    return $g
  }
  function BTN([int]$x, [int]$y, [int]$w, [int]$h, [string]$t) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $t
    $b.Location = [System.Drawing.Point]::new($x, $y)
    $b.Size = [System.Drawing.Size]::new($w, $h)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.Font = New-Object System.Drawing.Font('Microsoft YaHei', 9, [System.Drawing.FontStyle]::Bold)
    return $b
  }
  function LBL([int]$x, [int]$y, [int]$w, [int]$h, [string]$t) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $t
    $l.Location = [System.Drawing.Point]::new($x, $y)
    $l.Size = [System.Drawing.Size]::new($w, $h)
    return $l
  }

  # ---------- 执行器（异步） ----------
  # [2026-10-19 v16] 必须用 $global: —— 函数内直接赋值只存在于函数内（作用域坑），
  #   定时器事件块读不到 → 「刷新列表」跑完也不填列表、也不报结束（用户看到的「出不来」）
  $global:curProc = $null
  $global:curLog  = ''
  $global:curName = ''
  $global:offset  = 0
  $global:curStart = $null   # [2026-10-21 v23] 占用提示要说「已跑几秒」

  $outBox = New-Object System.Windows.Forms.TextBox
  # 日志框在窗口底部、与卡片左右齐平（x=20 宽 944），两页共用
  $outBox.Location = [System.Drawing.Point]::new(20, 440)
  $outBox.Size = [System.Drawing.Size]::new(944, 148)
  $outBox.Multiline = $true
  $outBox.ReadOnly = $true
  $outBox.BackColor = [System.Drawing.Color]::FromArgb(248, 248, 248)
  # [2026-10-19 v13] 日志用等宽字体，数字与时间戳对齐（抄参考项目的做法）
  $outBox.Font = New-Object System.Drawing.Font('Consolas', 9)

  function AppendLog([string]$t) { $outBox.AppendText($t) }
  # [2026-10-20 v18] 按按钮文字统一配色；禁用态 WinForms 自动变灰
  function ColorizeButtons {
    function Walk($parent) {
      foreach ($c in $parent.Controls) {
        if ($c -is [System.Windows.Forms.Button]) {
          $t = [string]$c.Text
          if ($t -eq '起') { $c.BackColor = $BG_ON; $c.ForeColor = $WHT }
          elseif ($t -eq '停' -or $t -eq '全停') { $c.BackColor = $BG_STOP; $c.ForeColor = $WHT }
          elseif ($t -like '切到*' -or $t -like '换模型*' -or $t -eq '应用' -or $t -eq '只改这一个' -or $t -like '改心跳*') { $c.BackColor = $BG_GO; $c.ForeColor = $WHT }
          else { $c.BackColor = $BG_NEU; $c.ForeColor = [System.Drawing.Color]::FromArgb(20, 40, 70) }
        }
        elseif ($c.Controls -and $c.Controls.Count -gt 0) { Walk $c }
      }
    }
    Walk $frm
  }

  function RunAction([string]$action, [string]$key, [int]$gpu, [string]$label, [string[]]$extra) {
    if ($global:curProc -and -not $global:curProc.HasExited) {
      # [2026-10-21 v23] 用户：「切几下页面就跳『上一个任务还在跑』，点确定再切还跳」——读官方版本也占了这个独占槽（实测 2-5 秒），期间切页/点按钮全被挡。
      #   版本已改走独立后台读取（StartVersionsRead），这里只剩真正的起停/改配置动作会挡；提示补上「已跑几秒」。
      $el = 0
      try { $el = [int](((Get-Date) - $global:curStart).TotalSeconds) } catch { }
      [System.Windows.Forms.MessageBox]::Show('上一个任务还在跑：' + $global:curName + '（已 ' + $el + ' 秒）' + [char]10 + '等它跑完再点下一个（日志框会显示结束时间与退出码）。', '请稍候', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
      return
    }
    if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Force -Path $LOGDIR | Out-Null }
    $global:curLog = Join-Path $LOGDIR ('console-' + $action + '-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.log')
    $global:curName = $label; $global:offset = 0; $global:curStart = Get-Date   # [2026-10-21 v23] 占用提示要说「已跑几秒」
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $RUN, $action)
    if ($key) { $argv += @('-Key', $key) }
    if ($gpu -ge 0) { $argv += @('-Gpu', $gpu) }
    if ($extra) { $argv += $extra }
# [2026-10-23 v29] 找不到 pwsh 时说人话：原来直接让 Start-Process 甩系统原话「系统找不到指定的文件」，
#   用户/用户看不出是 PowerShell 没找到，更不知道该怎么办（朋友机器上就是这么卡住的）。
if (-not $PWSH -or -not (Test-Path $PWSH)) {
      AppendLog((Get-Date -Format 'HH:mm:ss') + '  ' + $label + ' 起不来：找不到 PowerShell 7（pwsh.exe）。' + [char]10 + '    装一个：winget install Microsoft.PowerShell' + [char]10 + '    或在同目录 console-paths.json 里写 PWSH = pwsh.exe 的完整路径（反斜杠要写两个）' + [char]10)
      return
    }
    AppendLog((Get-Date -Format 'HH:mm:ss') + '  ' + $label + ' ...' + [char]10)
    try {
      $global:curProc = Start-Process -FilePath $PWSH -ArgumentList $argv -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $global:curLog -RedirectStandardError ($global:curLog + '.err')
    } catch { AppendLog('启动失败：' + $_.Exception.Message + [char]10); LogErr ('RunAction ' + $action + ' 失败: ' + $_.Exception.Message); $global:curProc = $null }
  }

  # [2026-10-20 v19] 设显卡功率：先用当前权限试；被拒（exit 87）就问用户要不要用管理员身份重试（弹一次 UAC）。
  # 为什么提权：本机 FilterAdministratorToken=1，双击打开的程序拿的是普通权限令牌，nvidia-smi 写功率会被拒。
  function SetPower([int]$smi, [int]$wv, [string]$gid) {
    if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Force -Path $LOGDIR | Out-Null }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $dlog  = Join-Path $LOGDIR ('power-direct-' + $stamp + '.log')
    $argv  = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $RUN, 'power', '-Gpu', $smi, '-Watts', $wv)
    AppendLog((Get-Date -Format 'HH:mm:ss') + '  设显卡' + $gid + ' 功率 ' + $wv + 'W（当前权限）...' + [char]10)
    $code = -1
    try {
      $p = Start-Process -FilePath $PWSH -ArgumentList $argv -WindowStyle Hidden -PassThru -Wait `
        -RedirectStandardOutput $dlog -RedirectStandardError ($dlog + '.err')
      $code = [int]$p.ExitCode
    } catch { AppendLog('  跑执行器失败：' + $_.Exception.Message + [char]10); return }
    try {
      if (Test-Path $dlog) { AppendLog(((Get-Content $dlog -Raw -Encoding UTF8) ?? '') + [char]10) }
      if (Test-Path ($dlog + '.err')) {
        $e = (Get-Content ($dlog + '.err') -Raw -Encoding UTF8) ?? ''
        if ($e.Trim().Length -gt 0) { AppendLog($e + [char]10) }
      }
    } catch {}
    if ($code -eq 87) {
      $r = [System.Windows.Forms.MessageBox]::Show('写功率被拒：需要管理员权限。' + [char]10 + '现在用管理员身份重试吗？（会弹一次 UAC 确认，只重试这一个动作，程序别处不动）', '需要管理员', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
      if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
        $elog = Join-Path $LOGDIR ('power-elev-' + $stamp + '.log')
        AppendLog((Get-Date -Format 'HH:mm:ss') + '  用管理员身份重试（请在 UAC 窗口点「是」）...' + [char]10)
        try {
          $cmd = "& '$RUN' power -Gpu $smi -Watts $wv *> '$elog'"
          $pe = Start-Process -FilePath $PWSH -Verb RunAs -WindowStyle Hidden -PassThru -Wait `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
          if (Test-Path $elog) { AppendLog(((Get-Content $elog -Raw -Encoding UTF8) ?? '') + [char]10) }
        } catch { AppendLog('  提权失败或被取消：' + $_.Exception.Message + [char]10) }
      }
    }
    try { LoadPowerInfo } catch { }
    try { UpdateHeader } catch { }
  }

  # ---------- 页① 模型起停 ----------
  $t1 = New-Object System.Windows.Forms.TabPage
  $t1.Text = '模型起停'
  $tabs.TabPages.Add($t1)

  # [2026-10-19 v13] 页内坐标基准：标签页内容区宽 = 968 - 左右各 4 内缩 = 960
  #   旧：$INNER=968（当作右边缘坐标）+ GBW=476 + colX=(8,484) → 右留白 0、左留白 8，不对称
  #   新：$INNER=960（内容区宽）、GBW=468、colX=(8,484) → 左留白 8 / 右留白 8 / 两卡间距 8，完全对称
  $INNER = 960
  $GBW = 468
  $colX = @(8, 484)

  $statusLbl = LBL 8 6 700 22 ''
  $statusLbl.Font = New-Object System.Drawing.Font('Microsoft YaHei', 9.5, [System.Drawing.FontStyle]::Bold)
  $statusLbl.ForeColor = $ACC   # [2026-10-19 v17] 当前运行模型要醒目：加粗 + 深蓝
  $t1.Controls.Add($statusLbl)

  # [2026-10-19 v13] 右缘对齐卡片右缘（卡片右缘 = 484+468 = 952）：旧值算到 960，比卡片多出 8px
  $btnStopAll = BTN 736 4 100 24 '全停'
  $btnStopAll.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show('全停：大块头 + 27B + 视觉，腾空两卡。正在跑的请求会中断。', '确认全停', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'stop-all' '' -1 '全停' $null }
  })
  $t1.Controls.Add($btnStopAll)

  $btnRefresh = BTN 852 4 100 24 '刷新'
  # [2026-10-21 v23] 用户：「我点刷新他们应该重新扫一下内存显存这些，但是不会动」——旧 RefreshState 不碰右上角，内存又只在开窗口量一次 → 点了像没反应。
  #   现在：重扫端口 + 重量两卡显存 + 重读当前模型 + 重读内存 + 刷右上角，并在日志框回显耗时。
  $btnRefresh.Add_Click({
    $swr = [Diagnostics.Stopwatch]::StartNew()
    try { if (-not (Up $global:BIGPORT)) { BigPortProbe } } catch { }
    try { ScanPresent } catch { }   # 手动刷新时重判一次「本机有没有这个模型」（拷进来新模型不用重开程序）
    RefreshState
    AppendLog((Get-Date -Format 'HH:mm:ss') + '  手动刷新完成（' + [int]$swr.Elapsed.TotalMilliseconds + 'ms）：显存 / 内存 / 当前模型 / 端口 已重扫' + [char]10)
  })
  $t1.Controls.Add($btnRefresh)

  # [2026-10-19 v13] 修文字截断坑：PowerShell 函数调用里 `'文字' + $var + '文字'` 不加括号时，只有第一段进 Text，后面被丢
  #   （实测：旧写法只显示「灰 = 显存不够；双卡模型从显卡」，后半句没了）→ 必须用括号包住拼接
  $legend = LBL 8 338 ($INNER - 16) 18 ('灰 = 显存不够；双卡模型从显卡' + $ANCHOR_CARD_ID + '起；起另一个 = 自动换档，不用先停。')
  $t1.Controls.Add($legend)

  $rowStart = @{}
  $rowStop  = @{}
  $rowStat  = @{}

  foreach ($idx in 0..([Math]::Min($GPUS.Count, 2) - 1)) {
    $g = $GPUS[$idx]
    $gb = GB $colX[$idx] 32 $GBW 300 ('显卡' + $g.Id + '  ' + $g.Name + '  ' + $g.GB + ' GB')
    # [2026-10-23 v30] 模型多时框内出竖向滚动条；条目少时位置与旧版逐像素相同。
    #   两层面板：外层裁剪、内层被移动（只有一层时超出的行会被自己裁掉，滚不出来）。
    #   不用 AutoScroll：它会在竖向条出现后再冒一条横向条，HorizontalScroll.Visible=$false 压不住。
    $rowClip = New-Object System.Windows.Forms.Panel                       # 外层：窗口，固定高，负责裁剪
    $rowClip.Location = [System.Drawing.Point]::new(4, 20)
    $rowClip.Size = [System.Drawing.Size]::new(($GBW - 27), 280)          # 441：留 17 给滚动条 + 2 边距
    $rowPanel = New-Object System.Windows.Forms.Panel                     # 内层：内容，高度=全部行，被滚动移动
    $rowPanel.Location = [System.Drawing.Point]::new(0, 0)
    $rowPanel.Size = [System.Drawing.Size]::new(($GBW - 27), 280)
    $rowClip.Controls.Add($rowPanel)
    $rowScroll = New-Object System.Windows.Forms.VScrollBar
    $rowScroll.Location = [System.Drawing.Point]::new(($GBW - 25), 20)
    $rowScroll.Size = [System.Drawing.Size]::new(17, 280)
    $rowScroll.Minimum = 0
    $rowScroll.SmallChange = 25
    $rowScroll.LargeChange = 200
    $rowScroll.Tag = $rowPanel
    $rowPanel.Tag = $rowScroll
    $rowClip.Tag = $rowScroll
    # 滚动只做一件事：把内层往上挪 Value 像素（外层不动，所以超出外层的行被裁掉、看不见的行进来）
    $rowScroll.Add_Scroll({
      $p = $args[0].Tag
      if ($p) { $p.Location = [System.Drawing.Point]::new($p.Location.X, (0 - $args[0].Value)) }
    })
    $rowPanel.Add_MouseWheel({
      $sb = $args[0].Tag
      if ($sb -and $sb.Visible) {
        $mx = ($sb.Maximum - $sb.LargeChange + 1)
        $nv = $sb.Value - ([Math]::Sign($args[0].Delta) * 50)
        if ($nv -lt $sb.Minimum) { $nv = $sb.Minimum }
        if ($nv -gt $mx) { $nv = $mx }
        $sb.Value = $nv
        $args[0].Location = [System.Drawing.Point]::new($args[0].Location.X, (0 - $nv))
      }
    })
    $rowClip.Add_MouseWheel({
      $sb = $args[0].Tag
      if ($sb -and $sb.Visible) {
        $mx = ($sb.Maximum - $sb.LargeChange + 1)
        $nv = $sb.Value - ([Math]::Sign($args[0].Delta) * 50)
        if ($nv -lt $sb.Minimum) { $nv = $sb.Minimum }
        if ($nv -gt $mx) { $nv = $mx }
        $sb.Value = $nv
        $ip = $args[0].Controls[0]
        if ($ip) { $ip.Location = [System.Drawing.Point]::new($ip.Location.X, (0 - $nv)) }
      }
    })
    $gb.Controls.Add($rowClip)
    $gb.Controls.Add($rowScroll)
    $i = 0
    foreach ($m in $MODELS) {
      $yy = $i * 25
      $rowPanel.Controls.Add((LBL 8 $yy 240 20 $m.Name))
      $bs = BTN 250 $yy 44 22 '起'
      $bp = BTN 296 $yy 44 22 '停'
      $sl = LBL 344 $yy 96 20 ''
      $bs.Tag = [pscustomobject]@{ key = $m.Key; gid = $g.Id; name = $m.Name; act = $m.Act }
      $bp.Tag = [pscustomobject]@{ key = $m.Key; gid = $g.Id; name = $m.Name; act = $m.Act }
      $bs.Add_Click({
        $t = $this.Tag
        $ans = [System.Windows.Forms.MessageBox]::Show('起 ' + $t.name + '（显卡' + $t.gid + '）' + "`n" + '该模型上卡，显存被占用。其它模型不受影响。', '确认', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction ('start-' + $t.act) $t.key ($t.gid - 1) ('起 ' + $t.name) $null }
      })
      $bp.Add_Click({
        $t = $this.Tag
        $ans = [System.Windows.Forms.MessageBox]::Show('停 ' + $t.name + '（显卡' + $t.gid + '）' + "`n" + '该模型从显存卸载，正在用它对话的请求会中断。其它模型不受影响。', '确认', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction ('stop-' + $t.act) $t.key ($t.gid - 1) ('停 ' + $t.name) $null }
      })
      $rowPanel.Controls.Add($bs); $rowPanel.Controls.Add($bp); $rowPanel.Controls.Add($sl)
      $rowStart[[string]$g.Id + '_' + $m.Key] = $bs
      $rowStop[[string]$g.Id + '_' + $m.Key]  = $bp
      $rowStat[[string]$g.Id + '_' + $m.Key]  = $sl
      $i++
    }
    # 内层高度 = 全部行总高；Maximum 多加 199 是因为 UI 拖到底的值 = Maximum - LargeChange + 1
    $contentPx = $i * 25 + 4
    $rowPanel.Size = [System.Drawing.Size]::new(($GBW - 27), [Math]::Max(280, $contentPx))
    $needPx = $contentPx - 280
    if ($needPx -gt 0) {
      $rowScroll.Maximum = ($needPx + 199)
      $rowScroll.Visible = $true
    } else {
      $rowScroll.Maximum = 0
      $rowScroll.Visible = $false
    }
    $t1.Controls.Add($gb)
  }

  $frm.Controls.Add($outBox)

    function RefreshState([switch]$NoScan) {
    if (-not $NoScan) { ScanPorts }   # v14：一次枚举（实测 390-900ms）代替旧版 4 次单独查询（2046ms）；[2026-10-21 v23] -NoScan 给 5 秒定时器用，别每次都付枚举的钱
    $s = StrataStatus
    $live = LiveFree
    $global:FREE = $live   # [2026-10-21 v23] 用户：「点刷新上面的显卡/内存不动」——把刚量到的显存直接交给右上角复用，不再各查各的
    $map = RunningMap $s
    $parts = @()
    # [2026-10-23 v30] 「占两卡」是我机器（3090+3080 双卡换档）才成立的说法，别人单卡机器不适用 → 去掉；
    #   档位名对不上时（外置清单/别人的模型名）直接显示引擎报的真实模型名
    if ($s) {
      $cur = [string]$s.current
      if ($s.model -and $s.model -ne $cur) { $cur = ($cur + '（' + [string]$s.model + '）') }
      $parts += ('大块头 ' + $cur + ' 运行中')
    } else { $parts += '大块头 停' }
    if (Up 8090) { $parts += '27B 运行中' }
    # [2026-10-22 v27] 同上：按清单里 act=vl 的条目判（内置条目没给 port 时用 8096）
    foreach ($m in $MODELS) {
    if ($m.Act -ne 'vl') { continue }
    $vp = if ([int]$m.Port -gt 0) { [int]$m.Port } else { 8096 }
    if (Up $vp) { $parts += '视觉 运行中' }
    }
    # [2026-10-20 v20] 用户：「显卡显存 2 个显存闲置那个重复了」——自截图证实：右上角状态条与这一行各写一遍
    #   只留右上角（v18 用户指定的位置），这一行不再重复；显卡空闲仍参与下面的可起/显存不够判断
    #   （旧：foreach ($g in $GPUS) { $parts += (显卡N 空闲 X MiB) }）
    $statusLbl.Text = ($parts -join '  ｜  ')

    # [2026-10-19 v12] 页② 状态行（只读，不动任何服务）
    try {
      if (Up 18789) { $lblGwState.Text = ('网关 :18789 在跑（pid ' + (PortPidOf 18789) + '）') }
      else { $lblGwState.Text = '网关 :18789 未在跑' }
    } catch { $lblGwState.Text = '网关状态读不到' }
    if ($s -and $s.current) {
      $lblBigState.Text = ('大块头 :' + $global:BIGPORT + ' 在跑，当前档 ' + $s.current + '（pid ' + $s.pid + '）')
    } else {
      $lblBigState.Text = ('大块头 :' + $global:BIGPORT + ' 未在跑')
    }

    $bigRunning = ($s -and $s.current)
    $llmRunning = (Up 8090)

    foreach ($g in $GPUS) {
      foreach ($m in $MODELS) {
        $k = [string]$g.Id + '_' + $m.Key
        $bs = $rowStart[$k]; $bp = $rowStop[$k]; $sl = $rowStat[$k]
        if (-not $bs) { continue }
        $running = $map.ContainsKey($m.Key)

        # [2026-10-23 v30] 本机没这个模型文件 → 灰掉并说明（在跑的除外，别把正在跑的标错）
        if (-not $running -and $global:PRESENT[[string]$m.Key] -eq $false) {
          $bs.Enabled = $false; $bp.Enabled = $false
          $sl.Text = '本机无此模型'; $sl.ForeColor = $OFF
          continue
        }

        if ($m.Dual) {
          if ($g.Id -ne $ANCHOR_CARD_ID) {
            $bs.Enabled = $false; $bp.Enabled = $false
            $sl.Text = '双卡→显卡' + $ANCHOR_CARD_ID; $sl.ForeColor = $OFF
            continue
          }
          if ($running) {
            $bs.Enabled = $false; $bp.Enabled = $true; $sl.Text = '运行中'; $sl.ForeColor = $ON
          } elseif ($bigRunning) {
            $bs.Enabled = $true; $bp.Enabled = $false; $sl.Text = '可切换'; $sl.ForeColor = $OFF
          } else {
            $sum = 0; foreach ($gg in $GPUS) { $sum += $live[$gg.Id] }
            $nd = NeedOf $m   # [2026-10-20 v22] 有实测就用实测，没实测才用占位值
            if ($sum -ge $nd) { $bs.Enabled = $true; $bp.Enabled = $false; $sl.Text = '可起'; $sl.ForeColor = $OFF }
            else { $bs.Enabled = $false; $bp.Enabled = $false; $sl.Text = '显存不够'; $sl.ForeColor = $OFF }
          }
        } else {
          if ($running) {
            if ($map[$m.Key] -eq $g.Id) { $bs.Enabled = $false; $bp.Enabled = $true; $sl.Text = '运行中'; $sl.ForeColor = $ON }
            else { $bs.Enabled = $false; $bp.Enabled = $false; $sl.Text = '显卡' + $map[$m.Key]; $sl.ForeColor = $OFF }
          } elseif ($m.Act -eq '27b' -and $llmRunning) {
            $bs.Enabled = $true; $bp.Enabled = $false; $sl.Text = '可切换'; $sl.ForeColor = $OFF
          } elseif ($live[$g.Id] -ge (NeedOf $m)) {   # [2026-10-20 v22] 优先实测
            $bs.Enabled = $true; $bp.Enabled = $false; $sl.Text = '可起'; $sl.ForeColor = $OFF
          } else {
            $bs.Enabled = $false; $bp.Enabled = $false; $sl.Text = '显存不够'; $sl.ForeColor = $OFF
          }
        }
      }
    }
    # [2026-10-21 v23] 刷新必须连右上角一起刷（旧版只刷页①的行状态；右上角只在开窗口/采集完成时动 → 用户看到「点了没反应」）
    try { UpdateHeader -sPre $s } catch { }
  }

  # ---------- 页② 安全垫 / 网关 ----------
  $t2 = New-Object System.Windows.Forms.TabPage
  # [2026-10-19 v13] 状态行也放在页②顶部（两页共用窗体底部日志框，切页仍能看到回显）
  $t2.Text = '安全垫 · 网关'
  $tabs.TabPages.Add($t2)

  $gbPad = GB $colX[0] 12 $GBW 340 '显存安全垫（MiB）'
  $gbPad.Controls.Add((LBL 12 22 180 20 ('首卡（显卡' + $FIRST_CARD_ID + '）')))
  $txtFirst = New-Object System.Windows.Forms.TextBox
  $txtFirst.Text = [string]$RES.first
  $txtFirst.Location = [System.Drawing.Point]::new(200, 20)
  $txtFirst.Width = 70
  $gbPad.Controls.Add($txtFirst)
  $gbPad.Controls.Add((LBL 12 52 180 20 '其它卡'))
  $txtLater = New-Object System.Windows.Forms.TextBox
  $txtLater.Text = [string]$RES.later
  $txtLater.Location = [System.Drawing.Point]::new(200, 50)
  $txtLater.Width = 70
  $gbPad.Controls.Add($txtLater)

  $btnPad = BTN 12 84 200 30 '确定（写入并重启）'
  $btnPad.Add_Click({
    $oF = [string]$RES.first; $oL = [string]$RES.later
    if ($txtFirst.Text -notmatch '^\d+$' -or $txtLater.Text -notmatch '^\d+$') {
      [System.Windows.Forms.MessageBox]::Show('必须是整数（MiB）。', '输入有误', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }
    $f = [int]$txtFirst.Text; $l = [int]$txtLater.Text
    $msg = '安全垫：首卡 ' + $oF + ' → ' + $f + ' MiB，其它卡 ' + $oL + ' → ' + $l + ' MiB' + "`n" +
      '影响：五个档位配置被改写，大块头服务重启，正在跑的大块头请求中断。' + "`n" +
      '备份：D:\06.AItools\Strata\.reserve-bak\' + "`n" +
      '回滚：从备份拷回，再重启大块头。'
    $ans = [System.Windows.Forms.MessageBox]::Show($msg, '确认修改安全垫', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { $txtFirst.Text = $oF; $txtLater.Text = $oL; return }
    RunAction 'reserve' '' -1 '写安全垫' @('-First', [string]$f, '-Later', [string]$l)
    $RES = ReadReserve
  })
  $gbPad.Controls.Add($btnPad)
  # [2026-10-19 v13] 写入后读回确认：直接读档位 JSON，把实际生效值写进状态行
  function UpdateReserveReadback {
    try {
      $v = ReadReserve
      if ($v -and $v.first -ne $null) {
        $lblReserveState.Text = ('当前生效（读回）：首卡 ' + $v.first + ' / 其它卡 ' + $v.later)
        $lblReserveState.ForeColor = $ON
      } else {
        $lblReserveState.Text = '读回失败：读不到档位 JSON 里的数值'
        $lblReserveState.ForeColor = $OFF
      }
    } catch {
      $lblReserveState.Text = '读回失败：' + $_.Exception.Message
      $lblReserveState.ForeColor = $OFF
    }
  }

  $btnRestartBig = BTN 220 84 150 30 '重启大块头'
  $btnRestartBig.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show('重启大块头（当前档不变），正在跑的请求中断。', '确认', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'restart-big' '' -1 '重启大块头' $null }
  })
  $gbPad.Controls.Add($btnRestartBig)

  $btnCache = BTN 12 124 150 30 '清空缓存'
  $btnCache.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show('清空大块头引擎缓存（不重启服务）。期间约 40–90 秒无应答。', '确认', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'clear-cache' '' -1 '清空缓存' $null }
  })
  $gbPad.Controls.Add($btnCache)

  $btnDiag = BTN 172 124 150 30 '诊断大块头'
  $btnDiag.Add_Click({ RunAction 'scan' '' -1 '诊断大块头进程' $null })
  $gbPad.Controls.Add($btnDiag)
  # [2026-10-19 v13] 一键回滚安全垫（抄参考项目的「恢复修改前」）：拷回最新一批备份 → 读回确认 → 重启大块头
  $btnRoll = BTN 324 124 124 30 '回滚安全垫'
  $btnRoll.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show('回滚：把 .reserve-bak 里最新一批备份拷回五个档位 JSON，然后重启大块头。' + "`n" + '正在跑的大块头请求会中断。', '确认回滚安全垫', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'reserve-rollback' '' -1 '回滚安全垫' $null }
  })
  $gbPad.Controls.Add($btnRoll)
  $gbPad.Controls.Add((LBL 12 164 440 20 '建议 1536 / 300（首卡 / 其它卡）'))
  $gbPad.Controls.Add((LBL 12 196 440 20 '写入对象：五个档位 JSON；改完自动重启大块头'))
  $gbPad.Controls.Add((LBL 12 224 440 20 '备份：D:\06.AItools\Strata\.reserve-bak\'))
  $gbPad.Controls.Add((LBL 12 252 440 20 '回滚：从备份拷回 → 重启大块头'))
  $lblTierState2 = LBL 12 280 440 20 '档位端口：iq2x 8092 / q2x 8093 / iq3x 8095 / siq2x 8091 / siq3x 8094'
  $gbPad.Controls.Add($lblTierState2)
  # [2026-10-19 v13] 读回状态行：写入后重新读 JSON，显示实际生效值（不盲信「写入成功」）
  $lblReserveState = LBL 12 308 440 20 '当前生效：读回中…'
  $lblReserveState.ForeColor = $OFF
  $gbPad.Controls.Add($lblReserveState)
  $t2.Controls.Add($gbPad)

  $gbGw = GB $colX[1] 12 $GBW 340 'OpenClaw 网关 :18789'  # [2026-10-19 v14] 网关框移到页③（页② 改成「窗口换模型」）
  $b1 = BTN 12 22 150 30 '重启网关'
  $b1.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show('重启网关，所有对话框断线约 10–30 秒。', '确认', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'gw' '' -1 '重启网关' $null }
  })
  $gbGw.Controls.Add($b1)
  $b2 = BTN 172 22 150 30 '强制重启'
  $b2.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show('强制重启：硬清理网关进程再起，所有对话框断线约 10–30 秒。', '确认', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'gw-hard' '' -1 '强制重启网关' $null }
  })
  $gbGw.Controls.Add($b2)
  $gbGw.Controls.Add((LBL 12 62 400 20 '走 gateway-rescue.ps1（优雅 → 强制 → 兜底 → 硬清理）'))
  $lblGwState = LBL 12 92 440 20 '网关状态：—'
  $gbGw.Controls.Add($lblGwState)
  $lblBigState = LBL 12 122 440 20 '大块头状态：—'
  $gbGw.Controls.Add($lblBigState)
  $gbGw.Controls.Add((LBL 12 152 440 20 '重启网关属系统级操作，先确认再点'))
  $gbGw.Controls.Add((LBL 12 182 440 20 '断线影响：所有对话框 10–30 秒'))
  $gbGw.Controls.Add((LBL 12 212 440 20 '回滚：救援脚本自带重试与硬清理'))
  $gbGw.Controls.Add((LBL 12 242 440 20 '日志：tmp\logs\gateway-rescue-*.log'))
  $t2.Controls.Add($gbGw)

  # ---------- 页③ 各窗口换模型（v14 新增） ----------
  $t3 = New-Object System.Windows.Forms.TabPage
  $t3.Text = '窗口换模型'
  $tabs.TabPages.Add($t3)

  $gbWin = GB $colX[0] 12 $GBW 340 ('各对话窗口当前模型（只读）')
  $winLbl = @()
  for ($i = 0; $i -lt 9; $i++) {
    $l = LBL 12 (22 + $i * 22) 440 18 ''
    $gbWin.Controls.Add($l)
    $winLbl += $l
  }
  $btnWinList = BTN 12 224 110 26 '刷新列表'
  $btnWinList.Add_Click({ RunAction 'win-list' '' -1 '读窗口清单' $null })
  $gbWin.Controls.Add($btnWinList)
  $lblWinState = LBL 132 226 320 20 '未读取：点「刷新列表」'
  $gbWin.Controls.Add($lblWinState)
  $gbWin.Controls.Add((LBL 12 262 440 20 '定时任务 / 心跳的模型在页④换：'))
  $gbWin.Controls.Add((LBL 12 290 440 20 '心跳与压缩固定用云端，不跟本地大块头抢活'))
  $t3.Controls.Add($gbWin)

  $gbSw = GB $colX[1] 12 $GBW 340 '一键换所有对话窗口的模型'
  $gbSw.Controls.Add((LBL 12 22 300 20 '目标模型（下拉选，也可自己填）'))
  # 下拉列出所有可换模型，数据源 console-models.json（执行器 model-list 生成）
  #   坑：ComboBoxStyle 没有 ::ComboBox，写错得到 null 会让整个窗口打不开；用 DropDown（可打字可下拉）
  $cmbModel = New-Object System.Windows.Forms.ComboBox
  $cmbModel.Location = [System.Drawing.Point]::new(12, 46)
  $cmbModel.Width = 440
  $cmbModel.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
  $cmbModel.Text = 'strata/qwen3.8-flash-next-iq2x'
  $gbSw.Controls.Add($cmbModel)
  $btnModelScan = BTN 12 76 130 24 '重扫模型清单'
  $btnModelScan.Add_Click({ RunAction 'model-list' '' -1 '读可换模型清单' $null })
  $gbSw.Controls.Add($btnModelScan)
  $lblModelState = LBL 152 78 296 20 '模型清单：未读'
  $gbSw.Controls.Add($lblModelState)
  $btnSwap = BTN 12 110 150 30 '换模型'
  $btnSwap.Add_Click({
    $m = PickModelRef
    $ans = [System.Windows.Forms.MessageBox]::Show('把所有对话窗口换成 ' + $m + '。' + "`n" + '不重启服务、不中断正在跑的回答（网关把切换排队到下一次安全时机）。' + "`n" + '定时任务与心跳窗口不动。', '确认换模型', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
      RunAction 'win-set' $m -1 '换窗口模型' $null   # [2026-10-19 v17] 只换对话窗口；定时任务/心跳去页④各管各的
    }
  })
  $gbSw.Controls.Add($btnSwap)
  $btnSwapC = BTN 172 110 190 30 '换模型 + 压上下文'
  $btnSwapC.Add_Click({
    $m = PickModelRef
    $ans = [System.Windows.Forms.MessageBox]::Show('换模型后逐个压缩上下文（防止切到上下文短的模型时爆上下文）。' + "`n" + '压缩要读历史，每个窗口约 2–20 秒。' + "`n" + '目标模型：' + $m, '确认换模型并压缩', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
      RunAction 'win-set' $m -1 '换窗口模型+压上下文' @('-Compact')   # [2026-10-19 v17] 只换对话窗口
    }
  })
  $gbSw.Controls.Add($btnSwapC)
  # [2026-10-19 v17] 去掉「连定时任务/心跳一起换」勾选：用户说各自切换就去各自页面，页④专门管定时任务
  $lblSysNote = LBL 12 150 440 20 '定时任务/心跳的模型在页④换，本页只管对话窗口'
  $lblSysNote.ForeColor = $WARN
  $gbSw.Controls.Add($lblSysNote)
  $gbSw.Controls.Add((LBL 12 184 440 20 '换模型 = 改各对话窗口的模型选择，不重启服务'))
  $gbSw.Controls.Add((LBL 12 212 440 20 '前提：目标模型的服务已在跑（先回页①起服务）'))
  $gbSw.Controls.Add((LBL 12 240 440 20 '切到上下文短的模型：勾「压上下文」或事后压'))
  $gbSw.Controls.Add((LBL 12 268 440 20 '写回确认：换完重新读一次窗口清单，报生效个数'))
  $lblSwState = LBL 12 296 440 20 '状态：—'
  $gbSw.Controls.Add($lblSwState)
  $t3.Controls.Add($gbSw)

  # ---------- 页④ 云端与定时任务（v16：左框改成定时任务「定义」表，不再显示乱码窗口名） ----------
  $t4 = New-Object System.Windows.Forms.TabPage
  $t4.Text = '云端与定时任务'
  $tabs.TabPages.Add($t4)

  $gbSys = GB $colX[0] 12 $GBW 348 '定时任务（只读 · 要模型的在上面）'
  $sysLbl = @()
  # [2026-10-20 v18] 12 行 → 17 行：cron.list 带 includeDisabled 后实测 17 个（13 在跑 + 4 停用）
  for ($i = 0; $i -lt 17; $i++) {
    $l = LBL 12 (18 + $i * 17) 440 15 ''
    $l.Font = New-Object System.Drawing.Font('Microsoft YaHei', 8.5)
    $gbSys.Controls.Add($l)
    $sysLbl += $l
  }
  $btnSysList = BTN 12 306 110 24 '刷新列表'
  $btnSysList.Add_Click({ RunAction 'cron-list' '' -1 '读定时任务清单' $null })
  $gbSys.Controls.Add($btnSysList)
  $lblSysState = LBL 132 308 336 20 '未读取：点「刷新列表」'
  $gbSys.Controls.Add($lblSysState)
  $gbSys.Controls.Add((LBL 12 334 440 12 '标签 [云端]/[官方]/[本地]；括号内是备用模型'))
  $t4.Controls.Add($gbSys)

  $gbCloud = GB $colX[1] 12 $GBW 348 '定时任务换模型（批量 + 单个）'
  $gbCloud.Controls.Add((LBL 12 16 440 20 '批量：把「要模型」的任务全换成 ↓'))
  $txtA = New-Object System.Windows.Forms.TextBox
  $txtA.Location = [System.Drawing.Point]::new(12, 38)
  $txtA.Width = 440
  $txtA.Text = 'scnet/DeepSeek-V4.1-Flash（云端）'
  $gbCloud.Controls.Add($txtA)
  $gbCloud.Controls.Add((LBL 12 64 440 20 '第二个候选（DS官方）→'))
  $txtB = New-Object System.Windows.Forms.TextBox
  $txtB.Location = [System.Drawing.Point]::new(12, 86)
  $txtB.Width = 440
  $txtB.Text = 'deepseek/deepseek-v4-pro（DS官方）'
  $gbCloud.Controls.Add($txtB)
  $btnA = BTN 12 112 150 26 '切到云端'
  $btnA.Add_Click({
    $m = $txtA.Text.Trim()
    $ans = [System.Windows.Forms.MessageBox]::Show('把「要模型」的定时任务全换成 ' + $m + "`n" + '云端按量计费，会产生费用。' + "`n" + '纯脚本任务不动；改完读回确认。', '确认切到云端', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'cron-set' $m -1 ('切定时任务→' + $m) $null }
  })
  $gbCloud.Controls.Add($btnA)
  $btnB = BTN 172 112 150 26 '切到DS官方'
  $btnB.Add_Click({
    $m = $txtB.Text.Trim()
    $ans = [System.Windows.Forms.MessageBox]::Show('把「要模型」的定时任务全换成 ' + $m + "`n" + '云端按量计费，会产生费用。' + "`n" + '纯脚本任务不动；改完读回确认。', '确认切到DS官方', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'cron-set' $m -1 ('切定时任务→' + $m) $null }
  })
  $gbCloud.Controls.Add($btnB)
  $gbCloud.Controls.Add((LBL 12 146 440 20 '单个任务：先选任务，再选模型 →'))
  $cmbJob = New-Object System.Windows.Forms.ComboBox
  $cmbJob.Location = [System.Drawing.Point]::new(12, 168)
  $cmbJob.Width = 440
  $cmbJob.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
  $gbCloud.Controls.Add($cmbJob)
  $cmbJobModel = New-Object System.Windows.Forms.ComboBox
  $cmbJobModel.Location = [System.Drawing.Point]::new(12, 196)
  $cmbJobModel.Width = 300
  $cmbJobModel.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
  $cmbJobModel.Text = 'scnet/DeepSeek-V4.1-Flash'
  $gbCloud.Controls.Add($cmbJobModel)
  $btnOne = BTN 320 196 132 26 '只改这一个'
  $btnOne.Add_Click({
    $jn = PickJobName
    $mm = PickModelRef2
    if (-not $jn) { [System.Windows.Forms.MessageBox]::Show('先在上面的下拉里选一个定时任务。', '没选任务'); return }
    $ans = [System.Windows.Forms.MessageBox]::Show('只把「' + $jn + '」换成 ' + $mm + "`n" + '改任务定义即时生效，不需重启网关。', '确认单个换', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'cron-set-one' $mm -1 ('只改' + $jn + '→' + $mm) @('-JobName', $jn) }
  })
  $gbCloud.Controls.Add($btnOne)
  $lblScopeNote = LBL 12 228 440 20 '本页只换定时任务；对话窗口在页③换'
  $lblScopeNote.ForeColor = $WARN
  $gbCloud.Controls.Add($lblScopeNote)
  $lblCloudState = LBL 12 254 440 20 '状态：—'
  $gbCloud.Controls.Add($lblCloudState)
  $lblHbState = LBL 12 280 440 20 '心跳与压缩：—（改它需重启网关）'
  $gbCloud.Controls.Add($lblHbState)
  $cmbHb = New-Object System.Windows.Forms.ComboBox
  $cmbHb.Location = [System.Drawing.Point]::new(12, 304)
  $cmbHb.Width = 300
  $cmbHb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
  $cmbHb.Text = 'scnet/DeepSeek-V4.1-Flash'
  $gbCloud.Controls.Add($cmbHb)
  $btnHb = BTN 320 304 132 26 '改心跳与压缩'
  $btnHb.Add_Click({
    $mm = PickModelRef3
    $ans = [System.Windows.Forms.MessageBox]::Show('把心跳与压缩模型改成 ' + $mm + "`n" + '这会写 openclaw.json（先自动备份），改完需重启网关才生效。' + "`n" + '默认配置：心跳与压缩用云端模型，不跟本地大块头抢活。', '确认改心跳', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { RunAction 'hb-set' $mm -1 '改心跳与压缩模型' $null }
  })
  $gbCloud.Controls.Add($btnHb)
  $gbCloud.Controls.Add((LBL 12 334 440 12 '切定时任务：不需起服务、不需重启网关'))
  $t4.Controls.Add($gbCloud)

  function LoadSysList {
    # [2026-10-19 v16] 读「定时任务定义」表：中文名 + 什么时候跑 + 用哪个模型（纯脚本任务标「纯脚本·不用模型」）
    try {
      if (-not (Test-Path $CRONF)) { $lblSysState.Text = '未读取：点「刷新列表」'; return }
      $rows = Get-Content $CRONF -Raw -Encoding UTF8 | ConvertFrom-Json
      for ($i = 0; $i -lt $sysLbl.Count; $i++) {
        if ($i -ge $rows.Count) { $sysLbl[$i].Text = ''; continue }
        $w = $rows[$i]
        # 自截图实测：440px 装不下整句 → 名字截 14 字、模型只留尾巴、不显示已用量
        $nm = [string]$w.name
        if ($nm.Length -gt 14) { $nm = ($nm.Substring(0, 14) + '…') }
        $md = [string]$w.model
        if ($md.Contains('/')) { $md = $md.Split('/')[1] }
        if (-not $md) { $md = '纯脚本·不用模型' }
        $offTxt = if ($w.enabled) { '' } else { '(停)' }
        $tagTxt = if ($w.provTag) { ('[' + $w.provTag + '] ') } else { '' }
        $fbTxt = if ($w.fallbackTags -and $w.fallbackTags.Count -gt 0) { ('（备用:' + ($w.fallbackTags -join ',') + '）') } else { '' }
        $sysLbl[$i].Text = ($nm + $offTxt + ' · ' + [string]$w.when + ' · ' + $tagTxt + $md + $fbTxt)
        # [2026-10-19 v17] 要模型的任务标橙、纯脚本标灰，一眼看出哪些会被「切云端」影响
        $sysLbl[$i].ForeColor = if ($w.needsModel) { $WARN } else { $OFF }
      }
      $on = 0; $need = 0
      foreach ($w in $rows) { if ($w.enabled) { $on++ }; if ($w.needsModel -and $w.enabled) { $need++ } }
      $lblSysState.Text = ('共 ' + $rows.Count + ' 个：' + $on + ' 跑、' + ($rows.Count - $on) + ' 停、' + $need + ' 要模型 · ' + (Get-Date -Format 'HH:mm:ss'))
      $models = @()
      foreach ($w in $rows) {
        if (-not $w.enabled) { continue }
        $m2 = [string]$w.model
        if ($m2.Contains('/')) { $m2 = $m2.Split('/')[1] }
        if (-not $m2) { $m2 = '纯脚本' }
        if (-not ($models -contains $m2)) { $models += $m2 }
      }
      $lblCloudState.Text = ('定时任务定义里的模型：' + (($models | Sort-Object) -join ' / '))
      # [2026-10-19 v16] 心跳/压缩单独一行：拼在一起超过 440px 会被右缘截断（自截图实测）
      if (Test-Path $HBF) {
        try {
          $hb = Get-Content $HBF -Raw -Encoding UTF8 | ConvertFrom-Json
          $hbt = [string]$hb.heartbeat
          if ($hbt.Contains('/')) { $hbt = $hbt.Split('/')[1] }
          $cmt = [string]$hb.compaction
          if ($cmt.Contains('/')) { $cmt = $cmt.Split('/')[1] }
          if ($hbt) {
            # 心跳与压缩是同一个模型时只写一次（自截图实测：两个长名拼一起会被右缘截断）
            $hbShow = if ($hbt -eq $cmt) { $hbt } else { ($hbt + ' / ' + $cmt) }
            $lblHbState.Text = ('心跳与压缩：' + $hbShow + '（改需重启网关）')
          }
        } catch {}
      }
    } catch {
      $lblSysState.Text = ('读失败：' + $_.Exception.Message)
    }
  }

  function LoadWindowList {
    try {
      if (-not (Test-Path $WINF)) { $lblWinState.Text = '未读取：点「刷新列表」'; return }
      $rows = Get-Content $WINF -Raw -Encoding UTF8 | ConvertFrom-Json
      $n = [Math]::Min($rows.Count, $winLbl.Count)
      for ($i = 0; $i -lt $winLbl.Count; $i++) {
        if ($i -ge $rows.Count) { $winLbl[$i].Text = ''; continue }
        $w = $rows[$i]
        $usedTxt = if ($w.used -eq $null) { '-' } else { [string]$w.used }
        $runTxt = if ($w.running) { ' [正在跑]' } else { '' }
        $winLbl[$i].Text = ($w.name + ' (' + $w.where + ')' + $runTxt + ' → ' + $w.model + '  已用 ' + $usedTxt)
      }
      $lblWinState.Text = ('共 ' + $rows.Count + ' 个对话窗口，读于 ' + (Get-Date -Format 'HH:mm:ss'))
    } catch {
      $lblWinState.Text = ('读窗口清单失败：' + $_.Exception.Message)
    }
  }

  # [2026-10-19 v16] 自查：自动点一次「刷新列表」（两个都是只读动作，不动任何服务/窗口），
  #   等子进程结束后再手动填列表 —— 这样即使定时器还没启动也能填出来
  # [2026-10-20 v18] 用户：别等采集完才弹窗 —— 窗口先开，采集在后台并行跑，完一项填一项
  $global:jobs = @{}
  $global:collectStarted = $false
  $global:collected = 0
  $global:collectTotal = 0
  $global:FREE = @{}
  $global:POW = @{}
  function StartCollect {
    if ($global:collectStarted) { return }
    $global:collectStarted = $true
    if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Force -Path $LOGDIR | Out-Null }
    $spec = @(
      @{ n='显卡显存与功率'; kind='gpu';   exe='nvidia-smi'; args='--query-gpu=index,memory.free,power.limit,power.default_limit,power.min_limit,power.max_limit,power.draw --format=csv,noheader,nounits'; out=(Join-Path $LOGDIR 'collect-gpu.txt') },
      @{ n='对话窗口清单';   kind='win';   exe='node'; args=('"' + $WINCJS + '" list --json --out "' + $WINF + '"'); out=(Join-Path $LOGDIR 'collect-win.txt') },
      @{ n='定时任务清单';   kind='cron';  exe='node'; args=('"' + $CRONJS + '" list --out "' + $CRONF + '" --hbfile "' + $HBF + '"'); out=(Join-Path $LOGDIR 'collect-cron.txt') },
      @{ n='可换模型清单';   kind='model'; exe='node'; args=('"' + $WINCJS + '" models --json --out "' + $MODF + '"'); out=(Join-Path $LOGDIR 'collect-models.txt') },
      @{ n='官方最新版本';   kind='ver';   exe='node'; args=('"' + $VERJS + '" --out "' + $VERF + '"'); out=(Join-Path $LOGDIR 'collect-ver.txt') },
      @{ n='本机环境自检';   kind='self';  exe='node'; args=('"' + $SELFJS + '" --out "' + $SELFF + '"'); out=(Join-Path $LOGDIR 'collect-self.txt') },
      @{ n='显存实测校准';   kind='calib'; exe='pwsh'; args=('-NoProfile -ExecutionPolicy Bypass "' + $RUN + '" calib'); out=(Join-Path $LOGDIR 'collect-calib.txt') }
    )
    foreach ($s in $spec) {
      try {
        # [2026-10-20 v22] 用户要「换电脑也能用」：exe 名先解析成真实路径（PATH 里没有也能跑）
        $exe = [string]$s.exe
        if ($exe -eq 'node') { if ($NODE) { $exe = [string]$NODE } }
        elseif ($exe -eq 'pwsh') { if ($PWSH) { $exe = [string]$PWSH } }
        $p = Start-Process -FilePath $exe -ArgumentList $s.args -WindowStyle Hidden -PassThru `
          -RedirectStandardOutput $s.out -RedirectStandardError ($s.out + '.err')
        $global:jobs[$s.n] = [pscustomobject]@{ proc = $p; kind = $s.kind; out = $s.out; done = $false }
        $global:collectTotal++
      } catch { LogErr ('StartCollect 单项失败 ' + $s.n + ' : ' + $_.Exception.Message); AppendLog('  采集启动失败（' + $s.n + '）：' + $_.Exception.Message + [char]10) }
    }
    LogErr ('StartCollect 完成：启动 ' + $global:collectTotal + ' 个分离进程')
    AppendLog((Get-Date -Format 'HH:mm:ss') + '  窗口先打开，后台并行采集 ' + $global:collectTotal + ' 项（显存功率/窗口/定时任务/模型清单/官方版本/环境自检/显存校准）' + [char]10)
  }
  function ApplyGpuCollect([string]$txt) {
    $global:FREE = @{}
    $global:POW = @{}
    foreach ($ln in ($txt -split [char]10)) {
      $p = ($ln -split ',')
      if ($p.Count -lt 7) { continue }
      $id = [int]$p[0].Trim() + 1
      $global:FREE[$id] = [int]$p[1].Trim()
      $global:POW[$id] = [pscustomobject]@{ cur = $p[2].Trim(); def = $p[3].Trim(); mn = $p[4].Trim(); mx = $p[5].Trim(); draw = $p[6].Trim() }
    }
    for ($i = 0; $i -lt [Math]::Min($powRow.Count, $GPUS.Count); $i++) {
      $g = $GPUS[$i]
      $pv = $global:POW[$g.Id]
      if ($pv -and $pv.cur) {
        $powIdx[$i].Text = ('上限 ' + [int][double]$pv.cur + ' W（默认 ' + [int][double]$pv.def + '，可设 ' + [int][double]$pv.mn + '-' + [int][double]$pv.mx + '）')
        $powRow[$i].Text = [string][int][double]$pv.cur
      } else { $powIdx[$i].Text = '上限：读不到（该卡不支持或无驱动）' }
    }
    $shown = @()
    foreach ($g in $GPUS) { $pv = $global:POW[$g.Id]; if ($pv -and $pv.draw) { $shown += ('显卡' + $g.Id + ' 现在耗 ' + [int][double]$pv.draw + ' W') } }
    $lblPowState.Text = ('功率：' + ($shown -join '  ｜ ') + '（读于 ' + (Get-Date -Format 'HH:mm:ss') + '）')
  }
  function RamText {
    # [2026-10-20 v20] 用户：「再加一个内存用量 占用 显示」——本机 128G，读 TotalPhysicalMemory/AvailablePhysicalMemory
    try {
      $ci = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
      $totGB = [math]::Round($ci.TotalPhysicalMemory / 1GB, 0)
      $useGB = [math]::Round(($ci.TotalPhysicalMemory - $ci.AvailablePhysicalMemory) / 1GB, 0)
      $global:ramPct = [int][math]::Round(($useGB / $totGB) * 100, 0)
      return ('内存 ' + $useGB + '/' + $totGB + 'G ' + $global:ramPct + '%')   # [2026-10-21 v24] 与显卡同格式且去全角括号（省宽度，防换行被裁）
    } catch { $global:ramPct = -1; return '内存：读不到' }
  }
  function ApplyCalib([string]$txt) {
    # [2026-10-20 v22] 执行器 calib 的输出：每行「tier,占用MiB」→ 落 console-calib.json，页① 的「可起/显存不够」立刻改用实测值
    $rows = @()
    foreach ($ln in (($txt ?? '') -split [char]10)) {
      $p = ($ln -split ',')
      if ($p.Count -lt 2) { continue }
      $kk = $p[0].Trim()
      $vv = 0
      if (-not [int]::TryParse($p[1].Trim(), [ref]$vv)) { continue }
      if ($vv -le 0) { continue }
      $rows += [pscustomobject]@{ tier = $kk; used = $vv; at = (Get-Date -Format 'yyyy-MM-dd HH:mm') }
    }
    if ($rows.Count -eq 0) { return }
    try { $rows | ConvertTo-Json -Depth 4 | Set-Content -Path $CALF -Encoding UTF8 } catch { }
    $global:CAL = @{}
    foreach ($r in $rows) { $global:CAL[$r.tier] = [int]$r.used }
  }
  function ApplySelfCheck([string]$txt) {
    # [2026-10-20 v22] 自检输出（node 直接落 console-selfcheck.json），这里只填页⑦
    try { LoadSelfCheck } catch { }
  }
  function UpdateHeader([object]$sPre = $null) {
    # [2026-10-21 v23] 允许把 RefreshState 已读到的 :8080 状态传进来，省一次 HTTP（实测 10-88ms）
    $s = if ($sPre) { $sPre } else { try { StrataStatus } catch { $null } }
    $bits = @()
    if ($s -and $s.current) { $bits += ('当前模型：' + $s.current) } else { $bits += '当前模型：无（大块头未起）' }   # [2026-10-20 v20b] 段与文字都收紧，保证一行放得下
    # [2026-10-20 v21] 用户：「显卡 跟内存统一一下，就都用G 然后加%多少，显示模式一样」
    #   → 与内存同格式「用/总G（%）」；内部判断（可起/显存不够）仍用 MiB，只是显示换了写法
    foreach ($g in $GPUS) {
      $f = $global:FREE[$g.Id]
      if ($f -eq $null) { $f = (LiveFree)[$g.Id] }
      if ($f -eq $null) { $bits += ('显卡' + $g.Id + ' 读不到'); continue }
      $totM = [int]$g.MiB
      $useM = $totM - [int]$f
      if ($useM -lt 0) { $useM = 0 }
      $pct = [int][math]::Round(($useM / $totM) * 100, 0)
      # [2026-10-21 v24] 全角括号（）各占 11px，两段就吃掉 40+px；改成「23/24G 99%」半角写法，数字含义不变
      $bits += ('显卡' + $g.Id + ' ' + [int][math]::Floor($useM / 1024) + '/' + [int][math]::Round($totM / 1024, 0) + 'G ' + $pct + '%')
    }
    $bits += (RamText)   # [2026-10-20 v20] 内存用量（用户新加）
    # [2026-10-21 v24] 用户：「你加了个时间，这个时间是什么时间没有标注没有名称」→ 明确写「刷新于」，不再用裸 @时分秒
    $bits += ('采集 ' + $global:collected + '/' + $global:collectTotal + ' 刷新于 ' + (Get-Date -Format 'HH:mm:ss'))
    $hdrLbl.Text = ($bits -join ' ｜ ')   # [2026-10-21 v24] 分隔符从「  ｜  」改「 ｜ 」：四段之间再省 48px，保证一行放得下不被裁
    # [2026-10-20 v20] 内存吃紧（≥85%）时整条状态文字变橙，平时深蓝
    if ($global:ramPct -ge 85) { $hdrLbl.ForeColor = $WARN } else { $hdrLbl.ForeColor = $ACC }
  }
  function PollCollect {
    $anyDone = $false
    foreach ($k in @($global:jobs.Keys)) {
      $e = $global:jobs[$k]
      if ($e.done) { continue }
      $exited = $false
      try { $exited = $e.proc.HasExited } catch { $exited = $true }
      if (-not $exited) { continue }
      $e.done = $true
      $global:collected++
      $code = try { [int]$e.proc.ExitCode } catch { -1 }
      $ok = if ($code -eq 0) { '完成' } else { ('失败 exit=' + $code) }
      AppendLog((Get-Date -Format 'HH:mm:ss') + '  采集' + $ok + '：' + $k + '（' + $global:collected + '/' + $global:collectTotal + '）' + [char]10)
      $txt = $null
      try { if (Test-Path $e.out) { $txt = Get-Content $e.out -Raw -Encoding UTF8 } } catch { }
      switch ($e.kind) {
        'gpu'   { try { ApplyGpuCollect -txt ([string]$txt) } catch { AppendLog('  显存功率解析失败：' + $_.Exception.Message + [char]10) } }
        'win'   { LoadWindowList }
        'cron'  { LoadSysList; LoadJobChoices }
        'model' { LoadModelChoices }
        'ver'   { LoadVersions }
        'self'  { try { ApplySelfCheck -txt ([string]$txt) } catch { AppendLog('  自检解析失败：' + $_.Exception.Message + [char]10) } }
        'calib' { try { ApplyCalib -txt ([string]$txt) } catch { AppendLog('  校准解析失败：' + $_.Exception.Message + [char]10) } }
      }
      $anyDone = $true
    }
    if ($anyDone) { UpdateHeader }
  }
  if ($AutoRefresh) {
    RunAction 'win-list' '' -1 '读窗口清单' $null
    for ($k = 0; $k -lt 25; $k++) {
      if (-not $global:curProc -or $global:curProc.HasExited) { break }
      Start-Sleep -Seconds 1
    }
    LoadWindowList
    RunAction 'cron-list' '' -1 '读定时任务清单' $null
    for ($k = 0; $k -lt 25; $k++) {
      if (-not $global:curProc -or $global:curProc.HasExited) { break }
      Start-Sleep -Seconds 1
    }
    LoadSysList
  }
  # [2026-10-19 v13] 开机时日志框不再空白：写一行就绪状态（只读，不动任何服务）
  AppendLog((Get-Date -Format 'HH:mm:ss') + '  控制台就绪：' + $statusLbl.Text + [char]10)
  AppendLog('  起/停按钮都会先弹确认；日志只写本窗口，不动其它窗口' + [char]10)

  if ($Layout) {
    foreach ($tp in $tabs.TabPages) {
      Write-Host ('== ' + $tp.Text + ' == inner ' + $tp.Width + 'x' + $tp.Height)
      foreach ($c in $tp.Controls) {
        $cn = $c.GetType().Name
        $ax = $tabs.Location.X + $tp.Location.X + $c.Location.X
      $ay = $tabs.Location.Y + $tp.Location.Y + $c.Location.Y
      Write-Host ('  ' + $cn + ' pos ' + $c.Location.X + ',' + $c.Location.Y + ' size ' + $c.Size.Width + ' by ' + $c.Size.Height + ' | abs ' + $ax + ',' + $ay + '..' + ($ax + $c.Size.Width) + ',' + ($ay + $c.Size.Height) + ' | ' + $c.Text)
        if ($cn -eq 'GroupBox') {
          foreach ($cc in $c.Controls) {
            Write-Host ('    ' + $cc.GetType().Name + ' pos ' + $cc.Location.X + ',' + $cc.Location.Y + ' size ' + $cc.Size.Width + ' by ' + $cc.Size.Height + ' | ' + $cc.Text + ' enabled=' + $cc.Enabled)
          }
        }
      }
    }
    return
  }


  # ---------- 页⑤ 功率 · 版本 · 官方链接（v17 新增） ----------
  $t5 = New-Object System.Windows.Forms.TabPage
  $t5.Text = '功率 · 版本 · 链接'
  $tabs.TabPages.Add($t5)
  # [2026-10-20 v18] 用户问「官方链接是不是每次点开自动刷新」——是的：每次进页⑤自动重读一次
  # [2026-10-21 v23] 旧写法用 RunAction（独占动作槽，实测读一次 2-5 秒）→ 这期间切页/点按钮全弹「上一个任务还在跑」。
  #   改成独立后台读：不占槽、不弹窗、60 秒内不重复读、正在读就不重复起。
  $tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedIndex -eq 4) {
      $vr = StartVersionsRead
      if ($vr -eq 'started') { AppendLog((Get-Date -Format 'HH:mm:ss') + '  后台读官方最新版本（不挡你切页）' + [char]10) }
      elseif ($vr -eq 'running') { AppendLog((Get-Date -Format 'HH:mm:ss') + '  官方版本正在读，读完自动填页⑤' + [char]10) }
      elseif ($vr -eq 'fresh') { try { LoadVersions } catch { } }
    }
  })

  $gbPow = GB $colX[0] 12 $GBW 340 '显卡功率限制（瓦）'
  $powRow = @()
  $powIdx  = @()
  for ($i = 0; $i -lt [Math]::Min($GPUS.Count, 2); $i++) {
    $g = $GPUS[$i]
    $yy = 22 + $i * 62
    $gbPow.Controls.Add((LBL 12 $yy 200 20 ('显卡' + $g.Id + '  ' + $g.Name)))
    $st = LBL 12 ($yy + 24) 300 20 '上限：读不到（该卡不支持或无驱动）'
    $gbPow.Controls.Add($st)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = [System.Drawing.Point]::new(320, ($yy + 22))
    $tb.Width = 60
    $gbPow.Controls.Add($tb)
    $ap = BTN 392 ($yy + 22) 60 24 '应用'
    $ap.Tag = [pscustomobject]@{ smi = $g.Smi; gid = $g.Id; name = $g.Name; box = $tb }
    $ap.Add_Click({
      $tt = $this.Tag
      $wv = [string]$tt.box.Text.Trim()
      if ($wv -notmatch '^\d+$') { [System.Windows.Forms.MessageBox]::Show('必须是整数瓦数。', '输入有误', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return }
      $ans = [System.Windows.Forms.MessageBox]::Show('把显卡' + $tt.gid + '（' + $tt.name + '）的功率上限设为 ' + $wv + ' W。' + [char]10 + '影响：这张卡跑得慢一点、发热与耗电降低；显存与模型装载不受影响；重启电脑后自动回默认。' + [char]10 + '要管理员权限（被拒会再问你是否提权）。', '确认设功率', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
      if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
      SetPower ([int]$tt.smi) ([int]$wv) ([string]$tt.gid)
    })
    $gbPow.Controls.Add($ap)
    $powRow += $tb
    $powIdx  += $st
  }
  $lblPowState = LBL 12 156 440 20 '功率：读不到（nvidia-smi 无响应）'
  $gbPow.Controls.Add($lblPowState)
  $gbPow.Controls.Add((LBL 12 184 440 20 '原理：nvidia-smi --power-limit（驱动级，软件即可）'))
  $gbPow.Controls.Add((LBL 12 212 440 20 '只改指定那张卡，另一张不受影响'))
  $gbPow.Controls.Add((LBL 12 240 440 20 '重启电脑后自动回默认上限'))
  $gbPow.Controls.Add((LBL 12 268 440 20 '显存与模型装载不受影响，只是慢一点'))
  $gbPow.Controls.Add((LBL 12 296 440 20 '回滚：填回默认值再「应用」（读回会报现值）'))
  # [2026-10-20 v19] 写功率要管理员：双击打开时是普通权限，会被 nvidia-smi 拒；点「应用」会自动问要不要提权重试
  $gbPow.Controls.Add((LBL 12 324 440 20 '写功率要管理员：点「应用」若被拒会问你是否提权（弹一次 UAC）'))
  $t5.Controls.Add($gbPow)

  $gbVer = GB $colX[1] 12 $GBW 340 '版本与官方链接'
  $lblVer1 = LBL 12 22 440 20 '版本：读不到'
  $lblVer1.Font = New-Object System.Drawing.Font('Microsoft YaHei', 9.5, [System.Drawing.FontStyle]::Bold)
  $lblVer1.ForeColor = $ACC
  $gbVer.Controls.Add($lblVer1)
  $lblVer2 = LBL 12 50 440 20 ''
  $gbVer.Controls.Add($lblVer2)
  $lblVer3 = LBL 12 78 440 20 ''
  $gbVer.Controls.Add($lblVer3)
  # 可点链接（抄参考项目：点文字直接开浏览器）
  $links = @(
    @('OpenClaw 官方 GitHub（更新说明）', 'https://github.com/openclaw/openclaw/releases'),
    @('OpenClaw 官方文档', 'https://docs.openclaw.ai'),
    @('Strata 引擎 GitHub（更新说明）', 'https://github.com/Niko1221/Strata/releases'),
    @('模型页（Qwen3.8-Flash-Next）', 'https://huggingface.co/Qwen/Qwen3.8-Flash-Next'),
    @('llama.cpp 发布页', 'https://github.com/ggml-org/llama.cpp/releases')
  )
  for ($i = 0; $i -lt $links.Count; $i++) {
    $lk = New-Object System.Windows.Forms.LinkLabel
    $lk.Text = $links[$i][0]
    $lk.Tag = $links[$i][1]
    $lk.Location = [System.Drawing.Point]::new(12, (106 + $i * 26))
    $lk.Size = [System.Drawing.Size]::new(440, 20)
    $lk.LinkColor = $ACC
    $lk.Add_Click({ try { Start-Process ([string]$this.Tag) } catch {} })
    $gbVer.Controls.Add($lk)
  }
  $gbVer.Controls.Add((LBL 12 240 440 20 '本机：OpenClaw 装在 npm 全局；Strata 引擎在'))
  $gbVer.Controls.Add((LBL 12 268 440 20 'D:\06.AItools\Strata\engine\（BUILD.json 记版本）'))
  $gbVer.Controls.Add((LBL 12 296 440 20 '本页只读版本；升级在升级窗口做'))
  $t5.Controls.Add($gbVer)

  # ---------- 页⑥ 本机入口（v20 新增） ----------
  # 本机服务入口（带实时在跑状态）+ 常用文件位置；网关救援在页②、版本与官方链接在页⑤
  $t6 = New-Object System.Windows.Forms.TabPage
  $t6.Text = '本机入口'
  $tabs.TabPages.Add($t6)

  $gbLocal = GB $colX[0] 12 $GBW 340 '本机服务入口（点文字直接开）'
  # [2026-10-22 v26] 入口清单改从配置 ENTRIES 读（[名称, 端口, 网址]）；配置没给就用本机这三条
  $localSrv = if ($CFGENT) { $CFGENT } else { @(
    @(('Strata 监控台（大块头 :' + $global:BIGPORT + '）'), $global:BIGPORT,  ('http://127.0.0.1:' + $global:BIGPORT + '/')),
    @('OpenClaw 控制台（网关 :18789）',      18789, 'http://127.0.0.1:18789/'),
    @('知识库（:8989）',                  8989,  'http://127.0.0.1:8989/')
  ) }
  $localStat = @()
  for ($i = 0; $i -lt $localSrv.Count; $i++) {
    $yy = 24 + $i * 34
    $lk = New-Object System.Windows.Forms.LinkLabel
    $lk.Text = $localSrv[$i][0]
    $lk.Tag = $localSrv[$i][2]
    $lk.Location = [System.Drawing.Point]::new(12, $yy)
    $lk.Size = [System.Drawing.Size]::new(320, 22)
    $lk.Font = New-Object System.Drawing.Font('Microsoft YaHei', 10, [System.Drawing.FontStyle]::Bold)
    $lk.LinkColor = $ACC
    $lk.ActiveLinkColor = $WARN
    $lk.Add_Click({ try { Start-Process ([string]$this.Tag) } catch {} })
    $gbLocal.Controls.Add($lk)
    $st = LBL 340 ($yy + 2) 110 20 '未测'
    $gbLocal.Controls.Add($st)
    $localStat += [pscustomobject]@{ port = [int]$localSrv[$i][1]; lbl = $st }
  }
  $gbLocalNotes = if ($CFGNOTES) { $CFGNOTES } else { @(
    '对应桌面「模型服务控制台」里那三个快捷方式：',
    ('大块头监控=' + $global:BIGPORT + '、OpenClaw 控制台=18789、知识库=8989'),
    '知识库没在跑时点了会连不上（先起知识库服务）',
    '右上角最左边那个「Strata 监控」是同一个地址'
  ) }
  for ($n = 0; $n -lt [Math]::Min(4, $gbLocalNotes.Count); $n++) {
    $gbLocal.Controls.Add((LBL 12 (132 + $n * 26) 440 20 ([string]$gbLocalNotes[$n])))
  }
  $t6.Controls.Add($gbLocal)

  $gbFiles = GB $colX[1] 12 $GBW 340 '常用文件与文件夹（点了开资源管理器）'
  # [2026-10-22 v26] 位置改用脚本里已有的路径变量拼（不再写死本机绝对路径）；
  #   哪条在这台机器上不存在就不显示那条，换机器不会指到空地方、点了也不会报错。
  $localFilesAll = @(
    @('本地模型部署清单（存放位置+谁服务谁）.txt', ([Environment]::GetFolderPath('Desktop')) + '\模型服务控制台\本地模型部署清单（存放位置+谁服务谁）.txt'),
    @('项目文档 docs 文件夹', $DOCSF),
    @('控制台便携包文件夹（脚本与日志）', $PACKDIR),
    @('控制台日志文件夹', $LOGDIR),
    @('Strata 引擎与档位配置', $TIER_DIR),
    @('模型文件盘（gguf）', $MODELDISK)
  )
  $localFiles = @()
  foreach ($row in $localFilesAll) { if ($row[1] -and (Test-Path -LiteralPath $row[1])) { $localFiles += ,$row } }
  for ($i = 0; $i -lt $localFiles.Count; $i++) {
    $yy = 24 + $i * 30
    $lk = New-Object System.Windows.Forms.LinkLabel
    $lk.Text = $localFiles[$i][0]
    $lk.Tag = $localFiles[$i][1]
    $lk.Location = [System.Drawing.Point]::new(12, $yy)
    $lk.Size = [System.Drawing.Size]::new(440, 22)
    $lk.LinkColor = $ACC
    $lk.Add_Click({ try { Start-Process ([string]$this.Tag) } catch {} })
    $gbFiles.Controls.Add($lk)
  }
  $gbFilesNotes = if ($CFGFNOTE) { $CFGFNOTE } else { @(
    '这些就是桌面快捷方式指向的真实位置（我查过那个文件夹）',
    '升级说明与官方 GitHub 在页⑤；网关救援按钮在页②',
    '杜比插件 / 梦境日记 / 启动画图 不是模型服务，没往这儿搬'
  ) }
  for ($n = 0; $n -lt [Math]::Min(3, $gbFilesNotes.Count); $n++) {
    $gbFiles.Controls.Add((LBL 12 (212 + $n * 26) 440 20 ([string]$gbFilesNotes[$n])))
  }
  $t6.Controls.Add($gbFiles)

  # ---------- 页⑦ 自检（v22 新增） ----------
  # [2026-10-20 v22] 用户要的「打开软件自己检测模型、和 openclaw / strata 的状态」：每次开窗口后台跑一次 model-detect.cjs
  #   它顺带自动定位 pwsh / node / nvidia-smi / openclaw / Strata / llama-server / 模型盘 的真实路径（--write 才会改 console-paths.json，默认不改）
  $t7 = New-Object System.Windows.Forms.TabPage
  $t7.Text = '自检'
  $tabs.TabPages.Add($t7)

  $gbSelf = GB 8 12 944 340 '本机环境自检（开窗口自动跑一次；缺的项会写明装哪儿）'
  $lblSelfSum = LBL 12 22 900 22 '自检：未跑'
  $lblSelfSum.Font = New-Object System.Drawing.Font('Microsoft YaHei', 10, [System.Drawing.FontStyle]::Bold)
  $lblSelfSum.ForeColor = $ACC
  $gbSelf.Controls.Add($lblSelfSum)
  $lstSelf = New-Object System.Windows.Forms.ListBox
  $lstSelf.Location = [System.Drawing.Point]::new(12, 50)
  $lstSelf.Size = [System.Drawing.Size]::new(920, 220)
  $lstSelf.Font = New-Object System.Drawing.Font('Consolas', 9)
  $lstSelf.IntegralHeight = $false
  $gbSelf.Controls.Add($lstSelf)
  $lblSelfFix = LBL 12 278 900 20 '自动定位：默认只报告不改配置；要让它把找不到的路径写回 console-paths.json，跑 model-detect.cjs --write'
  $gbSelf.Controls.Add($lblSelfFix)
  $btnSelf = BTN 12 302 120 26 '重新自检'
  $btnSelf.Add_Click({ RunAction 'detect' '' -1 '本机环境自检' $null })
  $gbSelf.Controls.Add($btnSelf)
  $btnSelfW = BTN 144 302 200 26 '自检并修正路径'
  $btnSelfW.Add_Click({ RunAction 'detect-write' '' -1 '自检并修正路径' $null })
  $gbSelf.Controls.Add($btnSelfW)
  $lblCalState = LBL 356 302 560 26 '显存实测：未读到（起过某档后自动记录该档实测值）'
  $lblCalState.ForeColor = $OFF
  $gbSelf.Controls.Add($lblCalState)
  $t7.Controls.Add($gbSelf)

  function LoadSelfCheck {
    # [2026-10-20 v22] 读 console-selfcheck.json 填页⑦
    if (-not (Test-Path $SELFF)) { $lblSelfSum.Text = '自检：未跑（跑 model-console-run.ps1 detect）'; return }
    try {
      $j = Get-Content $SELFF -Raw -Encoding UTF8 | ConvertFrom-Json
      $lblSelfSum.Text = ('自检：通过 ' + $j.okCount + ' 项，缺 ' + $j.missCount + ' 项（读于 ' + $j.at + '）')
      if ($j.missCount -gt 0) { $lblSelfSum.ForeColor = $WARN } else { $lblSelfSum.ForeColor = $ON }
      $lstSelf.Items.Clear()
      foreach ($it in $j.items) {
        $mark = if ($it.ok) { '[在] ' } else { '[缺] ' }
        [void]$lstSelf.Items.Add($mark + [string]$it.name + '  →  ' + ([string]$it.path) + '   ' + [string]$it.note)
      }
    } catch { $lblSelfSum.Text = ('自检文件读不了：' + $_.Exception.Message) }
    try {
      if (Test-Path $CALF) {
        $cj = Get-Content $CALF -Raw -Encoding UTF8 | ConvertFrom-Json
        $cs = @()
        foreach ($r in @($cj)) { if ($r.tier) { $cs += ([string]$r.tier + ' ' + [string]$r.used + 'MiB') } }
        if ($cs.Count -gt 0) { $lblCalState.Text = ('显存实测：' + ($cs -join ' ｜ ')); $lblCalState.ForeColor = $ON }
      }
    } catch { }
  }

  function LoadLocalState {
    # [2026-10-20 v20] 三个本机端口实时在跑状态（ScanPorts 已在 RefreshState 里跑过，这里只读缓存，不额外查询）
    if (-not $localStat) { return }
    foreach ($e in $localStat) {
      if (Up $e.port) { $e.lbl.Text = ('在跑 :' + $e.port); $e.lbl.ForeColor = $ON }
      else { $e.lbl.Text = '未在跑'; $e.lbl.ForeColor = $OFF }
    }
  }

  function LoadVersions {
    # [2026-10-19 v17] 读本机版本 + 官方最新（读缓存 console-versions.json；缺则显示本机版本）
    try {
      $oc = '读不到'
      try {
        $ocPkg = if ($env:APPDATA) { Join-Path $env:APPDATA 'npm\node_modules\openclaw\package.json' } else { '' }
        $pk = Get-Content $ocPkg -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($pk.version) { $oc = $pk.version }
      } catch {}
      $en = '读不到'
      try {
        $bj = Get-Content (Join-Path $TIER_DIR 'engine\BUILD.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($bj.version) { $en = $bj.version }
      } catch {}
      $lblVer1.Text = ('本机版本：OpenClaw ' + $oc + ' ｜ Strata 引擎 ' + $en)
      if (Test-Path $VERF) {
        try {
          $v = Get-Content $VERF -Raw -Encoding UTF8 | ConvertFrom-Json
          $lblVer2.Text = ('官方最新：OpenClaw ' + [string]$v.openclawLatest + ' ｜ Strata ' + [string]$v.strataLatest)
          $newer = @()
          if ($v.openclawLatest -and ($v.openclawLatest -ne $oc)) { $newer += 'OpenClaw' }
          if ($v.strataLatest -and ($v.strataLatest -ne $en)) { $newer += 'Strata' }
          if ($newer.Count -gt 0) {
            $lblVer3.Text = ('有更新：' + ($newer -join ' / ') + '（在升级窗口执行）')
            $lblVer3.ForeColor = $WARN
          } else {
            $lblVer3.Text = '版本对比：已最新'
            $lblVer3.ForeColor = $ON
          }
        } catch { $lblVer2.Text = '官方最新：读不到（需联网）' }
      } else {
        $lblVer2.Text = '官方最新：未读（跑一次 model-console-run.ps1 versions）'
      }
    } catch { $lblVer1.Text = '版本读不到：' + $_.Exception.Message }
  }

  function LoadPowerInfo {
    # [2026-10-19 v17] 只读：读每张卡的当前/默认/最小/最大功率上限，填文本框与状态行
    if ($NoPower) { $lblPowState.Text = '功率：跳过（-NoPower）'; return }
    try {
      $txt = (& nvidia-smi -q -d POWER 2>$null | Out-String)
      $blocks = ($txt -split 'GPU 0000')[1..99]
      $shown = @()
      for ($i = 0; $i -lt [Math]::Min($blocks.Count, 2); $i++) {
        $b = $blocks[$i]
        $cur = [regex]::Match($b, 'Current Power Limit\s*:\s*([\d.]+)\s*W').Groups[1].Value
        $def = [regex]::Match($b, 'Default Power Limit\s*:\s*([\d.]+)\s*W').Groups[1].Value
        $mn  = [regex]::Match($b, 'Min Power Limit\s*:\s*([\d.]+)\s*W').Groups[1].Value
        $mx  = [regex]::Match($b, 'Max Power Limit\s*:\s*([\d.]+)\s*W').Groups[1].Value
        $drw = [regex]::Match($b, 'Instantaneous Power Draw\s*:\s*([\d.]+)\s*W').Groups[1].Value
        if ($i -lt $powIdx.Count) {
          if ($cur) {
          $powIdx[$i].Text = ('上限 ' + [int][double]$cur + ' W（默认 ' + [int][double]$def + '，可设 ' + [int][double]$mn + '-' + [int][double]$mx + '）')
            $powRow[$i].Text = $cur
          } else { $powIdx[$i].Text = '上限：读不到（该卡不支持或无驱动）' }
          if ($drw) { $shown += ('显卡' + ($i + 1) + ' 现在耗 ' + $drw + ' W') }
        }
      }
      $lblPowState.Text = ('功率：' + (($shown | ForEach-Object { $_ }) -join ' ｜ ') + '（读于 ' + (Get-Date -Format 'HH:mm:ss') + '）')
    } catch { $lblPowState.Text = '功率读不到：' + $_.Exception.Message }
  }

  function LoadModelChoices {
    # [2026-10-19 v17] 填页③下拉菜单：本地模型排在前面，显示「中文名（本地/云端）」
    try {
      if (-not (Test-Path $MODF)) { $lblModelState.Text = '模型清单：未读（点「重扫模型清单」）'; return }
      $rows = Get-Content $MODF -Raw -Encoding UTF8 | ConvertFrom-Json
      $items = @()
      foreach ($w in ($rows | Sort-Object -Property @{ Expression = { if ($w.local) { 0 } else { 1 } } }, key)) {
        $nm = [string]$w.name
        if (-not $nm) { $nm = [string]$w.key }
        $tag = if ($w.local) { '本地' } else { '云端' }
        $items += ($nm + '（' + $tag + '）→ ' + $w.provider + '/' + $w.key)
      }
      $cmbModel.Items.Clear()
      foreach ($it in $items) { [void]$cmbModel.Items.Add($it) }
      # [2026-10-20 v18] 同一份清单也填进页④「单个任务」与「心跳」下拉
      $cmbJobModel.Items.Clear()
      $cmbHb.Items.Clear()
      foreach ($it in $items) { [void]$cmbJobModel.Items.Add($it); [void]$cmbHb.Items.Add($it) }
      $lblModelState.Text = ('模型清单：' + $items.Count + ' 个，读于 ' + (Get-Date -Format 'HH:mm:ss'))
      $lblModelState.ForeColor = $ON
    } catch { $lblModelState.Text = ('模型清单读失败：' + $_.Exception.Message); $lblModelState.ForeColor = $WARN }
  }
  function PickModelRef {
    # 下拉选中项 → 真正的 provider/模型名（尾巴）；若用户自己填了完整名则原样返回
    $s = [string]$cmbModel.Text
    if ($s.Contains('→')) { return ($s -split '→')[1].Trim() }
    return $s.Trim()
  }
  # [2026-10-20 v18] 页④两个模型下拉也取「→」后半段；任务下拉取任务名（｜ 前面那段）
  function PickModelRef2 {
    $s = [string]$cmbJobModel.Text
    if ($s.Contains('→')) { return ($s -split '→')[1].Trim() }
    return $s.Trim()
  }
  function PickModelRef3 {
    $s = [string]$cmbHb.Text
    if ($s.Contains('→')) { return ($s -split '→')[1].Trim() }
    return $s.Trim()
  }
  function PickJobName {
    $s = [string]$cmbJob.Text
    if ($s.Contains('｜')) { return ($s -split '｜')[0].Trim() }
    return $s.Trim()
  }
  function LoadJobChoices {
    try {
      if (-not (Test-Path $CRONF)) { return }
      $rows = Get-Content $CRONF -Raw -Encoding UTF8 | ConvertFrom-Json
      $items = @()
      foreach ($w in $rows) {
        if (-not $w.needsModel) { continue }
        $tag = if ($w.provTag) { ('[' + $w.provTag + '] ' + [string]$w.model) } else { '（未设模型）' }
        $off = if ($w.enabled) { '' } else { ' [停用]' }
        $items += ([string]$w.name + '｜' + $tag + $off)
      }
      $cmbJob.Items.Clear()
      foreach ($it in $items) { [void]$cmbJob.Items.Add($it) }
      if ($cmbJob.Items.Count -gt 0 -and -not [string]$cmbJob.Text) { $cmbJob.Text = [string]$items[0] }
    } catch { }
  }

  LoadVersions
  LoadPowerInfo
  LoadModelChoices

  # [2026-10-19 v13] 自截图模式：窗口打开 2.5 秒后用 DrawToBitmap 抓自己的内容再关闭
  # （比外部 CopyFromScreen / PrintWindow 可靠：不依赖窗口是否在前台，也不拍到别的窗口）
  if ($Shot) {
    if ($ShotPage -ge 1 -and $ShotPage -le $tabs.TabPages.Count) { $tabs.SelectedIndex = $ShotPage - 1 }
    $shotTimer = New-Object System.Windows.Forms.Timer
    # [2026-10-19 v16] -AutoRefresh 时多等约 8 秒：先自动跑两个只读列表，再截图，能看到列表是否真被填上
    $shotTimer.Interval = if ($AutoRefresh) { 10500 } else { 2500 }
    $shotTimer.Add_Tick({
      try {
        $bmp = New-Object System.Drawing.Bitmap $frm.Width, $frm.Height
        $frm.DrawToBitmap($bmp, [System.Drawing.Rectangle]::new(0, 0, $bmp.Width, $bmp.Height))
        $dir = Split-Path $Shot -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        AppendLog('自截图已保存：' + $Shot + [char]10)
      } catch { AppendLog ('自截图失败：' + $_.Exception.Message + [char]10) }
      $shotTimer.Stop()
      $frm.Close()
    })
    $shotTimer.Start()
  }

  # ---------- [2026-10-21 v23] 官方版本：独立后台读取（不占「上一个任务」那个动作槽） ----------
  $global:verProc = $null
  $global:verAt   = $null
  function StartVersionsRead {
    if ($global:verProc) {
      $alive = $true
      try { $alive = -not $global:verProc.HasExited } catch { $alive = $false }
      if ($alive) { return 'running' }
      $global:verProc = $null
    }
    if ($global:verAt) { try { if (((Get-Date) - $global:verAt).TotalSeconds -lt 60) { return 'fresh' } } catch { } }
    if (-not (Test-Path $LOGDIR)) { New-Item -ItemType Directory -Force -Path $LOGDIR | Out-Null }
    $exe = if ($NODE) { [string]$NODE } else { 'node' }
    $vout = Join-Path $LOGDIR 'collect-ver.txt'
    try {
      $vp = Start-Process -FilePath $exe -ArgumentList @('"' + $VERJS + '" --out "' + $VERF + '"') -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $vout -RedirectStandardError ($vout + '.err')
      $global:verProc = $vp; $global:verAt = Get-Date
      return 'started'
    } catch { AppendLog('  版本读取启动失败：' + $_.Exception.Message + [char]10); return 'failed' }
  }
  function PollVersionsRead {
    if (-not $global:verProc) { return }
    $exited = $true
    try { $exited = $global:verProc.HasExited } catch { $exited = $true }
    if (-not $exited) { return }
    $vc = try { [int]$global:verProc.ExitCode } catch { -1 }
    $global:verProc = $null
    AppendLog((Get-Date -Format 'HH:mm:ss') + '  官方版本读取结束（exit ' + $vc + '）' + [char]10)
    try { LoadVersions } catch { }
  }

  # ---------- [2026-10-21 v23] 右上角 5 秒自动刷新（用户：「一直开着软件，显存内存不会更新」） ----------
  #   实测成本：nvidia-smi 76ms、:8080/__status 10-88ms、内存 2ms、端口枚举 390-900ms
  #   → 每 5 秒刷显存/内存/当前模型；端口枚举慢，约每 4 次（20 秒）做一次；有起停动作在跑时不抢。
  $global:hdrTick = 0
  $hdrTimer = New-Object System.Windows.Forms.Timer
  $hdrTimer.Interval = 5000
  $hdrTimer.Add_Tick({
    if ($global:curProc) {
      $busy = $true
      try { $busy = -not $global:curProc.HasExited } catch { $busy = $false }
      if ($busy) { return }
    }
    $global:hdrTick++
    try {
      if (($global:hdrTick % 4) -eq 1) { RefreshState } else { RefreshState -NoScan }
    } catch { }
  })

  $timer = New-Object System.Windows.Forms.Timer
  $timer.Interval = 700
  # [2026-10-20 v18] 窗口真正显示后才做同步读取 + 启动后台采集（先弹窗、后填数据）
  $frm.Add_Shown({
    try { if (-not (Up $global:BIGPORT)) { BigPortProbe } } catch { }
    # [2026-10-21 v25] 状态改成后台异步读后，刚开窗口那一下可能还没读到 → 先最多等 1.5 秒再刷，避免误显示「未在跑」
    for ($pz = 0; $pz -lt 10; $pz++) { if (StrataStatus) { break }; Start-Sleep -Milliseconds 150 }
    try { RefreshState } catch { }
    try { UpdateReserveReadback } catch { }
    try { LoadWindowList; LoadSysList; LoadJobChoices; LoadModelChoices } catch { }
    try { ColorizeButtons } catch { }
    try { LoadLocalState } catch { }   # [2026-10-20 v20] 页⑥ 本机入口在跑状态
    try { LoadSelfCheck } catch { }    # [2026-10-20 v22] 页⑦ 自检
    try { StartCollect } catch { AppendLog('  采集启动失败：' + $_.Exception.Message + [char]10) }
    LogErr ('Add_Shown 触发：collectTotal=' + $global:collectTotal + ' 窗口可见=' + $frm.Visible)
    try { UpdateHeader } catch { }
  })
  $timer.Add_Tick({
    try { PollCollect } catch { }
    try { PollVersionsRead } catch { }   # [2026-10-21 v23] 独立槽：读完就填页⑤
    if (-not $global:curProc) { return }
    try {
      if (Test-Path $global:curLog) {
        $t = Get-Content $global:curLog -Raw -Encoding UTF8
        if ($t.Length -gt $global:offset) { AppendLog($t.Substring($global:offset)); $global:offset = $t.Length }
      }
      if (Test-Path ($global:curLog + '.err')) {
        $e = Get-Content ($global:curLog + '.err') -Raw -Encoding UTF8
        if ($e -and $e.Trim().Length -gt 0) { AppendLog($e + [char]10) }
      }
    } catch {}
    if ($global:curProc.HasExited) {
      AppendLog((Get-Date -Format 'HH:mm:ss') + '  ' + $global:curName + ' 结束（exit ' + $global:curProc.ExitCode + '）' + [char]10)
      RefreshState
      LoadWindowList
      LoadSysList
      LoadModelChoices   # [2026-10-19 v17] 扫完模型清单后自动填下拉菜单
      LoadJobChoices
      try { LoadLocalState } catch { }   # [2026-10-20 v20]
      try { $lblSwState.Text = ('最后动作：' + $global:curName + ' 结束于 ' + (Get-Date -Format 'HH:mm:ss') + '（exit ' + $global:curProc.ExitCode + '）') } catch {}
      $global:curProc = $null
    }
  })
  $timer.Start()
  $hdrTimer.Start()   # [2026-10-21 v23] 右上角 5 秒自动刷新
  LogErr ('v25 窗口已打开（' + $frm.Width + 'x' + $frm.Height + '，先弹窗后采集，右上角 5 秒自动刷新）')
  $frm.ShowDialog()
  $timer.Stop()
  try { $hdrTimer.Stop() } catch { }
} catch {
  LogErr ('窗口启动失败: ' + $_.Exception.Message)
  Write-Host ('窗口启动失败: ' + $_.Exception.Message)
  try { [System.Windows.Forms.MessageBox]::Show('控制台没能打开：' + $_.Exception.Message + "`n" + '详情：' + $RUNLOG, '控制台错误', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null } catch {}
  return
}

