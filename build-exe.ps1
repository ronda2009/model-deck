# build-exe.ps1 — 构建 model-console.exe（Windows + Go）
#
# 需要：Go、goversioninfo（go install github.com/tc-hib/go-winres/goversioninfo@latest，装完确保它在 PATH）
# 产物 model-console.exe 落在本脚本所在目录；files\ 会被 go:embed 打进二进制。
#
param([switch]$SkipVersionInfo)
$ErrorActionPreference = 'Stop'
# goversioninfo 通常装在 `go env GOPATH` 的 bin 下，默认不在 PATH → 先把它加进来（本机实测做法）
$gb = ''
try { $gb = (& go env GOPATH).Trim() } catch { }
if ($gb) { $env:PATH = (Join-Path $gb 'bin') + [IO.Path]::PathSeparator + $env:PATH }

Push-Location $PSScriptRoot
try {
  if (-not $SkipVersionInfo) {
    if (-not (Get-Command goversioninfo -ErrorAction SilentlyContinue)) {
      throw '找不到 goversioninfo。装它：go install github.com/tc-hib/go-winres/goversioninfo@latest'
    }
    # 图标 + 版本信息 + 应用程序清单，同一块资源（清单必须自己写：Go 链接器不嵌清单）
    & goversioninfo -64 -manifest 'app.manifest' -o 'rsrc_windows_amd64.syso' versioninfo.json
    if ($LASTEXITCODE -ne 0) { throw 'goversioninfo 失败' }
  }
  # go:embed files/* 匹配到目录会**递归**收整个目录内容 → 构建前清掉运行时产物，
  # 否则 logs\ 里的采集转储会被打进二进制（实测本机 15 个转储 ≈17KB 就是这么被塞进去的）。
  Remove-Item (Join-Path $PSScriptRoot 'files\logs') -Recurse -Force -ErrorAction SilentlyContinue

  & go build -ldflags '-H windowsgui' -o model-console.exe .
  if ($LASTEXITCODE -ne 0) { throw 'go build 失败' }
  $vi = (Get-Item .\model-console.exe).VersionInfo
  Write-Host ('OK exe=' + (Get-Item .\model-console.exe).Length + ' 字节  FileVersion=' + $vi.FileVersion)
} finally {
  Pop-Location
}
