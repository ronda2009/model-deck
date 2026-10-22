# D:\06.AItools\model-console-run.ps1 —— 模型服务控制台的「执行器」
# 控制台（model-console.ps1）只做界面；所有真正的起停动作在这里，按「只动指定对象」的原则写。
# 用法（控制台内部调用，也可以手动跑）：
#   pwsh -File model-console-run.ps1 status
#   pwsh -File model-console-run.ps1 start-big   -Key iq3s            # 大块头某档（双卡合扛）
#   pwsh -File model-console-run.ps1 stop-big
#   pwsh -File model-console-run.ps1 start-27b   -Key b27bx -Gpu 0    # 走 :8090 路由（OpenClaw 已注册）
#   pwsh -File model-console-run.ps1 stop-27b
#   pwsh -File model-console-run.ps1 start-vl    -Gpu 1               # 视觉 :8096（[2026-10-19 v14] 旧注释写 8101，已统一 8096）
#   pwsh -File model-console-run.ps1 stop-vl
#   pwsh -File model-console-run.ps1 stop-all
#   pwsh -File model-console-run.ps1 clear-cache
#   pwsh -File model-console-run.ps1 reserve -First 1536 -Later 300
#   pwsh -File model-console-run.ps1 gw | gw-hard
#   pwsh -File model-console-run.ps1 win-list                          # 读各对话窗口当前模型（只读）
#   pwsh -File model-console-run.ps1 win-set -Key strata/qwen3.8-flash-next-iq2x        # 换所有对话窗口
#   pwsh -File model-console-run.ps1 win-set -Key <模型> -Compact      # 换完再压上下文（切小模型时用）
#   pwsh -File model-console-run.ps1 win-set -Key <模型> -Sys          # 连系统/定时任务窗口一起换
#   pwsh -File model-console-run.ps1 sys-list                           # 读定时任务/心跳窗口（只读）
#   pwsh -File model-console-run.ps1 sys-set -Key scnet/DeepSeek-V4.1-Flash   # 只换定时任务/心跳（云端来回切）
#   pwsh -File model-console-run.ps1 sys-set -Key <模型> -ChatToo        # 上面 + 连对话窗口一起换
#   加 -DryRun = 只报「会动谁」，一个进程都不动
param(
  [string]$Action = 'status',
  [int]$Watts = 0,
  [string]$Key = '',
  [int]$Gpu = -1,
  [int]$First = 0,
  [int]$Later = 0,
  [switch]$Compact,
  [switch]$Sys,
  [switch]$ChatToo,
  [switch]$DryRun,
  [string]$JobName = ''   # [2026-10-20 v18] cron-set-one：只改这一个任务
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ---------- [2026-10-19 v15] 便携包：状态/日志/缓存写自己文件夹 ----------
# 下面绝对路径可被同目录 console-paths.json 覆盖（换机器只改那个文件，不改代码）。
$PACKDIR  = $PSScriptRoot
$PATHF    = Join-Path $PACKDIR 'console-paths.json'
$BASE     = $PACKDIR
# [2026-10-20 v22] 启动脚本（strata-router.py / strata-start-all-hidden.vbs / llama-router-start.ps1）不在本包里，
#   而在工具目录（本机 = D:\06.AItools）。旧代码用 Join-Path $BASE 找它们 → 找不到 → 起大块头报一堆错。
$TOOLDIR  = 'D:\06.AItools'   # [2026-10-21 v25] 修隐藏坏字符（原为 'D:' + 0x06 + '.AItools'）
$NODE     = 'node'
$SELFJS   = Join-Path $PACKDIR 'model-detect.cjs'
$SELFF    = Join-Path $PACKDIR 'console-selfcheck.json'
$CALF     = Join-Path $PACKDIR 'console-calib.json'
$MODELS   = 'D:\03.AImodels\llama-router'
$LLAMA_EXE = 'D:\06.AItools\llama.cpp\b11541\llama-server.exe'
$TIER_DIR = 'D:\06.AItools\Strata'
$STATEF   = Join-Path $PACKDIR 'console-state.json'
$WS       = Join-Path $PACKDIR 'logs'
$GWRESCUE = 'D:\06.AItools\openclaw\workspace\tools\gateway-rescue.ps1'
$CACHECLR = 'D:\06.AItools\strata-cache-clear.ps1'
$LLMSVC   = 'D:\06.AItools\llm-service.ps1'
# [2026-10-23 v29] pwsh 位置运行时解析（商店版在 WindowsApps 下，写死 MSI 路径在别人机器上不存在）。
#   顺序 $PSHOME → MSI 默认 → PATH；console-paths.json 的 PWSH 可覆盖。
$mcPsHome = if ($PSHOME -and (Test-Path (Join-Path $PSHOME 'pwsh.exe'))) { Join-Path $PSHOME 'pwsh.exe' } else { '' }
$mcPsMsi   = 'C:\Program Files\PowerShell\7\pwsh.exe'
$mcPsPath   = if ((Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)) { (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)[0].Source } else { '' }
$PWSH       = if ($mcPsHome) { $mcPsHome } elseif (Test-Path $mcPsMsi) { $mcPsMsi } elseif ($mcPsPath) { $mcPsPath } else { '' }
$WINCJS   = Join-Path $PACKDIR 'model-windows.cjs'
$WINF     = Join-Path $PACKDIR 'console-windows.json'
$SYSF     = Join-Path $PACKDIR 'console-syswindows.json'
$CRONJS   = Join-Path $PACKDIR 'model-crons.cjs'      # [2026-10-19 v16] 定时任务定义清单与换模型工具
$CRONF    = Join-Path $PACKDIR 'console-crons.json'   # [2026-10-19 v16] 定时任务定义缓存（界面读）
$HBF      = Join-Path $PACKDIR 'console-hbmodel.json' # [2026-10-19 v16] 心跳/压缩模型（只读 openclaw.json）
$VERJS    = Join-Path $PACKDIR 'model-versions.cjs'   # [2026-10-20 v17] 版本与官方链接采集（页⑤）
$VERF     = Join-Path $PACKDIR 'console-versions.json' # [2026-10-20 v17] 版本缓存（界面读）
$HBCJS    = Join-Path $PACKDIR 'model-hb.cjs'      # [2026-10-20 v18] 心跳/压缩模型读写（openclaw.json）
if (Test-Path $PATHF) {
  try {
    $pj = Get-Content $PATHF -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in @($pj.PSObject.Properties)) {
      $v = [string]$p.Value
      if ($v -and $p.Name -notlike '_*') { Set-Variable -Name $p.Name -Value $v }
    }
  } catch { }
}

