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
present. Before using that cached compatibility result, each project or session
operation rechecks the lightweight daemon probes. A changed PID must pass the
full OpenAPI probe again for a manually entered URL. A discovered connection
rejects a changed PID and requires discovery to run again against the updated
run file. Concurrent project or session operations share an in-flight identity
probe so parallel reconciliation does not multiply health traffic. Concurrent
first operations also share the full health, readiness, and OpenAPI
compatibility probe. A failed shared full or identity probe is discarded,
allowing a later operation to rerun the full compatibility check after the
daemon recovers. A missing or rejected run file never causes a remote
connection; users can still enter a loopback URL manually.

Session start also fails closed unless the approved request requires
workspace-scoped read/write permission; unknown or full-machine permission
scopes never reach the AO daemon.
When resuming an existing session, OpenMac also revalidates the session ID,
project ID, stable idempotency branch, worker kind, harness, and creation time;
malformed identity is treated as a conflict and never as a successful receipt.
Stopping an already terminal session returns `alreadyTerminal` without sending
another kill request; a non-terminal kill acknowledgement remains distinct from
the later terminal facts.
Session and project identifiers are validated as single safe URL path
components before any request, so separators and dot segments cannot redirect
an adapter call to another AO route.

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

## Opt-in AO workspace + Xcode verifier probe

When the disposable AO project contains a Swift package, the same script can
exercise the full workspace identity handoff and the real `XcodeVerifier`:

```bash
tools/test-agent-orchestrator-live.sh \
  --url http://127.0.0.1:3001 \
  --start-project openmac-ao-fixture \
  --harness fake \
  --base-branch main \
  --base-commit "$(git -C /Volumes/M2SSD/openmac-ao-fixture rev-parse HEAD)" \
  --xcode-repository-root /Volumes/M2SSD/openmac-ao-fixture \
  --xcode-workspace-root /Users/phil/.ao/data/worktrees/openmac-ao-fixture \
  --xcode-scheme OpenMacAOFixture
```

This opt-in test creates a fresh AO session, obtains the backend-confirmed
`verificationWorkspaceURL` and branch, checks Git common-directory and
`Package.swift` identity, runs a real `xcodebuild` build, persists the
`.xcresult` record, and stops the session. It uses the disposable fixture at
`/Volumes/M2SSD/openmac-ao-fixture` (commit `529f574`); it does not contact a
real coding agent or create a PR. The separate PR facts probe below covers the
read-only provider path.

## Opt-in live PR facts probe

AO can claim an existing public GitHub PR for a disposable worker session and
return the provider's current PR, CI, and review facts. The OpenMac smoke uses
that official claim endpoint only as test setup, then reads the session through
the OpenMac adapter:

```bash
tools/test-agent-orchestrator-live.sh \
  --url http://127.0.0.1:3001 \
  --start-project openmac-ao-pr-e2e \
  --harness fake \
  --base-branch main \
  --base-commit 9159a0206a2e1d2a99333118bf9ebc5590b7404f \
  --pr-url https://github.com/Untrivial-ai/agent-orchestrator/pull/3451
```

This is read-only with respect to GitHub: it does not create, edit, merge, or
close a PR. The disposable project must point at the same GitHub repository,
and the AO daemon must have read access to provider facts. The test asserts the
PR URL, open state, passing CI, and required-review state after the adapter
maps the live session snapshot.

The persistent disposable PR fixture is `/Volumes/M2SSD/openmac-ao-pr-fixture`
at upstream revision `9159a020`; AO registers it as project
`openmac-ao-pr-e2e`. The fixture and registration are local test state, not
part of the OpenMac source repository.

## Opt-in live 3-task E2E

The technical VS-12 smoke composes an approved typed three-task DAG, reserves
two root attempts at once, starts those two real AO sessions concurrently,
starts the dependent join only after the roots are recorded as succeeded, runs
the real Xcode verifier in all three backend-confirmed workspaces, claims the
same public PR on the join session, reconciles AO facts, and writes the
identification-free funnel export. It is deliberately opt-in and uses the
fake AO harness; it does not invoke a coding agent or mutate GitHub:

```bash
tools/test-agent-orchestrator-live.sh \
  --url http://127.0.0.1:3001 \
  --e2e \
  --start-project openmac-ao-fixture \
  --harness fake \
  --base-branch main \
  --base-commit "$(git -C /Volumes/M2SSD/openmac-ao-fixture rev-parse HEAD)" \
  --xcode-repository-root /Volumes/M2SSD/openmac-ao-fixture \
  --xcode-workspace-root /Users/phil/.ao/data/worktrees/openmac-ao-fixture \
  --xcode-scheme OpenMacAOFixture \
  --pr-url https://github.com/Untrivial-ai/agent-orchestrator/pull/3451
```

The current AO project summary does not report a permission scope, so the
production `DeliveryDispatcher` intentionally stops before reserving a live
session (`unknown` permission is fail-closed). This smoke therefore exercises
the approved store reservations plus the real AO backend directly; the
dispatcher preflight and parallel execution contract remain covered by the
deterministic suite until AO exposes that permission fact. The command prints
the temporary `ao-live-e2e-funnel.json` export before cleanup.

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
  That response is not sufficient for local Xcode verification, and OpenMac
  never falls back to running commands in the original repository. The
  follow-up workspace probe below uses a separate, official AO endpoint when
  the served contract exposes it.

