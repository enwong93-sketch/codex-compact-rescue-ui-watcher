# Changelog

## 0.1.0

- Initial public release.
- Detects active compacting status and compact endpoint failures.
- Switches GPT-5.5 to GPT-5.4-Mini for context compact recovery.
- Watches for a newly visible compact completion marker before switching back to GPT-5.5.
- Avoids changing speed/reasoning settings when returning to GPT-5.5.
- Adds round cooldown and duplicate trigger suppression.
