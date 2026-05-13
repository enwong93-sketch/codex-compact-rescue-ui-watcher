# Contributing

Contributions are welcome, especially fixes for Codex Desktop UI changes.

## Useful Bug Reports

Please include:

- Windows version
- Codex Desktop version if visible
- UI language
- Screenshot of the stuck menu or compact state
- Last 80 lines of `scripts/codex-compact-rescue.log`
- The command you ran

## Local Validation

Check PowerShell parsing:

```powershell
$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\scripts\codex-compact-rescue.ps1),
  [ref]$tokens,
  [ref]$parseErrors
)
$parseErrors
```

Test model switching manually before running the watcher:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-compact-rescue.ps1 -SwitchModelOnly 5.4-Mini
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-compact-rescue.ps1 -SwitchModelOnly 5.5
```
