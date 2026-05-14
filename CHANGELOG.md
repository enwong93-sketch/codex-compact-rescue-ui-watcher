# Changelog

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
