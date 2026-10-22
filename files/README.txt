MODEL SERVICE CONSOLE  (portable / self-contained)
==================================================

HOW TO OPEN (v19):
  1) DOUBLE-CLICK  model-console.exe     <- recommended
     - Since v19 the exe CONTAINS the program files (Go go:embed, ~3.4 MB).
       It looks for model-console.ps1 in the SAME folder first
       (so an edited script next to the exe wins),
       otherwise it unpacks the built-in copies into
         %LOCALAPPDATA%\model-console\
       and runs from there. So a SINGLE exe file works anywhere.
     - No black console box (Go SysProcAttr HideWindow = true, verified
       by enumerating visible windows 2/4/6 s after launch).
  2) OR double-click the .vbs launcher in this folder (backup, needs WScript).
     Both run: pwsh -NoProfile -WindowStyle Hidden -File model-console.ps1
     -WindowStyle Hidden is REQUIRED (else the WinForms window is invisible).

WHAT IS INSIDE THIS FOLDER:
  model-console.exe        launcher + embedded program files (v19)
  model-console.ps1        GUI, 5 tabs: cards / reserve+gateway /
                           window-model dropdown / cron+cloud /
                           power-limit + versions + links
  model-console-run.ps1    executor (all start/stop/change actions)
  model-windows.cjs        read or change chat-window models (gateway RPC)
  model-crons.cjs          cron job list + switch cron model (one or all)
  model-hb.cjs             read/write heartbeat+compaction model
  model-versions.cjs       local + official latest versions (tab 5)
  console-paths.json       EDIT THIS on a new machine (all machine paths)
  console-tiers.example.json  optional: copy to console-tiers.json to define
                             your own model tiers (absent = built-in list)
  console-*.json           caches (safe to delete; they get rebuilt)
  logs\                    run logs + per-action logs

REBUILD THE EXE (after editing any script):
  Run build-exe.ps1 (kept beside the launcher source, folder name is Chinese:
  docs\<project>\...\model-console-launcher\build-exe.ps1), e.g.
    pwsh -NoProfile -File "<that path>\build-exe.ps1" -OutDir D:\06.AItools\model-console
  (it re-stages the 9 files, runs go build -ldflags "-H windowsgui", copies the exe)

EXTERNAL DEPENDENCIES (cannot be embedded):
  PowerShell 7 (pwsh), node, nvidia-smi, llama-server.exe,
  Strata engine folder, model .gguf files, gateway-rescue.ps1,
  strata-cache-clear.ps1  -> point console-paths.json at them.
  pwsh is searched at C:\Program Files\PowerShell\7\pwsh.exe, then PATH.

HOW TO MOVE TO ANOTHER PC
  A) Quick: copy ONLY model-console.exe anywhere (desktop, USB). Double-click.
     It unpacks itself to %LOCALAPPDATA%\model-console\ and runs.
     Still needs pwsh 7 + node + nvidia-smi on that machine.
  B) Full folder: copy this whole folder, then fix console-paths.json:
       TIER_DIR    = where Strata keeps its tier JSON files
       MODELS      = where the .gguf model files are
       LLAMA_EXE   = full path to llama-server.exe
       GWRESCUE    = gateway-rescue.ps1 (optional; blank = skip)
       CACHECLR    = strata-cache-clear.ps1 (optional; blank = skip)
       LLMSVC      = llm-service.ps1 (optional; blank = skip)
       OPENCLAW_CLI= openclaw.mjs (needed for the window-model page)
     Blank value = that feature is skipped, nothing crashes.
     Keep the exe next to the folder: it prefers the script in its own folder.

