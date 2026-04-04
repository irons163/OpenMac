# OpenMac PM Plugin API v1

OpenMac supports pluggable PM planning so new planning features can ship outside the core app.

## Plugin folder layout

OpenMac scans this folder by default:

`~/Library/Application Support/OpenMac/Plugins`

Each plugin should live in its own subfolder:

```text
Plugins/
  your-plugin/
    plugin.json
    run.sh
```

## `plugin.json`

```json
{
  "id": "com.example.brainstormer",
  "name": "Example Brainstormer",
  "minOpenMacVersion": "1.0.0",
  "capabilities": ["pm.plan.generate"],
  "permissions": ["command.execute"],
  "commands": [
    {
      "id": "health-check",
      "title": "Health Check",
      "slots": ["app.toolbar", "pm.planner.panel"],
      "permissions": ["command.execute"],
      "timeoutSeconds": 30,
      "enabled": true
    }
  ],
  "eventHooks": [
    { "id": "on-ticket-created", "event": "ticket.created", "commandID": "health-check", "enabled": true },
    { "id": "on-run-finished", "event": "run.finished", "commandID": "health-check", "enabled": true }
  ],
  "uiExtensions": [
    {
      "id": "brainstorm",
      "slot": "pm.planner",
      "title": "Brainstorm Extension",
      "subtitle": "Run brainstorm rounds and fold results into project brief.",
      "component": "brainstorm.v1",
      "ui": {
        "fields": [
          { "id": "focus", "type": "focus.input", "placeholder": "Brainstorm focus (optional)" },
          { "id": "status", "type": "status.text" },
          { "id": "transcript", "type": "transcript.output", "minHeight": 130, "maxHeight": 220 }
        ],
        "actions": [
          { "id": "pm.brainstorm.run", "title": "Run Brainstorm Round" },
          { "id": "pm.brainstorm.apply", "title": "Apply Brainstorm to Brief" },
          { "id": "pm.brainstorm.apply.generate", "title": "Apply + Generate" },
          { "id": "command:health-check", "title": "Run Health Check", "commandID": "health-check" },
          { "id": "pm.brainstorm.clear", "title": "Clear Brainstorm" }
        ]
      },
      "priority": 100,
      "enabled": true
    }
  ],
  "entrypoint": "./run.sh",
  "enabled": true
}
```

Required:
- `id` (string)
- `name` (string)
- `capabilities` includes `pm.plan.generate`
- `entrypoint` (path to executable command/script)

Optional:
- `enabled` (boolean, default `true`)
- `minOpenMacVersion` / `maxOpenMacVersion` (string, optional): compatibility guard checked on install.
- `permissions` (string array): extension-level permissions. If command-level permissions are absent, OpenMac uses this as fallback.
- `commands` (array): command contributions rendered in OpenMac UI contribution points.
- `eventHooks` (array): auto-run command hooks for planner/runtime lifecycle events.
- `uiExtensions` (array): declares PM extension UI cards that OpenMac can render.

## `uiExtensions` fields

- `id` (string, required): stable extension id under this plugin.
- `slot` (string, required): where to render it. Current supported slot: `pm.planner`.
- `title` (string, optional): card title.
- `subtitle` (string, optional): helper text under title.
- `component` (string, required): UI component type.
  - Current supported values: `brainstorm.v1`, `form.v1`
- `ui` (object, optional): manifest-driven UI schema for this card.
  - `fields` (array, optional):
    - `id` (string, optional)
    - `type` (string, required): supported `focus.input`, `status.text`, `transcript.output`, `text.input`, `multiline.input`
    - `label` (string, optional)
    - `placeholder` (string, optional)
    - `minHeight` / `maxHeight` (number, optional, mainly for multiline output)
    - `enabled` (boolean, optional, default `true`)
  - `actions` (array, optional):
    - `id` (string, required): supports built-ins (`pm.brainstorm.run`, `pm.brainstorm.apply`, `pm.brainstorm.apply.generate`, `pm.brainstorm.apply.create`, `pm.brainstorm.clear`) and command routing (`command:<command-id>` or `pm.command.<command-id>`)
    - `commandID` (string, optional): explicit command contribution id to execute for this action
    - `title` (string, optional)
    - `enabled` (boolean, optional, default `true`)
- `priority` (number, optional, default `0`): higher renders earlier.
- `enabled` (boolean, optional, default `true`).

If no local `brainstorm.v1` extension is found, OpenMac inserts a built-in brainstorm extension as fallback.

## `commands` fields

- `id` (string, required)
- `title` (string, optional)
- `subtitle` (string, optional)
- `slots` (string array, optional): canonical slots:
  - `app.toolbar`
  - `task.card`
  - `pm.planner.panel`
- `permissions` (string array, optional): include `command.execute` to allow execution when permissions are declared.
- `timeoutSeconds` (number, optional): command timeout in seconds.
- `entrypoint` (string, optional): override plugin-level entrypoint for this command.
- `enabled` (boolean, optional, default `true`)

## `eventHooks` fields

- `id` (string, optional)
- `event` (string, required): `ticket.created`, `run.finished`, `review.entered`
- `commandID` (string, required): command contribution id to execute
- `enabled` (boolean, optional, default `true`)

## Runtime contract

OpenMac executes the entrypoint and sends one JSON payload to `stdin`.

### Request (`stdin`)

```json
{
  "projectName": "YouBike",
  "projectBrief": "Build a cross-platform app...",
  "extensionInputs": { "focus": "commuter reliability" },
  "availableAgents": [
    { "name": "A", "skills": ["swiftui", "planning"], "maxConcurrentTasks": 2 }
  ]
}
```

### Response (`stdout`)

```json
{
  "projectName": "YouBike",
  "summary": "Plugin-generated PM plan...",
  "tickets": [
    {
      "title": "YouBike · Scope",
      "details": "Acceptance:\nDepends on: none\n- ...",
      "requiredSkills": ["planning"],
      "storyPoints": 2,
      "epic": "Planning",
      "milestone": "M1 Scope Locked"
    }
  ]
}
```

If output is invalid or empty, OpenMac will fallback to built-in planning.

## Notes

- Entry scripts should write only JSON to stdout for best parsing reliability.
- OpenMac enforces a command timeout (current default: 45 seconds).
- Use the PM Planner "Planning Engine" selector to switch between built-in and plugin-preferred mode.

## Real AI Example

`docs/examples/pm-plugin-example` now contains a real AI plugin example (not static mock output):

- `run.py` can call either:
  - OpenAI-compatible API (`OPENAI_API_KEY` / `OPENAI_COMPAT_API_KEY`)
  - Codex CLI (`codex login`)
- Configure via `OPENMAC_PM_PLUGIN_AUTH=auto|openai|codex`
- See `docs/examples/pm-plugin-example/README.md` for setup details.
