# Agent Orchestrator Live Smoke

This opt-in check runs the OpenMac Swift adapter against an already-running
Agent Orchestrator daemon. It never starts or installs AO, and it never installs
AO runtime prerequisites.

## Read-only compatibility probe

Start the AO desktop app or daemon, then run:

```bash
tools/test-agent-orchestrator-live.sh \
  --url http://127.0.0.1:3001
```

The default probe calls AO health, reads the served OpenAPI version, and lists
projects. OpenMac accepts only a loopback daemon URL.

## Explicit isolated-session probe

Starting a session is opt-in because it creates an AO-managed worktree and
runtime. Use a disposable registered project when possible:

```bash
tools/test-agent-orchestrator-live.sh \
  --url http://127.0.0.1:3001 \
  --start-project PROJECT_ID \
  --harness fake \
  --base-branch main \
  --base-commit COMMIT_SHA
```

The test sends a kill request after reading the first facts. AO intentionally
preserves worktrees it considers dirty, so inspect AO after the run. The `fake`
harness is deterministic and LLM-free, but the daemon must have been launched
with `AO_FAKE_HARNESS=1`. On macOS and Linux, current AO session runtime also
requires `tmux`; install and trust that dependency separately rather than
letting OpenMac mutate the system.

## Current compatibility record

On 2026-07-31, OpenMac was checked against upstream revision
`b58bae51bac08c9e48bded4c636e504863a93c21`:

- `/healthz`, `/readyz`, served OpenAPI `0.1.0-route-shell`, and project
  discovery passed on an isolated daemon at `127.0.0.1:33001`.
- AO project registration against a disposable Git repository passed.
- Session spawn stopped at AO's own preflight because `tmux` was not installed;
  no session was created.
- The current AO session response deliberately omits the absolute worktree path.
  OpenMac therefore continues to reject local Xcode verification for AO
  sessions instead of running commands in the original repository.

This record is evidence of live protocol compatibility, not completion of
VS-07 or Gate B. Those still require an isolated session, verifiable workspace
identity, Xcode evidence, PR facts, and observed user sessions.