POWER LIMIT (tab 5) - IMPORTANT (v19)
  - Setting the power limit REQUIRES ADMINISTRATOR rights.
    Double-clicking the console gives a normal (filtered) token, so
    nvidia-smi answers "Insufficient Permissions".
  - The console now detects that and asks "retry as administrator?"; if you
    say yes it relaunches ONLY that one action elevated (one UAC prompt).
  - Range is validated against the card (3090: 100-480 W, 3080: 100-320 W);
    out-of-range input is refused instead of silently failing.
  - Driver level: a reboot restores the default limit (390 / 320 W).
    VRAM and model loading are unaffected, the card just runs slower.
  - Rollback: type the default value back and press Apply.

SINGLE-GPU MACHINES
  Already supported: with one GPU the console shows one card group only.

SAFETY
  Every start/stop/change pops a confirm box first. The console never touches
  cron/heartbeat windows unless you press the buttons on tab 4.
  Changing a cron job model takes effect immediately (no gateway restart).
  Changing heartbeat/compaction model writes openclaw.json (auto backup) and
  needs a gateway restart to take effect.

PAGE 7 SELFCHECK AND AUTO PATH DETECTION (v22, 2026-10-20)
----------------------------------------------------------
  On open, the console runs model-detect.cjs in background. It probes:
    pwsh, node, nvidia-smi (+ GPU list), openclaw CLI + version, gateway :18789,
    Strata dir + engine version, router :8080, tools dir (strata-router.py /
    start vbs), llama-server.exe, model dir, :8090, :8096, helper scripts.
  Page 7 lists each item as [OK] or [MISS] with path and what to do if missing.
  Buttons: "rescan selfcheck" (report only) and "selfcheck + fix paths"
  (writes detected values back into console-paths.json ONLY for keys whose
  current value does not exist on this machine; backs up first as
  console-paths.json.bak-detect-<timestamp>).

VRAM THRESHOLD AUTO-CALIBRATION (v22)
-------------------------------------
  Action "calib" measures what the currently running big-model tier actually
  occupies (sum of both cards, nvidia-smi memory.used) and writes
  console-calib.json. Page 1 then uses measured + 512 MiB headroom as the
  threshold; tiers never measured yet keep the placeholder value.
  Measured example: iq3x = 42680 MiB while the placeholder said 40450
  (2230 MiB optimistic -> "startable" shown but start could fail).

WHY START-BIG FAILED BEFORE (v22 fixes, both were my bugs)
----------------------------------------------------------
  A) Executor looked for strata-start-all-hidden.vbs / llama-router-start.ps1
     inside the console package dir ($PSScriptRoot), but they live in the TOOLS
     dir (D:\06.AItools). Now ToolFile searches TOOLDIR -> package -> Strata
     parent -> D:\06.AItools, and if not found it says which key to fix.
  B) console-paths.json was INVALID JSON (single backslashes -> \0 bad escape),
     ConvertFrom-Json failed and the script swallowed it in try/catch, so
     "change one file to move machines" never took effect. Rewritten with
     doubled backslashes + new keys TOOLDIR and NODE (old file kept as
     console-paths.json.bak-v22). Verify with:
       pwsh -File <workspace>\docs\...\probes\check-paths-json.ps1

STILL NOT DONE (owner decides): step 3 installer wizard - owner said do 1+2,
  test them OK first, only then build 3.

ICON + FILE PROPERTIES (v23, 2026-10-21)
-----------------------------------------
  The exe now carries its own icon (dark blue rounded square, white cloud,
  green power symbol) and full "Details" tab data:
    FileVersion 1.23.0.0 / ProductName "model-console (Chinese UI: model
    service console)" / ProductVersion 1.23.0.0 (v23) / FileDescription
    (one-line feature summary) / CompanyName / InternalName / OriginalFilename.
  Built by: make-icon.ps1 -> model-console.ico, versioninfo.json ->
  goversioninfo -64 -> rsrc_windows_amd64.syso -> go build links it automatically.
  build-exe.ps1 skips this step (with a notice) if the tool is missing, so
  packaging never breaks. -NoRes forces skipping.

