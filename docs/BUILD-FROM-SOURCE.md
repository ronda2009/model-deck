# 自己编译 / Build from source

```powershell
pwsh -File build-exe.ps1        # 产出 model-console.exe（同目录）
```

## 结构

- `main.go` — Go 启动器：把 `files\` 里的程序文件封进二进制（`go:embed`），运行时若同目录有 `model-console.ps1` 就用同目录那份，否则释放到 `%LOCALAPPDATA%\model-console\` 再用 `pwsh.exe` 拉起界面。
- `files\` — **真正的程序逻辑**：`model-console.ps1`（界面）、`model-console-run.ps1`（执行器）、`model-*.cjs`（OpenClaw 侧读写）、`打开控制台.vbs`（无黑框启动）、两份示例配置、README、LICENSE。
- `app.manifest` / `versioninfo.json` / `model-console.ico` — Windows 资源（清单 + 版本信息 + 图标），由 `goversioninfo` 合成 `rsrc_windows_amd64.syso`，`go build` 自动链接。

## 两个坑（别踩）

1. **Go 链接器不嵌应用程序清单**。删掉 `app.manifest` 或忘了 `-manifest`，exe 就没有清单（实测：把 `.syso` 移开重编，产物连资源目录都没有）。
2. **`go:embed files/*` 会把子目录整个递归收进去**。构建前先把 `files\logs\` 之类运行时目录清掉，否则日志转储会被打进二进制（体积暴涨）。本仓库默认不带 `logs\`。

## 内置默认路径说明（重要，别被吓到）

`files\model-console.ps1` 与 `files\model-console-run.ps1` 顶部写死的那批路径（`D:\06.AItools\...`）是**作者本机布局的内置后备值**，不是要求你照抄：

- 同目录放一份 `console-paths.json`（发布 zip 里它叫 `console-paths.example.json`，仓库里在 `files\console-paths.json`，内容就是全空示例）就会**覆盖**它们；
- 或者打开软件点 **页⑧「自检并修正路径」**，它会自动找并把结果写回那个文件；
- 只有「文件不存在 / 读不进去」时程序才退回内置后备值，而且会用中文告诉你哪里不对。

所以**换机器不用改源码，改配置就行**。（发布 zip 里附的 `console-paths.json` 各项都是留空的，就是走这条路径。）

## 依赖（跑起来需要）

PowerShell 7（`pwsh.exe`）、Node.js、`nvidia-smi`，外加你实际要跑的推理引擎。详见根目录 README。