The CLI probe sequence and identity checks were also re-audited at upstream
revision `25c9c96b74b57a9c0d4c0c4efb468eb4847ef74b`. It still checks
`/healthz` before `/readyz` and requires both responses to identify the
run-file process.

## Backend-confirmed verification workspace probe

AO's `SessionView` still intentionally omits an absolute worktree path. For a
served contract that supports it, OpenMac resolves the path through AO's
official shell-terminal API instead of reading AO's private database or
guessing from the original repository:

1. `POST /api/v1/shell-terminals` with the requested `projectId` and
   `sessionId`.
2. Validate the returned `shellTerminal.handleId`, `projectId`, `sessionId`,
   and absolute `workingDir`.
3. `DELETE /api/v1/shell-terminals/{handleId}` immediately; the temporary
   terminal is not used to execute a command.
4. Store the normalized `workingDir` as the start receipt's
   `verificationWorkspaceURL`.

The compatibility probe requires both shell-terminal operations when this
identity resolution is enabled. A missing operation, mismatched identity,
unsafe handle, non-absolute path, or failed cleanup fails closed. The older
captured fixture intentionally keeps the pre-endpoint contract; a dedicated
adapter test and the opt-in live smoke cover the shell-terminal response.

## Live verification completed on 2026-08-02

- Homebrew `tmux 3.7b` was installed and detected by `ao doctor`.
- The official AO desktop daemon was running on `127.0.0.1:3001`; health,
  readiness, served API compatibility, and project discovery passed.
- An explicit smoke run against disposable project `openmac-ao-fixture` with
  the deterministic `fake` harness created an isolated session, read facts,
  and received a stop acknowledgement. The OpenMac test verified request,
  execution, branch, and stop identities; no production repository or real
  coding-agent session was used.
- Direct inspection of the same daemon showed that a session response still
  omits an absolute worktree path. `/workspace/files` exposes file metadata and
  `/preview` exposes a preview URL, but neither is a backend-confirmed Xcode
  workspace identity. The official shell-terminal probe now supplies that
  identity without exposing AO's internal session metadata.
- A follow-up audit of the latest upstream `main` at
  [`9159a020`](https://github.com/Untrivial-ai/agent-orchestrator/tree/9159a0206a2e1d2a99333118bf9ebc5590b7404f)
  found the same boundary: `ControllersSessionView` still omits
  `workspacePath`/`workspaceRepoPath`; the new workspace-files response only
  returns session-relative file metadata. The upstream `/preview` route is a
  browser-preview URL, not an AO dashboard/session deep-link.
- The AO desktop was quit gracefully and reopened; the old daemon PID `8874`
  became stale, the new PID `11085` reached ready state, and the read-only
  compatibility smoke passed again with exit code 0.
- No AO session remains running after the smoke; AO reports only hidden
  terminated records in the session list.
- The live start receipt contained a file URL under AO's managed
  `/.ao/data/worktrees/openmac-ao-fixture/` root, and the temporary shell
  terminal was released; no shell terminals remained after the smoke.
- The opt-in workspace verifier smoke then ran `xcodebuild -scheme
  OpenMacAOFixture ... build` inside that AO worktree, produced a passing
  `.xcresult`, and stopped the session; the fixture's Git common-directory and
  branch identities matched the AO receipt.
- The opt-in PR facts smoke claimed public GitHub PR `Untrivial-ai/agent-orchestrator#3451`
  through AO's official session claim endpoint, then read it through the
  OpenMac adapter; URL, open state, passing CI, and required-review facts were
  mapped to the same execution identity and the session was stopped.
- The opt-in technical VS-12 E2E smoke composed a typed three-task DAG, reserved
  and started two root sessions concurrently, started the dependent join,
  verified all three backend-confirmed workspaces with real `xcodebuild`,
  reconciled PR facts on the join, and exported a privacy-filtered funnel report:
  3 tasks, 3 sessions, 3 verified tasks, 5 passed evidence facts, and 1 PR. It
  uses approved store reservations plus the real AO backend directly because the
  current AO project summary omits permission scope; production dispatcher
  preflight remains fail-closed until AO exposes that fact.
- The installed AO desktop `0.11.2` currently exposes only the daemon listener
  at `127.0.0.1:3001`; nothing listens on the documented dashboard port `3000`,
  the daemon root and `/preview` are not dashboard routes, and the app bundle
  declares no external URL scheme. OpenMac therefore leaves VS-08's dashboard
  deep-link pending instead of guessing an `ao://` or browser URL.

This completes the live session and daemon-restart prerequisite for VS-07/VS-08,
the backend-confirmed workspace identity, real AO workspace/Xcode-build, and
live PR-facts prerequisites for VS-09, plus the technical VS-12 3-task E2E.
Control
Center now reloads and reconciles when its macOS scene becomes active;
the deterministic restart test passes without replaying facts. The packaged
test.2 archive also passed `tools/test-packaged-app-restart.sh` (launch,
terminate, relaunch, terminate). The dashboard route helper is configurable and
fail-closed, but VS-08 still needs a real AO HTML dashboard route to verify.
PR creation, push, merge, and review mutation were not performed by the smoke.
The clean Mac Gatekeeper and participant/concierge gates remain
intentionally deferred.