REFRESH BEHAVIOUR (v23)
-----------------------
  * Header auto-refresh: every 5 seconds re-read GPU memory (76 ms), current
    tier via :8080/__status (10-88 ms) and RAM (2 ms). Port enumeration is
    slow (390-900 ms) so it runs every 4th tick (~20 s); the timer skips
    while a start/stop action is running.
  * "Refresh" button now re-scans ports + both cards + current tier + RAM and
    repaints the header too (measured 450 ms), and logs the elapsed time.
  * Header shows the read time: "collect 7/7 @HH:MM:SS".
  * Page 5 official-version fetch moved to its OWN background slot
    (StartVersionsRead / PollVersionsRead): it no longer occupies the
    exclusive action slot, so switching pages while it runs (2-5 s) no longer
    pops "previous task still running". That popup now also says how long
    the running task has been going.

GREEN / PORTABLE (answer to owner question 3)
--------------------------------------------
  It already IS a green app: the exe carries all program files, double-click
  runs it, no installer, no registry writes. Data goes to the exe folder if
  the scripts are there, otherwise to %LOCALAPPDATA%\model-console.
  v23 fix: if a file is locked (window still open) the launcher no longer
  records the "already extracted" fingerprint, so the next start retries
  instead of staying on the old version forever.
  What a NEW machine still needs installed (cannot be packed into the exe):
  PowerShell 7, node, nvidia-smi (NVIDIA driver), OpenClaw, Strata engine,
  model files. Page 7 self-check tells you which of those are missing.

HEADER CLIPPING FIX (v24, 2026-10-21)
--------------------------------------
  Owner: "the RAM / GPU / collect words look half covered". Measured with
  TextRenderer: label width 852 px, bold 11pt line height 19 px, label height
  30 px -> only ONE line fits; the v23 string measured 848 px (4 px of slack),
  so when a number grew by one digit the text wrapped and the 2nd line was cut
  in half. Fix: full-width parentheses -> half-width (saves ~66 px), separator
  "  |  " -> " | " (saves 48 px) => 772 px now (80 px slack); label height 34
  and AutoEllipsis=true so worst case shows "..." instead of half a glyph.
  The bare "@HH:MM:SS" is now labelled: "refreshed at HH:MM:SS" (time this
  header row was last read) - owner asked what that unnamed time meant.
  Version resource bumped to 1.24.0.0 / 1.24.0.0 (v24).

