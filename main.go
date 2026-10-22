// model-console-launcher/main.go — 双击即开的启动器（v19：把程序文件封进 exe）
// 编译：pwsh -File build-exe.ps1   （或 go build -ldflags "-H windowsgui" -o model-console.exe .）
// 三个关键点：
//   1) HideWindow = true —— 不设的话 GUI 程序启动控制台程序(pwsh)会自动开一个黑框（老板 2026-10-20 反馈）。
//   2) -WindowStyle Hidden 必需 —— 否则 WinForms 主窗口不可见（2026-10-19 实测）。
//   3) go:embed 把 ps1/cjs/json/README/vbs 封进二进制：只拷 exe 一个文件到任何位置也能跑，
//      运行时释放到 %LOCALAPPDATA%\model-console\（同目录若已有 ps1，则优先用同目录的，方便就地改脚本）。
package main

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

//go:embed files/*
var packed embed.FS

var (
	user32        = syscall.NewLazyDLL("user32.dll")
	msgBox        = user32.NewProc("MessageBoxW")
	kernel32      = syscall.NewLazyDLL("kernel32.dll")
	getModulePath = kernel32.NewProc("GetModuleFileNameW")
)

// 封进 exe 的文件（去掉 files/ 前缀后的名字）
var packedNames = []string{
	"model-console.ps1",
	"model-console-run.ps1",
	"model-windows.cjs",
	"model-crons.cjs",
	"model-versions.cjs",
	"model-hb.cjs",
	"model-detect.cjs",
	"console-paths.json",
	"README.txt",
	"打开控制台.vbs",
	// [2026-10-22 v27] 档位清单示例：拷走单个 exe 也要能拿到它（复制成 console-tiers.json 就能自定义模型清单）
	"console-tiers.example.json",
	// [2026-10-22 v27] 许可也要跟着软件走：只拷 exe 时同样释放出来
	"LICENSE.txt",
	"LICENSE-中文参考.txt",
}

func exeDir() string {
	var buf [512]uint16
	n, _, _ := getModulePath.Call(uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)), 0)
	if n == 0 {
		return filepath.Dir(os.Args[0])
	}
	return filepath.Dir(string(utf16.Decode(buf[:n])))
}

func show(title, text string) {
	tPtr, e1 := syscall.UTF16PtrFromString(title)
	xPtr, e2 := syscall.UTF16PtrFromString(text)
	if e1 != nil || e2 != nil {
		return
	}
	msgBox.Call(0, uintptr(unsafe.Pointer(xPtr)), uintptr(unsafe.Pointer(tPtr)), uintptr(0x10))
}

// 封进 exe 的内容指纹（改了脚本重编译，指纹变，释放目录会自动更新）
func packedHash() string {
	h := sha256.New()
	for _, name := range packedNames {
		b, err := packed.ReadFile("files/" + name)
		if err != nil {
			continue
		}
		h.Write([]byte(name))
		h.Write(b)
	}
	return hex.EncodeToString(h.Sum(nil))
}

// 释放到目标目录；指纹一致就跳过。返回是否可用。
func extractTo(dir string) (bool, error) {
	marker := filepath.Join(dir, ".packed-hash")
	want := packedHash()
	if old, err := os.ReadFile(marker); err == nil && string(old) == want {
		if _, err := os.Stat(filepath.Join(dir, "model-console.ps1")); err == nil {
			return true, nil // 已是同一版，直接用
		}
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return false, err
	}
	allOK := true
	for _, name := range packedNames {
		b, err := packed.ReadFile("files/" + name)
		if err != nil {
			continue
		}
		// 正在被占用的文件（界面还开着）写不进去 → 跳过，用旧的那份
		if err := os.WriteFile(filepath.Join(dir, name), b, 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "write %s failed: %v\n", name, err)
			allOK = false
		}
	}
	// [2026-10-21 v23] 关键修正：只有全部写成功才记指纹。
	// 旧写法不管写没写成都把 .packed-hash 写成新版 → 下次启动以为「已是同一版」直接跳过，
	// 结果界面还开着时那次没更新成功，之后关掉窗口也永远不会再更新（一直停在旧版）。
	if allOK {
		_ = os.WriteFile(marker, []byte(want), 0o644)
	}
	return true, nil
}

// 决定用哪份脚本：①exe 同目录有 ps1（整包搬走、就地改脚本）②否则释放到 %LOCALAPPDATA%\model-console
func resolvePack() (string, error) {
	d := exeDir()
	if _, err := os.Stat(filepath.Join(d, "model-console.ps1")); err == nil {
		return d, nil
	}
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base = os.TempDir()
	}
	dir := filepath.Join(base, "model-console")
	if ok, err := extractTo(dir); err == nil && ok {
		return dir, nil
	}
	if _, err := os.Stat(filepath.Join(dir, "model-console.ps1")); err == nil {
		return dir, nil
	}
	return "", fmt.Errorf("找不到 model-console.ps1，也没能释放内置副本：%s", dir)
}

func findPwsh() string {
	cands := []string{
		`C:\Program Files\PowerShell\7\pwsh.exe`,
		`C:\Program Files\PowerShell\7-preview\pwsh.exe`,
	}
	for _, c := range cands {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	if p, err := exec.LookPath("pwsh"); err == nil {
		return p
	}
	return ""
}

func main() {
	pack, err := resolvePack()
	if err != nil {
		show("模型服务控制台", err.Error())
		return
	}
	ps1 := filepath.Join(pack, "model-console.ps1")
	pwsh := findPwsh()
	if pwsh == "" {
		show("模型服务控制台", "找不到 PowerShell 7（pwsh.exe）。\n装一下 PowerShell 7 再双击：https://github.com/PowerShell/PowerShell/releases")
		return
	}
	args := append([]string{
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ps1,
	}, os.Args[1:]...)
	cmd := exec.Command(pwsh, args...)
	cmd.Dir = pack
	// 关键：不 HideWindow 就会闪一个黑色控制台窗口
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err := cmd.Start(); err != nil {
		show("模型服务控制台", "启动失败："+err.Error())
		return
	}
	// 界面是靠 pwsh 起的；这里等它退出，exe 才退出（不占控制台）
	_ = cmd.Wait()
	_ = time.Now()
}
