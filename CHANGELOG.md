# Changelog

## 0.1.22

- Narrows model-button detection so sidebar buttons such as `Codex mobile` are not mistaken for the model dropdown.
- Keeps recovery from `5.3-Codex-Spark` by matching model-like prefixes such as `5.3-`, `5.4-`, `5.5`, `GPT-`, `gpt-`, and `o*`.

## 0.1.21

- Recovers after accidental switches to models such as `5.3-Codex-Spark` by broadening model-button detection beyond only GPT-5.5/GPT-5.4 labels.
- Changes GPT-5.4-Mini recovery to use exact menu-item selection first and removes the GPT-5.4-Mini anchored coordinate fallback that could select another model.
- Limits menu-item scanning to top-level popup/menu windows instead of root desktop descendants.

## 0.1.20

- Removes the UIA menu-scan mouse path from automatic model switching. The watcher now uses keyboard-first switching with anchored-click fallback for both GPT-5.4-Mini and GPT-5.5.
- Fixes hangs where the watcher clicked the model menu and then stopped before sending any keyboard navigation.

## 0.1.19

- Fixes a model-menu stall introduced by exact model selection: after opening the Codex model menu, the watcher now scans only visible `MenuItem` controls instead of walking the full desktop UI tree.
- Applies the same narrow visible-menu scan to model-menu verification and retry checks, reducing hangs when Chrome, AIRI, or multiple Codex windows are open.

## 0.1.18

- Adds `/goal` support after the final GPT-5.5 resume: if a visible goal-paused row appears, the watcher clicks the row's resume/play control instead of sending another text `繼續`.
- Adds `-NoGoalResume` and `-GoalResumeWaitSeconds` for disabling or tuning goal resume detection.
- Reduces accidental GPT-5.2 switches by preferring exact `GPT-5.4-Mini` menu-item selection and by requiring coordinate fallbacks to confirm the target model before returning success.

## 0.1.17

- Removes the automatic second `繼續` after switching to GPT-5.4-Mini.
- Keeps the lower-composer focus fix, but confirmation now only logs if the first send was not visibly confirmed.

## 0.1.16

- Fixes resume text being sent to the wrong place after switching to GPT-5.4-Mini.
- Restricts composer detection to the lower part of the target Codex window and removes the overly broad `Message` match that could select old chat content.
- Adds a bottom-input fallback click before sending the first compact resume.

## 0.1.15

- Starts model-switch attempts before doing a current-model precheck, so retry logging begins even when Codex is busy.
- Narrows model-button lookup to visible buttons instead of scanning every descendant node, reducing UI Automation stalls during compact recovery.
- Removes the keyboard switcher's dependency on reading the current reasoning level before navigating the model menu.

## 0.1.14

- Retries switching to GPT-5.4-Mini up to 5 times, using keyboard, anchored-click, and mouse fallback paths on each attempt.
- Adds `-ModelSwitchAttempts` so slow UI or network lag during model switching does not abort the recovery after one failed attempt.

## 0.1.13

- Scans all visible Codex desktop windows for compact triggers instead of only the first `Codex*` window.
- Locks recovery actions to the window where the compact trigger was found, so multi-window Codex sessions can be watched by one watcher.

## 0.1.12

- Retries Windows clipboard writes when sending `繼續`, fixing intermittent `Clipboard.SetText` failures.
- Falls back to typing ASCII `continue` if the clipboard remains unavailable, so recovery does not get stuck on GPT-5.4-Mini.

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
