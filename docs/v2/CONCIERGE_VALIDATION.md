# OpenMac 0.1.0 test.2 Concierge Validation（延後）

> 範圍決策（2026-08-02）：本輪跳過受測者／concierge 驗證。本文件保留給未來 validation window，3–5 場觀察測試不列入本輪完成門檻。

This runbook turns the invited build into evidence for a go, narrow, or stop
decision. It is for 3–5 observed sessions before any further product expansion;
that validation is intentionally deferred in the current scope.

## What this test must answer

The primary question is not whether participants like the interface:

> Does an Apple developer who already coordinates multiple coding-agent
> sessions get enough value from an approval-and-evidence delivery layer to use
> it again on a real task?

Record friction without fixing it during the session. Do not add another
backend, dashboard, marketplace, or automation based on a single interview.

## Participant screener

A participant qualifies only when all of these are true:

- They actively maintain an iOS, macOS, watchOS, tvOS, or Swift package
  repository.
- They run at least three coding-agent sessions in a typical week.
- They have coordinated two or more related coding tasks manually in the last
  month.
- They can use a clean Git repository for the deterministic fixture walkthrough.

Prefer a mix of independent developers and engineers working in small Apple
teams. Record only a participant code such as `P01`; do not put names, employer
names, repository paths, source code, prompts, or logs in the validation notes.

Suggested screener:

1. What Apple platforms do you actively ship?
2. How many coding-agent sessions do you run in a typical week?
3. When two sessions touch related work, how do you coordinate order and review?
4. What most often prevents an agent result from being ready to merge?
5. Would you try a 30-minute local test using a clean Git repository?

## Invitation template

> I am testing a local macOS workflow for Apple developers who already run
> several coding-agent sessions. It turns one feature brief into an approved
> dependency plan, tracks isolated execution, and requires build/test evidence
> before “Ready to Merge.” This is a 30-minute observed test, not a sales demo.
> The build is ad-hoc signed and not notarized. You may use a disposable or
> non-sensitive clean Git repository, and you will not be asked to share source
> code or logs. Would you be willing to try it once and tell me where it fails?

## Build handoff

Send these two files together:

- `OpenMac-0.1.0-test.2-macOS.zip`
- `OpenMac-0.1.0-test.2-macOS.zip.sha256`

Expected SHA-256:

```text
6768da6ccdcdd69a312761b6148ebb30f3bf33f4c0aa8eab2b70a4a38f535439
```

Ask the participant to follow the included `INSTALL.md`. State before the
session that the build is ad-hoc signed, has a hardened runtime, is not
notarized, and must not be used with sensitive repositories.

AO is optional. If the participant already runs the AO desktop app or daemon,
they may try **Discover Running AO** and the read-only compatibility probe. Do
not install AO, `tmux`, or other prerequisites during the session, and do not
represent AO connection success as live dispatch.

## Thirty-minute session

### 0–3 minutes: establish the current workflow

Ask the participant to describe the last feature that required multiple coding
sessions. Capture their existing coordination steps and the point where they
decide work is safe to merge.

### 3–8 minutes: installation

Send the build and remain silent unless Gatekeeper prevents progress. Record:

- whether checksum verification was attempted without prompting;
- time from download to first launch;
- every warning or instruction that caused hesitation;
- whether the participant understood the ad-hoc/not-notarized boundary.

### 8–20 minutes: fixture core loop

Give only this task:

> Use the fixture to turn a brief into an approved plan, run it, and decide when
> the work is ready to merge.

The participant should discover these steps from the product:

1. Open **Delivery → Open Plan Review**.
2. Create a fixture review against a clean Git repository.
3. Inspect or edit the three-task plan and approve it.
4. Open **Delivery → Open Delivery Control Center**.
5. Run the fixture until it reaches **Ready to Merge**.
6. Explain what evidence made that state trustworthy.

Do not guide them for the first five minutes. If they become blocked, ask
“What would you expect to do next?” before giving the smallest possible hint.

### 20–24 minutes: optional AO discovery

Only when AO is already running:

1. Open **Delivery → Agent Orchestrator Connection…**.
2. Observe whether the daemon is discovered without a port being supplied.
3. Connect and read the project list.
4. Ask the participant what they believe is enabled after connection.

The correct boundary is that compatibility and project discovery passed; live
dispatch and isolated verification are still unavailable.

### 24–30 minutes: debrief

Ask:

1. Where did this save work compared with your current process?
2. Which step felt like ceremony without value?
3. Would you trust **Ready to Merge**? Why or why not?
4. Would you use this on your next real multi-session task?
5. Is direct AO/Codex usage simpler for you?
6. What would make you pay, sponsor development, or join a paid pilot?

Do not ask “What features should be added?” Ask what outcome was missing.

## Session record

Copy this block once per participant:

```text
Participant code:
Date/time:
Apple platform:
Coding-agent sessions per week:
Existing coordination method:

Checksum attempted without prompt: yes / no
Reached first launch: yes / no
Install duration:
Completed fixture loop: yes / no
Brief-to-approved duration:
Brief-to-running duration:
Reached Ready to Merge: yes / no
Could explain required evidence: yes / no
Hints required:
Plan edits: none / minor / major
Largest blocker:
Most valuable moment:
Approval/evidence felt valuable: yes / no / mixed
Direct AO/Codex felt simpler: yes / no / mixed
Would use on next task: yes / no / uncertain
Seven-day repeat completed: yes / no / pending
Paid pilot interest: yes / no / uncertain
Observer notes (no source, paths, prompts, logs, or personal data):
```

“Major” plan editing means the participant rewrote task boundaries or
dependencies, not merely wording.

## Decision after 3–5 sessions

Continue only if at least three participants complete the fixture loop, can
explain why **Ready to Merge** is trustworthy, and at least two say they would
use it on their next task. Treat these as early directional signals, not the
full seven-day Go threshold.

Narrow or stop when any of these dominate:

- participants prefer direct AO/Codex because the approval layer adds no value;
- more than half require major plan rewrites;
- evidence is perceived as ceremony rather than risk reduction;
- users cannot identify the next action without observer help;
- installation trust prevents the test from reaching the core loop.

After each session, fix only blockers that prevent observing the hypothesis.
Do not broaden scope until the seven-day repeat-use metrics in
`PRODUCT_SPEC.md` are measured.