# ---------- 模型登记表（顺序 = 桌面 bat 菜单顺序） ----------
# [2026-10-22 v27] 与界面共用外置清单 console-tiers.json，读不到用内置表；nameRun/needRun 不给就用 name/need。
#   别和 console-models.json 搞混：那是页③「可换模型」下拉的缓存（本文件 model-list 生成）。
$REG_DEF = @{
  'iq2x'  = @{ name='大块头 IQ2X（无删减 IQ2_XS）·默认'; need=42100; dual=$true;  engine='strata'; tier='iq2x' ; act='big'  }
  'q2x'   = @{ name='大块头 Q2X（无删减 Q2_0）';        need=40450; dual=$true;  engine='strata'; tier='q2x'  ; act='big'  }
  'iq3x'  = @{ name='大块头 IQ3X（无删减 IQ3_XXS）';     need=42110; dual=$true;  engine='strata'; tier='iq3x' ; act='big'  }
  'siq2x' = @{ name='S-IQ2x（Swift 无删减 IQ2_XS）';     need=40500; dual=$true;  engine='strata'; tier='siq2x'; act='big'  }
  'siq3x' = @{ name='S-IQ3x（Swift 无删减 IQ3_S）';      need=43500; dual=$true;  engine='strata'; tier='siq3x'; act='big'  }
  'c390'  = @{ name='27B Coder390-27B';                   need=19000; dual=$false; engine='llama';  id='coder390-27b'; gguf='coder390-27b.gguf'; ctx=32768; act='27b'  }
  'under' = @{ name='27B Underdog-27B';                   need=8200;  dual=$false; engine='llama';  id='underdog-27b'; gguf='underdog-27b.gguf'; ctx=32768; act='27b'  }
  'j27bx' = @{ name='27B J27bX';                          need=16300; dual=$false; engine='llama';  id='j27bx'; gguf='j27bx.gguf'; ctx=32768; act='27b'  }
  'b27bx' = @{ name='27B B27bX';                          need=16300; dual=$false; engine='llama';  id='b27bx'; gguf='b27bx.gguf'; ctx=32768; act='27b'  }
  'b27ks' = @{ name='27B B27bX-ks';                       need=15400; dual=$false; engine='llama';  id='b27bx-ks'; gguf='b27bx-ks.gguf'; ctx=32768; act='27b'  }
  'vl8'   = @{ name='Qwen3-VL-8B-Instruct-Q8_0（视觉·调图）';        need=9200;  dual=$false; engine='llama';  id='qwen3-vl-8b'; gguf='Qwen3-VL-8B-Instruct-Unredacted-MAX.Q8_0.gguf'; mmproj='Qwen3-VL-8B-Instruct-Unredacted-MAX.mmproj-q8_0.gguf'; ctx=8192; port=8096; act='vl'  }
}
$ORDER_DEF = @('iq2x','q2x','iq3x','siq2x','siq3x','c390','under','j27bx','b27bx','b27ks','vl8')
$REG = $REG_DEF; $ORDER = $ORDER_DEF
$MODELSF = Join-Path $PACKDIR 'console-tiers.json'
if (Test-Path $MODELSF) {
  try {
    $mj = @(Get-Content $MODELSF -Raw -Encoding UTF8 | ConvertFrom-Json)
    $h2 = @{}; $od = @(); $seen = @{}
    foreach ($e in $mj) {
      $k = [string]$e.key
      if (-not $k) { continue }
      if ($k.StartsWith('__')) { continue }   # 带 __ 的键是说明文字，不算条目（同 console-paths.json 的约定）
      if ($seen[$k]) { Write-Host ('  档位清单里有重复 key，已跳过后面的：' + $k); continue }
      if ('big','27b','vl' -notcontains [string]$e.act) { Write-Host ('  档位清单里 ' + $k + ' 的 act 不认识（要 big / 27b / vl），已跳过：' + $k); continue }
      if ([int]$e.need -le 0) { Write-Host ('  档位清单里 ' + $k + ' 的 need 不是正数，已跳过：' + $k); continue }
      $seen[$k] = $true
      $one = @{
        name   = $(if ($e.nameRun) { [string]$e.nameRun } else { [string]$e.name })
        need   = $(if ($e.needRun) { [int]$e.needRun } else { [int]$e.need })
        dual   = [bool]$e.dual
        engine = $(if ($e.engine) { [string]$e.engine } elseif ([string]$e.act -eq 'big') { 'strata' } else { 'llama' })
        act    = [string]$e.act
      }
      if ($e.tier)   { $one.tier   = [string]$e.tier }
      if ($e.id)     { $one.id     = [string]$e.id }
      if ($e.gguf)   { $one.gguf   = [string]$e.gguf }
      if ($e.mmproj) { $one.mmproj = [string]$e.mmproj }
      if ($e.ctx)    { $one.ctx    = [int]$e.ctx }
      if ($e.port)   { $one.port   = [int]$e.port }
      $h2[$k] = $one; $od += $k
    }
    if ($h2.Count -gt 0) { $REG = $h2; $ORDER = $od; Write-Host ('  档位清单读自 console-tiers.json（' + $h2.Count + ' 个）') }
    else { Write-Host '  档位清单 console-tiers.json 里没有有效条目，本次改用内置表' }
  } catch { Write-Host ('  档位清单 console-tiers.json 读不了（多半是 JSON 写法不对：Windows 路径的反斜杠要写两个）：' + $_.Exception.Message + ' —— 本次改用内置表') }
}

# ---------- [2026-10-23 v30] 本机扫描清单：与界面读同一份 console-tiers.scanned.json，否则列了却起不来 ----------
$scanf = Join-Path $PACKDIR 'console-tiers.scanned.json'
if (Test-Path $scanf) {
  try {
    $sj = Get-Content $scanf -Raw -Encoding UTF8 | ConvertFrom-Json
    $addN = 0
    foreach ($e in @($sj.entries)) {
      $k = [string]$e.key
      if (-not $k) { continue }
      if ($REG[$k]) { continue }                                          # 内置/手写条目优先，不覆盖
      if ('big','27b','vl' -notcontains [string]$e.act) { continue }
      if ([int]$e.need -le 0) { continue }
      $one = @{
        name   = $(if ($e.nameRun) { [string]$e.nameRun } else { [string]$e.name })
        need   = $(if ($e.needRun) { [int]$e.needRun } else { [int]$e.need })
        dual   = [bool]$e.dual
        engine = $(if ($e.engine) { [string]$e.engine } elseif ([string]$e.act -eq 'big') { 'strata' } else { 'llama' })
        act    = [string]$e.act
      }
      if ($e.tier)   { $one.tier   = [string]$e.tier }
      if ($e.id)     { $one.id     = [string]$e.id }
      if ($e.gguf)   { $one.gguf   = [string]$e.gguf }
      if ($e.mmproj) { $one.mmproj = [string]$e.mmproj }
      if ($e.ctx)    { $one.ctx    = [int]$e.ctx }
      if ($e.port)   { $one.port   = [int]$e.port }
      $REG[$k] = $one; $ORDER += $k; $addN++
    }
    if ($addN -gt 0) { Write-Host ('  本机扫描清单补入 ' + $addN + ' 个模型（共 ' + $ORDER.Count + ' 条）') }
  } catch { Write-Host ('  本机扫描清单读不了（删掉 console-tiers.scanned.json 会自动重扫）：' + $_.Exception.Message) }
}

# ---------- 原子工具 ----------
# [2026-10-22 v27] 视觉模型不再写死 vl8/8096：从登记表里找 act=vl 的那条；没给 port 就用 8096
function VlKey { foreach ($k in $ORDER) { if ($REG[$k].act -eq 'vl') { return $k } } return '' }
function VlPort([string]$k) { if ($k -and $REG[$k].port) { return [int]$REG[$k].port } return 8096 }
# 27B 路由端口 8090 是 OpenClaw 注册死的，不能换；视觉端口跟着清单走
function LlamaPorts { $a = @(8090); foreach ($k in $ORDER) { if ($REG[$k].act -eq 'vl') { $a += VlPort $k } }; return $a }

