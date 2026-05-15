# Changelog

## 0.1.11

- Sends the final `繼續` only once after returning to GPT-5.5, then waits longer for Codex to load and confirm the run started.
- Confirms the final resume by detecting a visible stop/pause control or running status such as `正在思考` / `正在執行`.
- Adds `-FinalResumeConfirmSeconds` to tune the final confirmation wait time.

## 0.1.10

- Treats `上下文已自動精簡` as a candidate signal only; the watcher now waits for a new post-compact ready marker such as `已引導對話` before switching back to GPT-5.5.
- Prevents early model rollback when Codex displays the compact marker before the conversation is fully reattached.

## 0.1.9

- Adds delayed model confirmation after keyboard/mouse model changes, reducing failures when Codex shows transient model-change warnings.
- Retries the final `繼續` after returning to GPT-5.5 and confirms it by checking for a visible stop/pause control.

## 0.1.8

- Avoids stopping compact too early by requiring the active compacting status to disappear before switching back to GPT-5.5.
- Removes the unsafe idle-loop shortcut that switched from GPT-5.4-Mini to GPT-5.5 just because any completion marker was visible.
- Accepts `Codex*` window titles so temporary `Codex (not responding)` states during compact do not abort the recovery wait.

## 0.1.7

- Restores the full default recovery flow: after switching back to GPT-5.5, the watcher sends the final `繼續` unless `-NoFinalResume` is explicitly passed.

## 0.1.6

- Renames local `$matches` arrays to avoid PowerShell's automatic `$Matches` hashtable after regex `-match`, fixing repeated hashtable-add errors.

## 0.1.5

- Fixes a PowerShell hashtable/property-name collision that could log `A hash table can only be added to another hash table` before recovery started.

## 0.1.4

- Changes the default recovery finish to switch back to GPT-5.5 without sending final `繼續`, preventing immediate re-compact loops.
- Adds `-FinalResume` for users who explicitly want the previous auto-resume behavior.

## 0.1.3

- Marks all currently visible compacting status triggers after a recovery, preventing loops caused by multiple stale status lines on screen.

## 0.1.2

- Prevents repeated recovery loops when the same visible compacting status remains on screen after a successful round.
- Tracks visible status triggers by UI runtime id and releases them when they disappear.

## 0.1.1

- Fixes repeat-round detection by caching only compact error triggers.
- Keeps active compacting status triggers eligible for future recovery rounds.

## 0.1.0

- Initial public release.
- Detects active compacting status and compact endpoint failures.
- Switches GPT-5.5 to GPT-5.4-Mini for context compact recovery.
- Watches for a newly visible compact completion marker before switching back to GPT-5.5.
- Avoids changing speed/reasoning settings when returning to GPT-5.5.
- Adds round cooldown and duplicate trigger suppression.
