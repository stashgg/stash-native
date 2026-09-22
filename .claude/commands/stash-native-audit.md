---
description: Audit the iOS, Android, macOS, and Windows SDKs and samples with evidence, findings, and quality/health scores; optionally fix confirmed findings.
---

Read [AGENTS.md](../../AGENTS.md), then execute the shared [stash-native-audit skill](../../.agents/skills/stash-native-audit/SKILL.md).

Forward the user's arguments unchanged: `$ARGUMENTS`.

No arguments means `audit` (report only). `status` summarizes existing results; `fix` follows the explicitly requested remediation scope. Resolve skill references relative to the shared skill directory, not this command directory.