function Up([int]$port) { return (@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count -gt 0) }
function PortPid([int]$port) {
  $c = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($c.Count -eq 0) { return $null }
  return $c[0].OwningProcess
}
# [2026-10-23 v30] 大块头端口不写死 8080（官方 Strata 默认 8095）；配置 BIGPORT 优先，否则探 /health
if (-not $BIGPORT) { $BIGPORT = 8080 }
$global:BIGPORT = [int]$BIGPORT
function BigPortProbe {
  $cands = @($global:BIGPORT, 8080, 8095, 8081, 8082, 8100) | Select-Object -Unique
  foreach ($p in $cands) {
    if (-not (Up $p)) { continue }
    try {
      $hv = Invoke-WebRequest ('http://127.0.0.1:' + $p + '/health') -TimeoutSec 3 -UseBasicParsing | ConvertFrom-Json
      if ($hv -and $hv.service -eq 'strata') { $global:BIGPORT = [int]$p; return }
    } catch { }
  }
}
BigPortProbe
function FreeMiB([int]$idx) {
  $rows = @(& nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits 2>$null)
  foreach ($r in $rows) {
    $p = ($r -split ',')
    if ([int]$p[0] -eq $idx) { return [int]$p[1] }
  }
  return -1
}
function LoadState() {
  if (-not (Test-Path $STATEF)) { return @{} }
  try {
    $j = Get-Content $STATEF -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($j -is [System.Collections.Hashtable]) { return $j }
    $h = @{}
    foreach ($p in @($j.PSObject.Properties)) { $h[[string]$p.Name] = $p.Value }
    return $h
  } catch { return @{} }
}
function SaveState($st) {
  try { [IO.File]::WriteAllText($STATEF, ($st | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false))) } catch { Write-Host ('  状态文件写失败: ' + $_.Exception.Message) }
}
function KillPid($procId) {
  if (-not $procId) { return }
  Write-Host ('  杀 PID=' + $procId + '（含子进程）')
  & taskkill /PID $procId /T /F 2>&1 | Out-Null
  Start-Sleep -Seconds 2
}
function KillPort([int]$port) {
  if ($DryRun) { Write-Host ('  [DryRun] 会杀 :' + $port); return }
  $p = PortPid $port
  if (-not $p) { Write-Host ('  :' + $port + ' 没有在跑，无需停'); return }
  KillPid $p
}

# ---------- 大块头（strata） ----------
$KEEP_PAT   = 'strata-router-' + 'keep'
$START_PAT  = 'strata-start-'  + 'all'
$ROUTER_PAT = 'strata-router'  + '\.py'
$SERVE_PAT  = 'Strata\\serve\\server\.py'
$TIER_PORTS = @(8091,8092,8093,8094,8095)

