# TimeTug audit remediation results

Date: 2026-09-27. Branch: `codex/timetug-audit-remediation`. This file is a running verification record; final check counts and commit will be filled after all edits settle.

| Task | Area | Current evidence |
|---|---|---|
| 1 | Credential lifecycle | Implemented. Connector and Apple tests passed in focused runs. DeepSeek found a provider reauthorization recovery issue, fixed with a regression test. |
| 2 | Refresh ordering | Implemented. Deterministic stale-refresh test passed. |
| 3 | Timezone context | Implemented. Core tests passed; new DST/in-flight test awaits integrated run. |
| 4 | Startup acknowledgement | Implemented with per-source app tests; integrated app run pending. |
| 5 | Join URL safety | Implemented; focused connector policy test passed. Integrated app run pending. |
| 6 | Widget horizon | Implemented; Core 281/281 passed before concurrent inference edits. |
| 7-8 | Inference identity, bounds and retries | Implemented; Core 296/296 and inference 13/13 passed in focused final-agent runs. DeepSeek Core/app review pending. |
| 9-10 | Scoped refresh and provider concurrency | Implemented; Core 294/294, Connectors 185/185 and Bridge 12/12 passed after source changes. Final integrated run pending. |
| 11 | Dedup performance | Frozen oracle and benchmark harness added; baseline measurement and optimization in progress. |
| 12 | OAuth listener | Implemented; DeepSeek found two additional lifecycle defects. Both fixed; CalendarApple 30/30 passed. |
| 13 | UI ticks | Implemented with policy tests; integrated app run passed 230/230 before the final OAuth fixes. |
| 14 | Microsoft series split | Implemented; DeepSeek found a pre-write serialization ordering defect, fixed; Connectors 185/185 passed afterward. |
| 15-19 | CI, website, agent verification | Implemented; DeepSeek found six applicable issues and one shipped-Google-scope false positive. Release-tools wrapper 12 passed after fixes. Final integrated check pending. |
| 20 | Final verification and measurements | Pending. |

Finding 7 (Microsoft write access) was resolved after this run by the owner's decision: Microsoft sign-in requests read-only scopes (ADR 0017, PR #49). The library's write code and capabilities are unchanged. No live calendar write tests, deployment or production IAM/headers checks have been run. Linux CI enforcement remains pending a successful same-code run.

## Measurements to fill from final evidence

- Complete `verify.sh all` run: pending.
- Release-mode dedup benchmark before/after (synthetic only): pending.
- Provider request count and peak concurrency: pending integrated evidence.
- Idle UI structural rebuilds: prior one-second timer rebuilt every second (3,600 times per idle hour); new policy should be measured in a controlled test before reporting an after count.
- Startup instruction words/estimated tokens: pending.
- Agent token/tool-call/review-pass counts: unavailable unless captured from session evidence; no estimate will be presented as measured.

Root `AGENTS.md` changed from 2,100 words / 16,980 bytes at baseline to 370 words / 3,127 bytes in the current working tree. Detailed operational instructions moved to linked runbooks; this is a startup-reading reduction, not a measured agent-token or wall-time saving.