FREEZE FIX (v25, 2026-10-21)
-----------------------------
  Owner: "I stopped the models with the console and the window froze; opening it
  again froze too". Root cause: the UI thread read http://127.0.0.1:8080/
  __status SYNCHRONOUSLY with a 6 s timeout. Right after a service is stopped
  the port is often HALF-OPEN (it accepts but never answers) - measured 6049 ms
  per read. One refresh = 6049 (status) + 985 (port scan) + 77 (nvidia-smi) +
  3 (RAM) = 6453 ms, but the header timer fires every 5000 ms -> the UI message
  queue never drains = frozen; reopening hit the same state, so it froze again.
  Fix (only StrataStatus changed): start the read in the background, wait at
  most 150 ms on the UI thread, keep the last value if it has not arrived,
  and let the 3 s HttpClient timeout set it to null (UI then shows "not
  running"). Measured: half-open worst case 170 ms per read (was 6049 ms).
  A/B test (two copies differing ONLY in that function, both pointed at a
  half-open test port): old = header readable 5 of 12 tries; new = 12 of 12.

HIDDEN CONTROL CHARACTER FIXED (v25)
-------------------------------------
  TOOLDIR was stored as "D:" + 0x06 + ".AItools" in 3 places (a patch script
  turned \06 into an octal escape). It worked only because console-paths.json
  overrode it - on a fresh machine without that file the tool dir would be
  garbage. Now correct; both scripts scan clean (0 control characters).

WORDING CLEANED (v25)
---------------------
  8 explanatory lines no longer mention internal workflow names (owner / ask
  Moyun / upgrade-assistant / duty roster / cloud model). Kept: the model
  names the owner named ("da kuai tou" family), real window titles, real
  folder names. Version resource 1.25.0.0.

MICROSOFT / ANTIVIRUS CHECK (checked only, nothing changed yet)
---------------------------------------------------------------
  - exe is NOT digitally signed (Get-AuthenticodeSignature = NotSigned).
  - No Mark-of-the-Web on any copy (local build/copy does not add one), so
    SmartScreen will not nag on this machine; a copy downloaded from the web
    or unpacked from an email attachment WOULD carry it and may prompt.

  - Windows application manifest: ADDED in v28 (was missing before - verified
    two ways: Win32 EnumResourceNames showed RT_MANIFEST empty, and a control
    build with the .syso removed produced an exe with NO resource directory at
    all, i.e. the Go linker does not embed a manifest by default). The manifest
    declares asInvoker (explicitly not admin) and four supportedOS GUIDs so
    Windows 10/11 recognise the compatibility profile instead of guessing.
    DPI awareness is deliberately NOT declared: the UI coordinates are all
    hardcoded pixels and the window is created by pwsh.exe, so DPI behaviour is
    governed by pwsh.exe's own manifest - declaring it here would only shrink
    the layout without any benefit. Text is therefore still bitmap-scaled on a
    high-DPI display (blurry) - unchanged, not fixed by this.
  - This machine: Microsoft Defender service stopped, real-time protection
    off, no AV registered - so a local scan could not be run (MpCmdRun
    failed, hr 0x80070667).
  - Heuristic risk profile of this design: single Go binary that extracts
    .ps1 files into %LOCALAPPDATA% and launches pwsh. Unsigned +
    self-extracting is what heuristics like to flag.
  - Owner picked option (a) only, because it is free: manifest added in v28.
    Still open: (b) code signing with a purchased certificate (costs money),
    (c) submitting the file for reputation / whitelist. SHA256 of the shipped
    exe is recorded in the project ledger.

RELEASE PREPARATION (v26, 2026-10-22)
--------------------------------------
  Owner decided the monetisation route: NO video (no time), main line =
  sell "I set it up for you + Q&A" service on Goofish (owner already has a
  shop there for madVR setup), GitHub as a free open-source business card.
  Plan: docs/.../release-and-monetisation-plan.md (6 stages, each with an
  acceptance criterion). Stage 0 (this version) = de-personalise + one-shot
  release packaging. NOTHING in this working pack changes behaviour.

  Hardcoded local username removed (4 places): desktop path now uses
  [Environment]::GetFolderPath(\'Desktop\'); the OpenClaw package/cli paths
  now come from $env:APPDATA / $env:USERPROFILE candidates instead of
  "C:\<用户名>\...". Verified on this machine: same resolved
  values as before (behaviour unchanged), and it now works for any user.

  Tab 6 (local entries) is no longer hardcoded: the file list is built from
  variables already in the script and any entry that does not exist on this
  machine is simply not shown; the service list and the note lines can now
  be overridden from console-paths.json keys ENTRIES / ENTRYNOTES /
  FILENOTES (absent = built-in defaults, so this machine is unchanged).

  Selfcheck timestamp fixed: it used to be written in UTC (showed 12:02
  while it was 20:02 - 8 hours off). Now local time, matching every other
  timestamp in the UI.

  Added LICENSE.txt (MIT) + a Chinese reference copy of the same license
  (file name is in Chinese; the English text governs). Added tools/make-release.cjs: one command
  produces the public package - it copies the 10 program files, applies a
  21-rule neutralisation table (with a PROTECT list so technical names like
  FilterAdministratorToken are NOT mangled), rewrites console-paths.json as
  an example file, appends an English README section (license / what it is
  / what it is not / dependencies / first run / disclaimer), builds a
  neutral exe (Company "model-console", Copyright "MIT License"), zips it,
  prints SHA256, and re-checks syntax (both ps1 errors:0, all cjs --check).
  Neutralisation report: 27 owner-mentions replaced in the UI script, and
  the leftover check reports ZERO occurrences of the internal words.

  Release package verified as a "first run on a new machine": ran the
  release exe with LOCALAPPDATA pointed at a throwaway folder (children
  inherit it) so this machine was not touched - window opened, 11 files
  unpacked, tabs 6 and 7 contain zero machine-specific words, selfcheck
  reported 11 ok / 2 missing (the two missing are just services not
  running). Three screenshots for the repo README are in
  docs/.../release-assets/.

  Sizes and hashes: the working exe grew from 3,495,936 bytes; this build is
  FileVersion 1.26.0.0. Exact byte sizes and SHA256 of the working exe, the
  release exe and the release zip are listed in SHA256.txt next to the zip, and
  in the project ledger. They are deliberately NOT written inside this README:
  this README is embedded in the exe, so quoting the exe hash here is circular
  (editing the text changes the hash). The build is STILL UNSIGNED.

v27 - MODEL TIER LIST CAN BE EXTERNALISED
--------------------------------------------------
  The start/stop tier list used to be hardcoded in the two PowerShell
  scripts. It can now live in an external file: put console-tiers.json
  next to the scripts (or next to the exe's unpacked folder) and both the
  window and the executor read it. No file, unreadable file, or no valid
  entries -> the built-in list is used, so an untouched install behaves
  exactly as before (verified: 6 executor DryRun cases and the 12 tier
  rows shown in tab 1 are identical to v26 on this machine).

  Copy console-tiers.example.json to console-tiers.json and edit it to
  describe your own models. Each entry: key (id used by start/stop),
  name (shown in tab 1), need (total VRAM in MiB the tier occupies, used
  for the "can start / not enough VRAM" verdict), dual (needs both cards),
  act (big = engine tier switch, 27b = via the 27B router on :8090,
  vl = standalone llama instance), and optional engine / tier / id / gguf
  / mmproj / ctx / port / nameRun / needRun. Entries whose key starts with
  __ are comments, not models. Duplicate keys, unknown act values and
  non-positive need are reported and skipped, never silently accepted.

  Do not confuse console-tiers.json with console-models.json: the latter
  is the tab-3 "switchable models" cache produced by the executor and has
  completely different contents.

  The vision-model port is no longer hardcoded either: it follows the
  act=vl entry's port (default 8096 when absent). The 27B router port
  :8090 stays fixed because the assistant registers it.

  A malformed file is reported in plain words (including the usual cause:
  single backslashes in Windows paths) and the built-in list is used for
  that run - it does not fail silently.

v28 - WINDOWS APPLICATION MANIFEST (the free item of the three)
--------------------------------------------------
  The exe now carries an embedded application manifest (app.manifest, 951
  bytes, injected through goversioninfo -manifest into the same resource
  block as the icon and version info). It declares:

    requestedExecutionLevel = asInvoker   (explicitly asks for NO admin)
    supportedOS = Windows 7 / 8 / 8.1 / 10-11 GUIDs

  Why it matters: without a manifest Windows guesses the compatibility
  profile and the UAC level is implicit. Declaring asInvoker also means the
  power-limit button keeps asking for elevation on purpose (one UAC prompt)
  instead of the whole program running elevated.

  What it does NOT change: DPI. The window is created by pwsh.exe, so DPI
  awareness and control theming come from pwsh.exe's manifest, not ours; and
  the UI uses fixed pixel coordinates, so declaring awareness here would make
  the layout smaller on a scaled display for no gain. Text sharpness on a
  150% display is therefore unchanged.

  Verified by reading the built exe back, two independent ways: Win32
  EnumResourceNames lists RT_MANIFEST(24) id 1 (951 bytes), and a PE parser
  extracts the manifest text from the resource directory. The four GUIDs were
  copied from pwsh.exe's own manifest rather than typed from memory.


v29 - FIXED: "CANNOT RUN THIS COMMAND / SYSTEM CANNOT FIND THE FILE" ON
MACHINES WHERE POWERSHELL 7 CAME FROM THE MICROSOFT STORE
---------------------------------------------------------------
  PowerShell 7 installs two ways and the paths differ. The MSI installer puts
  pwsh.exe at C:\Program Files\PowerShell\7\pwsh.exe. The Microsoft Store puts it
  under C:\Users\<you>\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_<pkg>\pwsh.exe.

  This program used to hard-code the MSI path. On a Store install that path does
  not exist, so EVERY button failed with the raw Windows message "system cannot
  find the file specified" - which gives no hint about what was actually missing.
  Worse, it is a dead end: the "self-check and fix paths" button needs pwsh to
  start too, so the very function meant to fix paths could not start either.

  The self-check page even said "PowerShell 7: present" while nothing worked,
  because detection used a different lookup (it searches PATH) than the runtime
  path. Two different logics for the same thing - that contradiction was the clue.

  Now pwsh is located at runtime: first the folder that is ALREADY running this
  script ($PSHOME, the most reliable), then the MSI path, then whatever "pwsh"
  resolves to on PATH. A "PWSH" entry in console-paths.json still overrides all
  of them. If none exist you get a plain-language message instead of a system
  error: install PowerShell 7 (winget install Microsoft.PowerShell) or set PWSH
  in console-paths.json (Windows path backslashes must be doubled).

  Verified: reproduced the exact error text locally by pointing Start-Process at
  a non-existent exe; probed the resolver three ways (this machine, a simulated
  Store install where the first two candidates are forced empty - it fell back to
  PATH and launched a child process with exit code 0, and the all-empty case
  triggers the plain-language message). This machine is unaffected: its pwsh IS
  the MSI path, so the resolved value is identical to the old hardcoded one.


LICENSE
--------------------------------------------------
MIT License (see LICENSE.txt; LICENSE-中文参考.txt is an unofficial Chinese
translation for convenience - the English text governs).

WHAT THIS IS
--------------------------------------------------
A single-file Windows GUI to run and switch local LLM services
(llama.cpp / Strata style routers), including:
  - start/stop model tiers, dual-GPU combined start
  - switch which model each OpenClaw chat window uses
  - switch the model used by scheduled jobs, heartbeat and compaction
  - NVIDIA power-limit control (needs administrator rights)
  - measured VRAM threshold auto-calibration
  - built-in self-check that finds missing paths on a new machine
  - version readout for OpenClaw / engine / llama.cpp

WHAT THIS IS NOT
--------------------------------------------------
  - It does NOT download or ship model files (.gguf). You provide them.
  - It is NOT a chat client.
  - It is Windows-only (WinForms + PowerShell 7).

DEPENDENCIES (all three, on the target machine)
--------------------------------------------------
  1) PowerShell 7   (pwsh.exe)
  2) node.exe       (Node.js)
  3) nvidia-smi     (NVIDIA driver installed; at least one NVIDIA GPU)
  Plus whatever local engine you actually run (Strata / llama.cpp / Ollama).

FIRST RUN
--------------------------------------------------
  1) Double-click model-console.exe  (or 打开控制台.vbs for no console flash)
  2) Go to tab 7 (selfcheck). It lists what is missing and where it looked.
     Press "selfcheck and fix paths" to auto-detect and write
     console-paths.json for you.
  3) If SmartScreen says "unknown publisher": this build is UNSIGNED.
     Right-click the exe -> Properties -> uncheck "Unblock", or accept the
     warning. SHA256 of the shipped exe is printed next to the zip.

DISCLAIMER
--------------------------------------------------
Provided as-is, no warranty. Stopping a model interrupts in-flight requests.
Changing the power limit is a driver-level setting; a reboot restores the
driver default. Use at your own risk.