function Scan-Strata {
  @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -eq 'strata.exe' -or
      ($_.Name -eq 'python.exe' -and ($_.CommandLine -match $ROUTER_PAT -or $_.CommandLine -match $SERVE_PAT)) -or
      (($_.Name -eq 'pwsh.exe' -or $_.Name -eq 'powershell.exe') -and
       ($_.CommandLine -match $KEEP_PAT -or $_.CommandLine -match $START_PAT) -and
       $_.ProcessId -ne $PID)
    })
}
function TierFromModel([string]$m) {
  # [2026-10-23 v30] 与界面同一套：把引擎报的模型名对回清单里的档位名；对不上就原样返回
  if (-not $m) { return '' }
  $mm = ([string]$m).ToLower()
  $tiers = @()
  foreach ($k in $ORDER) {
    if ($REG[$k].act -ne 'big') { continue }
    $t = $(if ($REG[$k].tier) { [string]$REG[$k].tier } else { [string]$k })
    $t = $t.ToLower()
    if ($t -and ($tiers -notcontains $t)) { $tiers += $t }
  }
  foreach ($t in $tiers) { if ($mm -eq $t -or $mm.EndsWith('-' + $t)) { return $t } }
  foreach ($t in ($tiers | Sort-Object { $_.Length } -Descending)) { if ($mm.Contains($t)) { return $t } }
  return $m
}
function StrataStatus {
  # [2026-10-23 v30] /__status 是自建路由私有接口，官方 Strata 没有 → 别人机器上恒为 null；问不到改问官方 /health。
  try { return (Invoke-WebRequest ('http://127.0.0.1:' + $global:BIGPORT + '/__status') -TimeoutSec 6 -UseBasicParsing | ConvertFrom-Json) } catch { }
  try {
    $hv = Invoke-WebRequest ('http://127.0.0.1:' + $global:BIGPORT + '/health') -TimeoutSec 6 -UseBasicParsing | ConvertFrom-Json
    if ($hv -and $hv.model) {
      $ld = $true
      if ($hv.PSObject.Properties['loaded']) { $ld = [bool]$hv.loaded }
      if (-not $ld) { return $null }
      $pp = $null
      try { $pp = PortPid $global:BIGPORT } catch { }
      return [pscustomobject]@{ current = (TierFromModel ([string]$hv.model)); model = [string]$hv.model; pid = $pp; official = $true }
    }
  } catch { return $null }
  return $null
}
function ToolFile([string]$name) {
  # [2026-10-20 v22] 在工具目录找脚本；找不到就在常见位置兜底（换机器不至于直接瘫）
  $c = @( (Join-Path $TOOLDIR $name), (Join-Path $PACKDIR $name), (Join-Path (Split-Path $TIER_DIR -Parent) $name), (Join-Path 'D:\06.AItools' $name) )
  foreach ($p in $c) { if (Test-Path $p) { return $p } }
  return ''
}
function Stop-StrataOnly {
  if ($DryRun) {
    $all = Scan-Strata
    Write-Host ('  [DryRun] 将停 ' + $all.Count + ' 个进程（本轮不动任何进程）：')
    foreach ($k in $all) { Write-Host ('    ' + $k.Name + ' PID=' + $k.ProcessId) }
    return $true
  }
  # 先请引擎优雅卸载（让正在生成的回答跑完），再杀
  if (Up $global:BIGPORT) {
    try { Invoke-WebRequest ('http://127.0.0.1:' + $global:BIGPORT + '/unload?wait=120') -Method POST -ContentType 'application/json' -Body '{}' -TimeoutSec 150 -UseBasicParsing | Out-Null; Write-Host '  [腾卡] 已优雅卸载' } catch { Write-Host '  [腾卡] 优雅卸载不成，直接硬杀' }
  }
  # 顺序很关键：先杀守护/拉起 → 再杀 router → 再杀后端 → 最后杀引擎
  for ($round = 1; $round -le 5; $round++) {
    $all = Scan-Strata
    if ($all.Count -eq 0) { Write-Host ('  [大块头] 已全停（第 ' + $round + ' 轮扫描已空）'); break }
    $guard  = @($all | Where-Object { $_.Name -eq 'pwsh.exe' -or $_.Name -eq 'powershell.exe' })
    $router = @($all | Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match $ROUTER_PAT })
    $serve  = @($all | Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match $SERVE_PAT })
    $engine = @($all | Where-Object { $_.Name -eq 'strata.exe' })
    foreach ($k in ($guard + $router + $serve + $engine)) {
      Write-Host ('   停 ' + $k.Name + ' PID=' + $k.ProcessId)
      & taskkill /PID $k.ProcessId /T /F 2>&1 | Out-Null
    }
    Start-Sleep -Seconds 4
  }
  Start-Sleep -Seconds 6
  $rev = @(Scan-Strata)
  if ($rev.Count -gt 0) {
    Write-Host ('  还有活的/复活的，补杀一轮：' + (($rev | ForEach-Object { $_.Name + '#' + $_.ProcessId }) -join ', '))
    foreach ($v in $rev) { & taskkill /PID $v.ProcessId /T /F 2>&1 | Out-Null }
    Start-Sleep -Seconds 8
    if (@(Scan-Strata).Count -gt 0) { Write-Host '  ✗ 大块头仍杀不干净，看 strata-router*.log' -ForegroundColor Red; return $false }
  }
  if (Up $global:BIGPORT) { Write-Host ('  ✗ :' + $global:BIGPORT + ' 仍监听（router 未死）') -ForegroundColor Red; return $false }
  Write-Host '  [大块头] 已停，显存释放' -ForegroundColor Green
  return $true
}
function Ensure-StrataRouter {
  if (Up $global:BIGPORT) { return $true }
  Write-Host '  拉起大块头 router + keeper ...'
  if ($DryRun) { Write-Host '  [DryRun] 会跑 strata-start-all-hidden.vbs'; return $true }
  # [2026-10-20 v22] 原来写 Join-Path $BASE（= 控制台包目录），但启动 vbs 在工具目录 → 永远找不到，
  #   于是报「8080 没起来」+「switch 异常：由于目标计算机积极拒绝」，用户只能去用 bat 启动。
  $vbs = ToolFile 'strata-start-all-hidden.vbs'
  if (-not $vbs) {
    # [2026-10-23 v30] 没有自建路由 = 官方 Strata 机器。这里先不起：档位由后面的 Switch-Tier 定，
    #   在这里起等于不知道要哪个档（会随机挑一个配置文件）。
    Write-Host '  没找到自建路由的启动脚本 → 这台是官方 Strata，起哪个档交给换档那步办'
    return $true
  }
  try { wscript $vbs } catch { Write-Host ('   启动失败: ' + $_.Exception.Message) -ForegroundColor Red; return $false }
  for ($i = 0; $i -lt 150 -and -not (Up $global:BIGPORT); $i++) { Start-Sleep -Milliseconds 500 }
  if (-not (Up $global:BIGPORT)) { Write-Host ('   ✗ :' + $global:BIGPORT + ' 没起来（看 ' + $TOOLDIR + '\strata-router*.log）') -ForegroundColor Red; return $false }
  Write-Host ('   :' + $global:BIGPORT + ' 已就绪')
  return $true
}
# [2026-10-23 v30] 没有自建路由的机器（官方 Strata）：按官方方式起 —— 读官方目录里的 run-<档>.bat，
#   或 python serve\server.py --engine strata --config <档位json> --port <端口>。
function OfficialStart([string]$tier) {
  $bat = ''
  try { $bat = @(Get-ChildItem -LiteralPath $TIER_DIR -Filter ('run-' + $tier + '.bat') -File -ErrorAction SilentlyContinue)[0].FullName } catch { }
  if ($bat) {
    Write-Host ('  官方方式：跑 ' + (Split-Path $bat -Leaf))
    if ($DryRun) { Write-Host '  [DryRun] 会隐藏运行这个 bat'; return $true }
    try { Start-Process -FilePath $bat -WorkingDirectory $TIER_DIR -WindowStyle Hidden } catch { Write-Host ('   启动失败: ' + $_.Exception.Message) -ForegroundColor Red; return $false }
  } else {
    $py = @( (Join-Path $TIER_DIR '.venv\Scripts\python.exe'), 'python' ) | Where-Object { if ($_.Contains('')) { Test-Path $_ } else { Get-Command $_ -CommandType Application -ErrorAction SilentlyContinue } } | Select-Object -First 1
    $srv = Join-Path $TIER_DIR 'serve\server.py'
    $cfgs = @()
    try { $cfgs = @(Get-ChildItem -LiteralPath $TIER_DIR -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ('*' + $tier + '*') }) } catch { }
    if (-not $py -or -not (Test-Path $srv) -or $cfgs.Count -eq 0) {
      Write-Host ('   ✗ 这台机器没有本助手的自建路由，也没找到官方起法需要的东西（要 ' + $TIER_DIR + '\serve\server.py + 档位 ' + $tier + ' 的 json + python）')
      Write-Host '     改 console-paths.json 的 TIER_DIR 指向 Strata 目录，或先用 Strata 自己的方式把模型起起来'
      return $false
    }
    $cfg = $cfgs[0].FullName
    Write-Host ('  官方方式：server.py --config ' + (Split-Path $cfg -Leaf) + ' --port ' + $global:BIGPORT)
    if ($DryRun) { Write-Host ('  [DryRun] 会起 ' + $py + ' ' + $srv + ' --engine strata --config ' + $cfg + ' --port ' + $global:BIGPORT); return $true }
    $lg = Join-Path $PACKDIR ('logs\official-' + $tier + '-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.log')
    try { if (-not (Test-Path (Split-Path $lg -Parent))) { New-Item -ItemType Directory -Force -Path (Split-Path $lg -Parent) | Out-Null } } catch { }
    try {
      $sa = @($srv, '--engine', 'strata', '--config', $cfg, '--port', [string]$global:BIGPORT)
      Start-Process -FilePath $py -ArgumentList $sa -WorkingDirectory $TIER_DIR -WindowStyle Hidden -RedirectStandardOutput $lg -RedirectStandardError ($lg + '.err')
    } catch { Write-Host ('   启动失败: ' + $_.Exception.Message) -ForegroundColor Red; return $false }
  }
  for ($i = 0; $i -lt 240 -and -not (Up $global:BIGPORT); $i++) { Start-Sleep -Milliseconds 500 }
  if (-not (Up $global:BIGPORT)) { Write-Host ('   ✗ :' + $global:BIGPORT + ' 没起来（看 ' + $TIER_DIR + ' 里的日志）') -ForegroundColor Red; return $false }
  Write-Host ('   :' + $global:BIGPORT + ' 已就绪')
  return $true
}
function Switch-Tier([string]$tier) {
  Write-Host ('  切到 ' + $tier + ' 并上卡（约 40–90 秒，请稍候）...')
  if ($DryRun) { Write-Host '  [DryRun] 会 GET /__switch?tier=' + $tier; return $true }
  # [2026-10-23 v30] 官方 Strata 没有 /__switch：换档 = 按那个档位的配置重新起（先卸再起）
  #   端口压根没在听时也别去 GET /__switch（会 404 再白 ping 300 秒），直接按官方方式起
  if (-not (Up $global:BIGPORT)) { return (OfficialStart $tier) }
  $s0 = $null
  try { $s0 = StrataStatus } catch { }
  if ($s0 -and $s0.official) {
    if ([string]$s0.current -eq [string]$tier) { Write-Host ('   ✓ 已在跑 ' + $tier + '，不用切'); return $true }
    try { Invoke-WebRequest ('http://127.0.0.1:' + $global:BIGPORT + '/unload?wait=120') -Method POST -ContentType 'application/json' -Body '{}' -TimeoutSec 150 -UseBasicParsing | Out-Null } catch { }
    $pp = $null
    try { $pp = PortPid $global:BIGPORT } catch { }
    if ($pp) { & taskkill /PID $pp /T /F 2>&1 | Out-Null; Start-Sleep -Seconds 4 }
    return (OfficialStart $tier)
  }
  try { Invoke-WebRequest ('http://127.0.0.1:' + $global:BIGPORT + '/__switch?tier=' + $tier) -TimeoutSec 600 -UseBasicParsing | Out-Null } catch { Write-Host ('   switch 异常: ' + $_.Exception.Message) -ForegroundColor Yellow }
  for ($i = 0; $i -lt 300; $i++) {
    try {
      $b = '{"model":"' + $tier + '","messages":[{"role":"user","content":"ping"}],"max_tokens":1}'
      $r = Invoke-WebRequest ('http://127.0.0.1:' + $global:BIGPORT + '/v1/chat/completions') -Method POST -ContentType 'application/json' -Body $b -TimeoutSec 25 -UseBasicParsing
      if ($r.StatusCode -eq 200) { Write-Host ('   ✓ ' + $tier + ' 已上卡，可回话'); return $true }
    } catch {}
    Start-Sleep -Seconds 1
  }
  Write-Host ('   ⚠ 300 秒内没就绪，看 strata-backend-' + $tier + '.log') -ForegroundColor Yellow
  return $false
}

