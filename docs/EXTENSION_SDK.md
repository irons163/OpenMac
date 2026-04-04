# OpenMac Extension SDK v2

OpenMac extensions are local folders with `plugin.json` + executable entrypoint.

## Quick Start

```bash
./tools/openmac-plugin-init.sh com.example.my-plugin ~/Desktop "My Plugin"
```

Then install in app:
- `Extensions > Marketplace...`
- `Install / Update from Folder...` (or `Install from Remote`)

Default extension folder:

`~/Library/Application Support/OpenMac/Plugins`

## Manifest (`plugin.json`)

```json
{
  "id": "com.example.my-plugin",
  "name": "My Plugin",
  "version": "0.1.0",
  "channel": "stable",
  "minOpenMacVersion": "1.0.0",
  "dependencies": ["com.example.shared-utils"],
  "summary": "Optional description",
  "capabilities": ["pm.plan.generate"],
  "permissions": ["command.execute"],
  "entrypoint": "./run.sh",
  "commands": [
    {
      "id": "health-check",
      "title": "Health Check",
      "subtitle": "Optional",
      "slots": ["app.toolbar", "pm.planner.panel"],
      "permissions": ["command.execute"],
      "timeoutSeconds": 30,
      "enabled": true
    }
  ],
  "eventHooks": [
    { "event": "ticket.created", "commandID": "health-check", "enabled": true }
  ],
  "uiExtensions": [
    {
      "id": "brainstorm",
      "slot": "pm.planner",
      "title": "Brainstorm Extension",
      "component": "form.v1",
      "priority": 10,
      "enabled": true
    }
  ],
  "enabled": true
}
```

## Command Contribution Slots

- `app.toolbar`: shown under top toolbar `Extensions` menu
- `task.card`: shown on each Kanban task card
- `pm.planner.panel`: shown inside PM Planner sheet
- `kanban.toolbar`: shown in Kanban extension menu section
- `kanban.sidebar`: shown in Kanban extension menu section
- `marketplace.panel`: shown in Extension Marketplace panel

Alias values are normalized by OpenMac (for compatibility), but use the canonical values above.

## Runtime Safety Rules

- Commands support timeout (`timeoutSeconds`, max enforced by app).
- If permissions are declared and `command.execute` is missing, OpenMac blocks command execution.
- If permissions are not declared, OpenMac runs in compatibility mode and logs a warning.
- Marketplace includes an activity log for install/run success/failure debugging.
- Marketplace supports saved install sources and extension enable/disable toggles.
- Marketplace supports install by plugin ID, preferred update channel (`stable`/`beta`/`alpha`), and per-plugin version locks.
- Marketplace includes a one-click E2E acceptance run with copyable report output.
- Event hooks can auto-run extension commands on lifecycle events (`ticket.created`, `run.finished`, `review.entered`).
- Hook execution is queued with dedupe + retry/backoff so rapid repeated events do not flood extensions.

## Runtime Contract

### PM Plan generation request

OpenMac writes request JSON to `stdin`.

Expected response on `stdout`:

```json
{
  "projectName": "Project",
  "summary": "Plan summary",
  "tickets": []
}
```

### Command contribution request

Expected response on `stdout`:

```json
{"message": "Command completed"}
```

OpenMac also sends optional selected task context when running from task card slot.
For planner-host actions, OpenMac also sends `extensionInputs` (field values collected from extension UI).
