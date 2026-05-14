# Codex Compact Rescue

Windows automation for recovering Codex Desktop compact failures.

When Codex gets stuck while auto-compacting context on GPT-5.5, this watcher applies a tested recovery flow:

1. Detects `正在自動壓縮上下文`, `上下文正在自動精簡`, or compact endpoint errors.
2. Clicks Stop/Pause to cancel the stuck compact attempt.
3. Switches the active thread to GPT-5.4-Mini.
4. Sends `繼續`.
5. Watches for a newly visible `上下文已自動精簡` marker.
6. Switches back to GPT-5.5 without changing speed/reasoning settings.
7. Sends `繼續` again and waits 60 seconds before the next recovery round.

The script uses Windows UI Automation labels plus keyboard navigation. It was tested with normal and full-screen Codex Desktop windows.

## Requirements

- Windows 10/11
- Codex Desktop app
- Windows PowerShell 5.1 or PowerShell 7+
- The affected Codex thread must stay visible. Do not minimize Codex to the taskbar while the watcher is running.

## Install

Clone or download this repository, then open PowerShell in the repo folder:

```powershell
cd "C:\path\to\codex-compact-rescue"
```

If Windows blocks downloaded scripts, unblock them once:

```powershell
Get-ChildItem .\scripts -File | Unblock-File
```

## Usage

Start the watcher:

```powershell
.\scripts\start-codex-compact-rescue.bat
```

Stop the watcher:

```powershell
.\scripts\stop-codex-compact-rescue.bat
```

Show recent logs:

```powershell
Get-Content .\scripts\codex-compact-rescue.log -Tail 100
```

## Test Model Switching

Test switching to GPT-5.4-Mini:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-compact-rescue.ps1 -SwitchModelOnly 5.4-Mini
```

Test switching back to GPT-5.5:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-compact-rescue.ps1 -SwitchModelOnly 5.5
```

## Options

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-compact-rescue.ps1 `
  -PollSeconds 5 `
  -CompactWaitSeconds 600 `
  -AfterStopDelaySeconds 1 `
  -RoundCooldownSeconds 60
```

- `-PollSeconds`: how often to scan the visible Codex UI.
- `-CompactWaitSeconds`: max wait for a new compact completion marker.
- `-AfterStopDelaySeconds`: wait after clicking Stop/Pause before switching models.
- `-RoundCooldownSeconds`: wait after a completed recovery before watching again.
- `-ResumeText`: text sent when no clickable continue button is available. Default: `繼續`.
- `-NoFinalResume`: switch back to GPT-5.5 but do not send final `繼續`.
- `-Once`: handle one recovery round then exit.
- `-WhatIf`: log planned actions without clicking or typing.

## Notes

- This is UI automation, so Codex UI changes can require script updates.
- Keep the model button and composer visible. Full-screen is fine.
- The watcher suppresses the same visible compact error for 15 minutes after a successful recovery, so old error text does not trigger another round. Active compacting status text is never cached, because a later status marker can be a real new compact round.
- Completion is not guessed by a fixed timer. The watcher records existing compact markers and waits for a newly visible completion marker.

## Troubleshooting

If the model menu is left open, press `Esc`, stop the watcher, then start again:

```powershell
.\scripts\stop-codex-compact-rescue.bat
.\scripts\start-codex-compact-rescue.bat
```

If model switching fails, test each direction manually with `-SwitchModelOnly` and inspect the log.

## License

MIT