# ---------- llama 实例（视觉 / 嵌入，独立端口） ----------
function Start-LlamaOn([string]$key, [int]$gpuIdx) {
  $m = $REG[$key]
  $port = [int]$m.port
  if (Up $port) { Write-Host ('  :' + $port + ' 已在跑，先停旧的'); KillPort $port }
  if ($DryRun) { Write-Host ('  [DryRun] 起 llama-server :' + $port + ' 模型 ' + $m.gguf + ' 绑卡 ' + $gpuIdx); return $true }
  if (-not (Test-Path $LLAMA_EXE)) { Write-Host '  ✗ 找不到 llama-server.exe' -ForegroundColor Red; return $false }
  $a = @('-m', (Join-Path $MODELS $m.gguf), '-ngl', '99', '-c', [string]$m.ctx, '--host', '127.0.0.1', '--port', [string]$port,
         '-ctk', 'q4_0', '-ctv', 'q4_0', '--temp', '0.6', '--seed', '42')
  if ($m.mmproj) { $a += @('--mm', (Join-Path $MODELS $m.mmproj), '--image-min-tokens', '1024') }
  $env:CUDA_VISIBLE_DEVICES = [string]$gpuIdx
  Start-Process -FilePath $LLAMA_EXE -ArgumentList $a -WorkingDirectory (Split-Path $LLAMA_EXE) -WindowStyle Hidden `
    -RedirectStandardOutput ($BASE + '\llama-console-' + $port + '.out.log') `
    -RedirectStandardError ($BASE + '\llama-console-' + $port + '.err.log') | Out-Null
  for ($i = 0; $i -lt 90 -and -not (Up $port); $i++) { Start-Sleep -Seconds 1 }
  if (Up $port) {
    Write-Host ('  ✓ :' + $port + ' 已起（' + $m.name + '，卡 ' + $gpuIdx + '）') -ForegroundColor Green
    $st = LoadState; $st[[string]$port] = @{ key = $key; gpu = $gpuIdx; pid = PortPid $port }; SaveState $st
    return $true
  }
  Write-Host ('  ✗ :' + $port + ' 没起来，看 llama-console-' + $port + '.err.log') -ForegroundColor Red
  return $false
}

# ---------- 27B（走 :8090 路由，OpenClaw 已注册，不能换端口） ----------
function Start-27b([string]$key, [int]$gpuIdx) {
  $m = $REG[$key]
  $st = LoadState
  $cur = $st['8090']
  $needRestart = $false
  if (Up 8090) {
    if ($cur -and [int]$cur.gpu -ne $gpuIdx) { $needRestart = $true }
  } else {
    $needRestart = $true
  }
  if ($needRestart) {
    Write-Host ('  停 :8090 路由（原卡 ' + $(if ($cur) { $cur.gpu } else { '未知' }) + ' → 新卡 ' + $gpuIdx + '）')
    KillPort 8090
    if ($DryRun) { Write-Host '  [DryRun] 会跑 llama-router-start.ps1 -Gpu ' + $gpuIdx; return $true }
    # [2026-10-20 v22] 同样问题：脚本在工具目录，不在包内
    $rs = ToolFile 'llama-router-start.ps1'
    if (-not $rs) { Write-Host '  ✗ 找不到 llama-router-start.ps1（工具目录不对）' -ForegroundColor Red; return $false }
    & $rs -Port 8090 -Gpu $gpuIdx
    if (-not (Up 8090)) { Write-Host '  ✗ 8090 没起来，看 llama-router.err.log' -ForegroundColor Red; return $false }
  }
  if ($DryRun) { Write-Host ('  [DryRun] 预加载 ' + $m.id); return $true }
  Write-Host ('  预加载 ' + $m.name + ' 上卡（首次约 15–60 秒）...')
  try {
    $body = @{ model = $m.id; messages = @(@{ role = 'user'; content = 'ping' }); max_tokens = 8; chat_template_kwargs = @{ enable_thinking = $false } } | ConvertTo-Json -Depth 6 -Compress
    $r = Invoke-WebRequest 'http://127.0.0.1:8090/v1/chat/completions' -Method POST -ContentType 'application/json' -Body $body -TimeoutSec 240 -UseBasicParsing
    if ($r.StatusCode -eq 200) { Write-Host ('  ✓ ' + $m.name + ' 已上卡（:8090，卡 ' + $gpuIdx + '）') -ForegroundColor Green }
  } catch { Write-Host ('  ⚠ 预加载失败: ' + $_.Exception.Message) -ForegroundColor Yellow }
  $st = LoadState; $st['8090'] = @{ key = $key; gpu = $gpuIdx; pid = PortPid 8090 }; SaveState $st
  return $true
}

# ---------- 安全垫 ----------
# [2026-10-19 v13] 读回工具：从档位 JSON 里取出实际写入的两个值（写完必须读回验证，不盲信写入成功）
function Read-ReserveValues([string]$path) {
  $t = Get-Content $path -Raw
  $vf = $null; $vl = $null
  if ($t -match '--vram-reserve-mib",\s*"(\d+)"') { $vf = [int]$Matches[1] }
  if ($t -match '--vram-reserve-later-mib",\s*"(\d+)"') { $vl = [int]$Matches[1] }
  return @{ first = $vf; later = $vl }
}

