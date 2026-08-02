# Agent Orchestrator contract fixtures

Sanitized wire fixtures captured from the public HTTP contract at upstream
revision `9caafbee89383c9bf7e904936eb88c48add2fa88` on 2026-07-31.

The covered surface is deliberately limited to:

- `GET /healthz`
- `GET /readyz`
- `GET /api/v1/openapi.yaml`
- `GET /api/v1/projects`
- `GET /api/v1/projects/{id}`
- `GET|POST /api/v1/sessions`
- `GET /api/v1/sessions/{id}`
- `GET /api/v1/sessions/{id}/workspace/files`
- `POST /api/v1/sessions/{id}/kill`

These captured fixtures predate the shell-terminal workspace identity probe and
therefore intentionally do not list `POST /api/v1/shell-terminals` or its
`DELETE /api/v1/shell-terminals/{handleId}` cleanup route. The dedicated adapter
contract test and opt-in live smoke supply that newer response shape.

The session variants also cover unchanged polling snapshots, an unknown future
status, and an explicitly terminated session so the adapter must fail closed.
The served OpenAPI fixture lists every operation the adapter requires; health
degrades before project or session calls when a compatible version omits one.

Paths, repository URLs, process IDs, session IDs, timestamps, and task content
are test-only substitutions. Field names, envelopes, enums, and required
relationships follow the upstream Go DTOs and served OpenAPI document.
