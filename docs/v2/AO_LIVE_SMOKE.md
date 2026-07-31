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

The default probe calls AO health and readiness, reads the served OpenAPI
version, and lists projects. OpenMac accepts only a loopback daemon URL.

The in-app connection screen also attempts to discover the current upstream
daemon through `~/.ao/running.json`. Discovery accepts only a regular file
owned by the current user that is not group- or world-writable, does not follow
a symbolic link, bounds the file size, validates the recorded PID is live, and
constructs the URL from the recorded port using `127.0.0.1`. The subsequent
health and readiness requests must identify the AO daemon and report the same
PID; a discovered connection must also match the run-file PID. OpenMac does not
read the served OpenAPI contract until both probes pass, and accepts it only
when the version and every project/session operation used by the adapter are
present. A missing or rejected run file never causes a remote connection; users
can still enter a loopback URL manually.

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

- The upstream `running.json` shape and CLI daemon-identity check were captured
  for secure local discovery without persisting the optional browser runtime
  token.
- `/healthz`, `/readyz`, served OpenAPI `0.1.0-route-shell`, and project
  discovery passed on an isolated daemon at `127.0.0.1:33001`.
- AO project registration against a disposable Git repository passed.
- Session spawn stopped at AO's own preflight because `tmux` was not installed;
  no session was created.
- The current AO session response deliberately omits the absolute worktree path.
  OpenMac therefore continues to reject local Xcode verification for AO
  sessions instead of running commands in the original repository.

The CLI probe sequence and identity checks were also re-audited at upstream
revision `25c9c96b74b57a9c0d4c0c4efb468eb4847ef74b`. It still checks
`/healthz` before `/readyz` and requires both responses to identify the
run-file process.

This record is evidence of live protocol compatibility, not completion of
VS-07 or Gate B. Those still require an isolated session, verifiable workspace
identity, Xcode evidence, PR facts, and observed user sessions.