function Write-Reserve([int]$f, [int]$l) {
  $bak = Join-Path $TIER_DIR '.reserve-bak'
  if (-not (Test-Path $bak)) { New-Item -ItemType Directory -Force -Path $bak | Out-Null }
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
  $changed = @()
  foreach ($file in (Get-ChildItem $TIER_DIR -Filter 'strata-*.json')) {
    Copy-Item $file.FullName (Join-Path $bak ($file.Name + '.' + $stamp)) -Force
    $t = Get-Content $file.FullName -Raw
    $t2 = $t -replace '--vram-reserve-mib",\s*"\d+"', ('--vram-reserve-mib", "' + $f + '"')
    $t2 = $t2 -replace '--vram-reserve-later-mib",\s*"\d+"', ('--vram-reserve-later-mib", "' + $l + '"')
    if ($t2 -ne $t) { Set-Content -Path $file.FullName -Value $t2 -Encoding UTF8; $changed += $file.Name }
  }
  Write-Host ('  已写入 ' + $changed.Count + ' 个档位文件（备份 .reserve-bak\' + $stamp + '）')
  # 读回确认：重新读每个文件，看实际值是不是等于要写的值
  $bad = @()
  foreach ($file in (Get-ChildItem $TIER_DIR -Filter 'strata-*.json')) {
    $v = Read-ReserveValues $file.FullName
    if ($v.first -ne $f -or $v.later -ne $l) { $bad += ($file.Name + ' ' + $v.first + '/' + $v.later) }
  }
  if ($bad.Count -eq 0) {
    Write-Host ('  读回确认：首卡 ' + $f + ' / 其它卡 ' + $l + '（全部档位文件一致）')
  } else {
    Write-Host ('  读回不符！' + ($bad -join ' | '))
  }
  return $changed
}

# [2026-10-19 v13] 回滚：把 .reserve-bak 里最新一批备份拷回档位目录
function Restore-ReserveLatest {
  $bak = Join-Path $TIER_DIR '.reserve-bak'
  $all = @()
  if (Test-Path $bak) { $all = @(Get-ChildItem $bak -Filter 'strata-*.json.*' | Sort-Object LastWriteTime) }
  if ($all.Count -eq 0) { Write-Host '  没有备份（.reserve-bak 是空的），不动任何文件'; return @() }
  $stamp = ($all[-1].Name -replace '.*(\d{8}-\d{6})$', '$1')
  $group = @($all | Where-Object { $_.Name.EndsWith($stamp) })
  foreach ($b in $group) {
    $orig = $b.Name -replace '\.\d{8}-\d{6}$', ''
    Copy-Item $b.FullName (Join-Path $TIER_DIR $orig) -Force
    Write-Host ('  拷回 ' + $orig + '（来自 ' + $b.Name + '）')
  }
  Write-Host ('  回滚批次：' + $stamp + '，共 ' + $group.Count + ' 个文件')
  return $group
}

# ---------- 状态 ----------
function Show-State {
  Write-Host '=== 实时状态 ==='
  $s = StrataStatus
  if ($s) { Write-Host ('  大块头 :' + $global:BIGPORT + '  当前档 ' + $s.current + '  pid ' + $s.pid) } else { Write-Host ('  大块头 :' + $global:BIGPORT + '  停') }
  foreach ($port in (LlamaPorts)) {   # [2026-10-22 v27] 视觉端口跟着清单走
    $ps = [string]$port
    if (Up $port) { Write-Host ('  :' + $ps + ' 在跑  pid ' + (PortPid $port)) } else { Write-Host ('  :' + $ps + ' 停') }
  }
  $rows = @(& nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits 2>$null)
  foreach ($r in $rows) { Write-Host ('  卡 ' + $r) }
  Write-Host ('  网关 :18789 ' + $(if (Up 18789) { '在跑 pid ' + (PortPid 18789) } else { '停' }))
}

function Restart-StrataImpl {
  $s = StrataStatus
  $tier = 'iq2x'
  if ($s -and $s.current) { $tier = $s.current }
  foreach ($p in $TIER_PORTS) { if (Up $p) { KillPort $p } }
  Start-Sleep -Seconds 2
  [void](Ensure-StrataRouter)
  [void](Switch-Tier $tier)
}

# ---------- 动作分发 ----------
Write-Host ('===== 执行器 ' + $Action + '  (DryRun=' + [bool]$DryRun + ') =====')

switch ($Action) {
  'status' { Show-State }
  'scan' {
    $all = Scan-Strata
    Write-Host ('  大块头相关进程共 ' + $all.Count + ' 个（只列，不动）：')
    foreach ($k in $all) { Write-Host ('    ' + $k.Name + ' PID=' + $k.ProcessId + ' | ' + $k.CommandLine) }
    $guard  = @($all | Where-Object { $_.Name -eq 'pwsh.exe' -or $_.Name -eq 'powershell.exe' })
    $router = @($all | Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match $ROUTER_PAT })
    $serve  = @($all | Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match $SERVE_PAT })
    $engine = @($all | Where-Object { $_.Name -eq 'strata.exe' })
    Write-Host ('  停的顺序会是：守护 ' + $guard.Count + ' → router ' + $router.Count + ' → 后端 ' + $serve.Count + ' → 引擎 ' + $engine.Count)
    Write-Host ('  :' + $global:BIGPORT + ' 监听 = ' + (Up $global:BIGPORT) + '；8093 监听 = ' + (Up 8093))
  }

  'start-big' {
    if (-not $REG.ContainsKey($Key)) { Write-Host ('  未知档位 ' + $Key); exit 1 }
    $m = $REG[$Key]
    Write-Host ('  起大块头：' + $m.name + '（双卡合扛，需约 ' + $m.need + ' MiB）')
    Write-Host '  说明：大块头需要两卡都有余量；其它 llama 实例不冲突，但显存不够时起不来'
    [void](Ensure-StrataRouter)
    [void](Switch-Tier $m.tier)
    Show-State
  }
  'stop-big' {
    Write-Host '  停大块头（router + keeper + 后端 + strata.exe）'
    [void](Stop-StrataOnly)
    $st = LoadState
    foreach ($p in $TIER_PORTS) { if (Up $p) { KillPort $p } }
    Show-State
  }
  'restart-big' {
    $s = StrataStatus
    $tier = 'iq2x'
    if ($s -and $s.current) { $tier = $s.current }
    Write-Host ('  重启大块头（档位 ' + $tier + '）：先杀后端端口 8091-8095，再 /__switch')
    foreach ($p in $TIER_PORTS) { if (Up $p) { KillPort $p } }
    Start-Sleep -Seconds 2
    [void](Ensure-StrataRouter)
    [void](Switch-Tier $tier)
    Show-State
  }
  'start-27b' {
    if (-not $REG.ContainsKey($Key)) { Write-Host ('  未知模型 ' + $Key); exit 1 }
    Write-Host ('  起 ' + $REG[$Key].name + ' 在显卡 ' + ($Gpu + 1) + '（走 :8090 路由）')
    [void](Start-27b $Key $Gpu)
    Show-State
  }
  'stop-27b' {
    Write-Host '  停 :8090 路由（OpenClaw 的 llamacpp provider 会暂时不可用）'
    KillPort 8090
    $st = LoadState; $st.Remove('8090'); SaveState $st
    Show-State
  }
  'start-vl' {
    $vk = VlKey
    if (-not $vk) { Write-Host '  ✗ 档位清单里没有 act=vl 的条目（视觉模型）'; break }
    $vp = VlPort $vk
    Write-Host ('  起视觉模型在显卡 ' + ($Gpu + 1) + '（:' + $vp + '）')
    [void](Start-LlamaOn $vk $Gpu)
    Show-State
  }
  'stop-vl' {
    $vk = VlKey; $vp = VlPort $vk
    Write-Host ('  停视觉模型（:' + $vp + '）')
    KillPort $vp
    $st = LoadState; $st.Remove([string]$vp); SaveState $st
    Show-State
  }
  'stop-all' {
    Write-Host '  全停：大块头 + 27B 路由 + 视觉（腾空两卡）'
    [void](Stop-StrataOnly)
    foreach ($p in (LlamaPorts)) { KillPort $p }   # [2026-10-22 v27] 视觉端口跟着清单走
    Show-State
  }
  'clear-cache' {
    Write-Host '  清空大块头缓存（不重启服务、不新开会话）'
    & $PWSH -NoProfile -File $CACHECLR
  }
  'reserve' {
    Write-Host ('  写安全垫：首卡 ' + $First + ' MiB / 其它卡 ' + $Later + ' MiB')
    if ($DryRun) {
      Write-Host '  [DryRun] 会备份五个档位 JSON → 改写两个数值 → 读回确认 → 重启大块头'
      foreach ($file in (Get-ChildItem $TIER_DIR -Filter 'strata-*.json')) {
        $v = Read-ReserveValues $file.FullName
        Write-Host ('  [DryRun] 现值 ' + $file.Name + '：首卡 ' + $v.first + ' / 其它卡 ' + $v.later)
      }
      break
    }
    [void](Write-Reserve $First $Later)
    [void](Restart-StrataImpl)
  }
  'reserve-rollback' {
    # [2026-10-19 v13] 一键回滚安全垫：拷回最新一批备份 → 读回确认 → 重启大块头
    $bak = Join-Path $TIER_DIR '.reserve-bak'
    $peek = @()
    if (Test-Path $bak) { $peek = @(Get-ChildItem $bak -Filter 'strata-*.json.*' | Sort-Object LastWriteTime) }
    if ($peek.Count -eq 0) { Write-Host '  .reserve-bak 里没有备份，不动任何文件'; break }
    $stamp = ($peek[-1].Name -replace '.*(\d{8}-\d{6})$', '$1')
    $sample = $peek[-1].Name -replace '\.\d{8}-\d{6}$', ''
    $v = Read-ReserveValues (Join-Path $bak $peek[-1].Name)
    if ($DryRun) {
      Write-Host ('  [DryRun] 会把最新一批备份（' + $stamp + '，例 ' + $sample + '）拷回档位目录并重启大块头')
      Write-Host ('  [DryRun] 该备份里的值：首卡 ' + $v.first + ' / 其它卡 ' + $v.later)
      break
    }
    [void](Restore-ReserveLatest)
    # 读回确认：拷回后重新读档位目录里的文件
    $bad = @()
    foreach ($file in (Get-ChildItem $TIER_DIR -Filter 'strata-*.json')) {
      $cv = Read-ReserveValues $file.FullName
      if ($cv.first -ne $v.first -or $cv.later -ne $v.later) { $bad += ($file.Name + ' ' + $cv.first + '/' + $cv.later) }
    }
    if ($bad.Count -eq 0) {
      Write-Host ('  读回确认：回滚后首卡 ' + $v.first + ' / 其它卡 ' + $v.later + '（与备份一致）')
    } else {
      Write-Host ('  读回不符！' + ($bad -join ' | '))
    }
    [void](Restart-StrataImpl)
  }
  'gw' { Write-Host '  网关救援（优雅优先）'; & $PWSH -NoProfile -File $GWRESCUE }
  'gw-hard' { Write-Host '  网关救援（硬清理）'; & $PWSH -NoProfile -File $GWRESCUE -Hard }
  'versions' {
    # [2026-10-20 v17] 只读：读本机版本 + 官方最新 release，写 console-versions.json 供页⑤显示
    Write-Host '  读版本与官方链接（只读，需联网）'
    $raw = (& node $VERJS --out $VERF 2>&1 | Out-String).Trim()
    Write-Host ('  ' + ($raw -join [char]10))
    if (Test-Path $VERF) { Write-Host '  已写 console-versions.json' } else { Write-Host '  未写出缓存（页⑤仍显示本机版本）' }
  }
  'model-list' {
    # [2026-10-19 v17] 只读：列可换的模型（本地+云端），node 直接落盘 console-models.json 供界面下拉菜单
    Write-Host '  读可换模型清单（只读）'
    $raw = (& node $WINCJS models --json --out (Join-Path $PACKDIR 'console-models.json') 2>&1 | Out-String).Trim()
    if (-not $raw.StartsWith('[')) { Write-Host ('  读失败：' + $raw.Substring(0, [Math]::Min(160, $raw.Length))); break }
    $rows = $raw | ConvertFrom-Json
    Write-Host ('  可换模型 ' + $rows.Count + ' 个：')
    foreach ($w in $rows) { Write-Host ('    ' + $w.provider + '/' + $w.key + ' | ' + $w.name + ' | ' + $(if ($w.local) { '本地' } else { '云端' })) }
  }
  'power' {
    # [2026-10-20 v19] 修两处：①读上限的命令写错（-q 不认 --format=csv,noheader,nounits，日志里全是 ERROR）
    #   ②写功率要管理员权限：双击打开本程序时是普通权限，nvidia-smi 会报 Insufficient Permissions（exit 87 让界面去提权重试）
    if ($Watts -le 0) { Write-Host '  缺 -Watts <瓦>'; exit 1 }
    $smi = if ($Gpu -ge 0) { $Gpu } else { 0 }
    $q = (@(& nvidia-smi -i $smi --query-gpu=power.limit,power.default_limit,power.min_limit,power.max_limit --format=csv,noheader,nounits 2>&1 | Out-String)).Trim()
    if ((-not $q) -or ($q -match 'ERROR')) { Write-Host ('  读功率上限失败：' + $q); exit 1 }
    $pf = @($q -split ',' | ForEach-Object { [double]([string]$_).Trim() })
    $cur = [int]$pf[0]; $def = [int]$pf[1]; $mn = [int]$pf[2]; $mx = [int]$pf[3]
    Write-Host ('  显卡' + ($smi + 1) + ' 现上限 ' + $cur + ' W（默认 ' + $def + '，可设 ' + $mn + '-' + $mx + '，只改这张卡）')
    if ($Watts -lt $mn -or $Watts -gt $mx) { Write-Host ('  输入 ' + $Watts + ' W 超出可设范围 ' + $mn + '-' + $mx + '，未改'); exit 1 }
    if ($DryRun) { Write-Host ('  [DryRun] 会把显卡' + ($smi + 1) + ' 上限设为 ' + $Watts + ' W'); break }
    $out = (@(& nvidia-smi -i $smi --power-limit=$Watts 2>&1 | Out-String)).Trim()
    Write-Host ('  ' + $out)
    if ($out -match 'Insufficient Permissions') {
      Write-Host '  → 被拒：写功率需要管理员权限（双击打开本程序时是普通权限）。'
      Write-Host '  → 界面会问「要不要用管理员身份重试」，点了会弹一次 UAC 确认。'
      exit 87
    }
    $back = (@(& nvidia-smi -i $smi --query-gpu=power.limit --format=csv,noheader,nounits 2>&1 | Out-String)).Trim()
    Write-Host ('  读回确认：显卡' + ($smi + 1) + ' 现上限 ' + $back + ' W')
  }
  'cron-list' {
    # [2026-10-19 v16] 只读：定时任务「定义」清单（中文名 + 何时跑 + 用哪个模型）+ 心跳/压缩模型
    Write-Host '  读定时任务定义（只读，不改任何任务）'
    $raw = (& node $CRONJS list --out $CRONF --hbfile $HBF 2>&1 | Out-String).Trim()
    if (-not $raw.StartsWith('[')) { Write-Host ('  读失败：' + $raw.Substring(0, [Math]::Min(160, $raw.Length))); break }
    $rows = $raw | ConvertFrom-Json
    Write-Host ('  定时任务 ' + $rows.Count + ' 个：')
    foreach ($w in $rows) {
      $st = if ($w.enabled) { '在跑' } else { '停用' }
      Write-Host ('    ' + $w.name + ' | ' + $w.when + ' | ' + $w.kindText + ' | ' + ($w.model || '纯脚本·不用模型') + ' | ' + $st)
    }
    if (Test-Path $HBF) {
      try {
        $hb = Get-Content $HBF -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host ('  心跳/压缩模型：' + $hb.heartbeat + ' / ' + $hb.compaction + '（openclaw.json，本动作不改）')
      } catch {}
    }
  }
  'cron-set' {
    # [2026-10-19 v16] 换「定时任务定义」里的模型：只改「要模型」的任务；纯脚本任务不调用模型，不动；
    #   心跳与压缩在 openclaw.json（改需网关重启），本动作不碰 —— 符合用户 2026-10-16 的决定
    if (-not $Key) { Write-Host '  缺目标模型'; exit 1 }
    if ($DryRun) {
      Write-Host ('  [DryRun] 会把「要模型」的定时任务换成 ' + $Key)
      & node $CRONJS set --model $Key --dry 2>&1
      break
    }
    Write-Host ('  定时任务模型 → ' + $Key)
    $r = (& node $CRONJS set --model $Key 2>&1 | Out-String)
    Write-Host $r.Trim()
    if ($ChatToo) {
      Write-Host '  连对话窗口一起换'
      & node $WINCJS set --model $Key --scope chat 2>&1
    }
  }
  'cron-set-one' {   # [2026-10-20 v18] 只改一个定时任务的模型（用户：批量要保留，个别也要能改）
    if (-not $Key) { Write-Host '  缺目标模型'; exit 1 }
    if (-not $JobName) { Write-Host '  缺 -JobName <任务名>'; exit 1 }
    if ($DryRun) {
      Write-Host ('  [DryRun] 只把「' + $JobName + '」换成 ' + $Key)
      & node $CRONJS set --model $Key --name $JobName --dry 2>&1
      break
    }
    Write-Host ('  只改定时任务「' + $JobName + '」 → ' + $Key)
    $r1 = (& node $CRONJS set --model $Key --name $JobName 2>&1 | Out-String)
    Write-Host $r1.Trim()
    # 改完读回任务清单，界面才有最新值
    [void](& node $CRONJS list --out $CRONF --hbfile $HBF 2>&1 | Out-String)
    Write-Host '  已读回 console-crons.json'
  }
  'hb-set' {   # [2026-10-20 v18] 改心跳与压缩模型（写 openclaw.json，先自动备份，改完需重启网关）
    if (-not $Key) { Write-Host '  缺目标模型'; exit 1 }
    if ($DryRun) { Write-Host ('  [DryRun] 会把心跳与压缩改成 ' + $Key + '（需重启网关才生效）'); & node $HBCJS set --model $Key --dry 2>&1; break }
    $r2 = (& node $HBCJS set --model $Key 2>&1 | Out-String)
    Write-Host $r2.Trim()
    Write-Host '  提醒：这两项属「需重启网关」类，重启后才生效（重启前先确认）'
  }
  'detect' {
    # [2026-10-20 v22] 本机环境自检（只报告，不改配置）
    Write-Host '  本机环境自检（只读，不改任何配置）'
    & node $SELFJS --out $SELFF 2>&1
  }
  'detect-write' {
    # [2026-10-20 v22] 自检 + 把「当前值在本机不存在」的路径用探测到的真值写回 console-paths.json（自动备份 .bak-detect-*）
    Write-Host '  本机环境自检并修正路径（会先备份 console-paths.json）'
    & node $SELFJS --out $SELFF --write 2>&1
  }
  'calib' {
    # [2026-10-20 v22] 显存实测自动校准：当前在跑哪档，就量它实际占多少显存（两卡求和），输出「tier,占用MiB」供界面写门槛
    Write-Host '  显存实测（只读，不动服务）'
    $s = StrataStatus
    if (-not $s -or -not $s.current) { Write-Host '  大块头没在跑，量不到（起一档再跑）'; break }
    $sum = 0
    foreach ($r in @(& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null)) {
      $v = 0
      if ([int]::TryParse($r.Trim(), [ref]$v)) { $sum += $v }
    }
    if ($sum -le 0) { Write-Host '  读不到显存占用'; break }
    Write-Host ('  当前档 ' + $s.current + ' 实测占用 ' + $sum + ' MiB（两卡合计）')
    Write-Host ([string]$s.current + ',' + [string]$sum)
  }
  'win-list' {
    # [2026-10-19 v14] 只读：读各对话窗口当前用哪个模型，写缓存文件供界面填列表
    Write-Host '  读各窗口当前模型（只读，不动任何窗口）'
    # 让 node 自己落盘（--out）：PowerShell 重定向/Set-Content 会把 UTF-8 二次编码，中文窗口名会变乱码
    $raw = (& node $WINCJS list --json --out $WINF 2>&1 | Out-String).Trim()
    if (-not $raw.StartsWith('[')) { Write-Host ('  读失败：' + $raw.Substring(0, [Math]::Min(120, $raw.Length))); break }
    [void](Set-Content -Path $WINF -Value $raw -Encoding UTF8)
    $rows = $raw | ConvertFrom-Json
    Write-Host ('  对话窗口 ' + $rows.Count + ' 个：')
    foreach ($w in $rows) {
      $run = if ($w.running) { ' [正在跑]' } else { '' }
      Write-Host ('    ' + $w.name + ' (' + $w.where + ')' + $run + ' → ' + $w.model + '  已用上下文 ' + $w.used)
    }
  }
  'win-set' {
    # [2026-10-19 v14] 一键换所有对话窗口的模型；不重启服务、不中断正在跑的回答
    if (-not $Key) { Write-Host '  缺目标模型'; exit 1 }
    if ($DryRun) {
      # [2026-10-19 v14] DryRun 也要把 -Compact / -Sys 传下去，不然「勾了但走查里看不到」会误导
      Write-Host ('  [DryRun] 会把所有对话窗口换成 ' + $Key + '（一个窗口也不动）')
      $dargs = @($WINCJS, 'set', '--model', $Key, '--dry')
      if ($Compact) { $dargs += '--compact' }
      if ($Sys) { $dargs += '--sys' }
      & node @dargs 2>&1
      break
    }
    Write-Host ('  换所有对话窗口 → ' + $Key + $(if ($Compact) { '，并压缩上下文' } else { '' }))
    $args = @($WINCJS, 'set', '--model', $Key)
    if ($Compact) { $args += '--compact' }
    if ($Sys) { $args += '--sys' }
    & node @args 2>&1
    # 读回确认：重新读一次窗口清单（node 直接落盘，避开编码二次转换）
    $raw = (& node $WINCJS list --json --out $WINF 2>&1 | Out-String).Trim()
    if ($raw.StartsWith('[')) {
      [void](Set-Content -Path $WINF -Value $raw -Encoding UTF8)
      $rows = $raw | ConvertFrom-Json
      $want = ($Key -split '/')[1]
      $n = 0
      foreach ($w in $rows) { if ($w.model -eq $Key -or $w.model -eq $want) { $n++ } }
      Write-Host ('  读回确认：' + $n + ' / ' + $rows.Count + ' 个对话窗口已生效为 ' + $Key)
    }
  }
  default { Write-Host ('  没看懂动作 ' + $Action); exit 1 }
}

