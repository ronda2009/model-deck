# 模型服务控制台 / Model Service Console

**单文件 Windows 图形界面，管本地大模型服务**：起停与换档、双卡合扛一个模型、给每个 OpenClaw 对话窗口换模型、定时任务换模型、显卡功率上限、显存实测校准、换电脑自动找路径。

A single-file Windows GUI for local LLM services: start/stop model tiers, run one model across two GPUs, switch which model each OpenClaw chat window uses, switch the model used by scheduled jobs / heartbeat / compaction, set NVIDIA power limits, measure real VRAM cost per tier, and auto-detect paths on a new machine.

![模型启停](release-p1-models.png)
![本机入口](release-p6-entries.png)
![自检](release-p7-selfcheck.png)

---

## 为什么做这个 / Why

本地模型玩到「多档位 + 多张卡 + 多个助手窗口」之后，命令行就不够用了：
- 换一档要停服务、改配置、重启、再确认哪个窗口还在用旧档；
- 两张卡想合扛一个模型，得自己算显存、挑锚卡；
- 助手（OpenClaw）的每个对话窗口各自绑定模型，批量换很烦；
- 换台电脑，路径全要重来。

这个工具把这些做成**点一下的按钮**，并且**开窗先自检**：缺什么、去哪儿找，直接列出来。

Once you run several quant tiers across two GPUs with several assistant chat windows bound to different models, command lines stop being enough. This turns those operations into buttons, and self-checks the machine on launch.

## 它不是什么 / What it is not

- **不打包模型文件**（`.gguf` 由你自己下载，几个 G，许可也归你）
- **不是聊天客户端**
- **只有 Windows**（WinForms + PowerShell 7）

## 依赖 / Dependencies（三样都要）

1. **PowerShell 7**（`pwsh.exe`）
2. **Node.js**（`node.exe`）
3. **nvidia-smi**（装好 NVIDIA 驱动，至少一张 N 卡）

外加你实际要跑的引擎（Strata / llama.cpp / Ollama 之类）。

## 怎么用 / How to use

1. 双击 `model-console.exe`（或 `打开控制台.vbs`，不闪黑框）
2. 打开 **页⑦ 自检**：它列出缺什么、找过哪些地方。点 **「自检并修正路径」**，它会自动定位并把路径写进 `console-paths.json`
3. 页① 起停与换档、页③ 给对话窗口换模型、页④ 定时任务与心跳、页⑤ 显卡功率与版本、页⑥ 本机入口

exe 是**绿色单文件**：程序文件封在二进制里（Go `go:embed`）。同目录有 `model-console.ps1` 就用同目录那份（改了立刻生效），否则释放到 `%LOCALAPPDATA%\model-console\`。不写注册表。

### 模型清单也可以自己定 / Your own model list（v27 新增）

页① 那张「档位清单」以前写死在脚本里，现在可以外置：把包里的 `console-tiers.example.json` 复制成 **`console-tiers.json`** 放同目录，界面与执行器就按你这份清单办事。**没有这个文件就用内置清单**（内容就是示例文件里那 11 条），所以不改就跟以前一模一样。

每条字段：`key`（起停用的代号）、`name`（界面显示名）、`need`（起这档两卡合计要占的显存 MiB，用来判「可起/显存不够」）、`dual`（是否两卡合扛）、`act`（`big`=引擎换档 / `27b`=走 27B 路由 :8090 / `vl`=独立 llama 实例），可选 `engine`/`tier`/`id`/`gguf`/`mmproj`/`ctx`/`port`/`nameRun`/`needRun`。`key` 以 `__` 开头的是说明文字，不算模型。重复 key、`act` 不认识、`need` 不是正数——都会明确报出来并跳过，不会闷着吞。

> 别和 `console-models.json` 搞混：那个是页③「可换模型」下拉的缓存（程序自动生成），内容完全不同。
> 视觉模型的端口也跟着清单走（不给就默认 8096）；27B 路由端口 :8090 是助手注册死的，不能换。
> JSON 里 Windows 路径的反斜杠要写两个（`\\`），写一个整个文件读不进去——读不进去时程序会用中文告诉你，并临时改用内置清单。

### 程序清单 / Application manifest（v28 新增）

exe 内嵌了 Windows 应用程序清单（`app.manifest`，951 字节）：

- `requestedExecutionLevel = asInvoker` —— 程序本身**明确不要管理员**；只有「改显卡功率上限」那一个按钮会按设计单独弹一次 UAC。
- 声明 Windows 7 / 8 / 8.1 / 10-11 兼容 —— 让 Win10/11 按声明识别，而不是靠猜。

**没做的事，说明原因**：清单里**故意不声明 DPI 感知**。界面用的是固定像素坐标，而且窗口是由 `pwsh.exe` 这个进程创建的（DPI 行为归 pwsh 自己的清单管）——在这里单方面声明只会让窗口在 150% 缩放下小一圈、内容挤爆，清晰度收益反而拿不到。所以**高缩放屏上文字仍是位图缩放（略糊）**，这条没变。

## 首次运行的两个提示 / Two first-run notes

- **SmartScreen 说「未知发布者」**：这个版本**未数字签名**。右键 → 属性 → 取消勾选「解除锁定」，或直接接受警告。exe 的 SHA256 标在下载页与 `SHA256.txt`。
  （v28 起 exe 已内嵌 Windows 应用程序清单：明确 `asInvoker` 不要管理员 + 声明 Win7/8/8.1/10-11 兼容性。**清单不等于签名** —— SmartScreen 看的是签名与下载信誉，所以这条警告还会有。）
- **设置显卡功率需要管理员权限**：被拒时界面会问你要不要提权重试（一次 UAC）。功率是驱动级设置，**重启后恢复驱动默认值**。

## 安全 / Safety

- 停模型会中断正在跑的请求；起停前都会弹窗确认。
- 显存门槛用**实测值**（自动校准），不是猜的。
- 只动你点的那个对象，不批量改全局。

## 打赏 / Buy me a coffee

软件免费。如果它帮你省了时间，可以请作者喝杯咖啡 🙂

<a href="https://qr.alipay.com/fkx13840f42u5aj2vrhkh5c"><img src="docs/donate/alipay-qr.jpg" width="240" alt="支付宝收款码 / Alipay QR" /></a>

扫码或[点这个链接直达付款页](https://qr.alipay.com/fkx13840f42u5aj2vrhkh5c)。

为什么不用 GitHub Sponsors：实测 GitHub 官方「支持地区」清单里**没有中国大陆**，中国大陆账号目前开不了官方收款（只能排 waitlist）；而且国内朋友得有国际 Visa/MasterCard 才能付，银联不行。所以这里挂的是支付宝收款码。

---

## 许可 / License

MIT（见 `LICENSE.txt`；`LICENSE-中文参考.txt` 是非官方中文参考，以英文原文为准）。

## 免责 / Disclaimer

按「原样」提供，无担保。显卡功率、显存、速度都取决于你的机器。用了出事自己担着 🙂

## 下载 / Download

看 **Releases**：`model-console-v28-windows.zip`（约 2.0 MB，含 exe + 两份示例配置（路径 / 模型清单）+ README + LICENSE + `SHA256.txt`）。

## 这个版本的状态 / Status

v26 是**第一个对外发布版**；v27 把「模型清单」做成可外置（不改就跟以前一样）；v28 给 exe 加了应用程序清单（免费那条，**仍**未签名）。主要在我自己这台机器上日常使用（RTX 3090 + RTX 3080 双卡，Strata 引擎 + llama.cpp + OpenClaw）。**未签名**，**只在 Windows 上测过**。有问题欢迎开 issue。
