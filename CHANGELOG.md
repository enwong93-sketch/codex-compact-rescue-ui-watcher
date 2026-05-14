# Changelog

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
