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
  "capabilities": ["pm.plan.generate"],
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
- `uiExtensions` (array): declares PM extension UI cards that OpenMac can render.

## `uiExtensions` fields

- `id` (string, required): stable extension id under this plugin.
- `slot` (string, required): where to render it. Current supported slot: `pm.planner`.
- `title` (string, optional): card title.
- `subtitle` (string, optional): helper text under title.
- `component` (string, required): UI component type.
  - Current supported value: `brainstorm.v1`
- `ui` (object, optional): manifest-driven UI schema for this card.
  - `fields` (array, optional):
    - `id` (string, optional)
    - `type` (string, required): supported `focus.input`, `status.text`, `transcript.output`
    - `label` (string, optional)
    - `placeholder` (string, optional)
    - `minHeight` / `maxHeight` (number, optional, mainly for multiline output)
    - `enabled` (boolean, optional, default `true`)
  - `actions` (array, optional):
    - `id` (string, required): supported `pm.brainstorm.run`, `pm.brainstorm.apply`, `pm.brainstorm.clear`
    - `title` (string, optional)
    - `enabled` (boolean, optional, default `true`)
- `priority` (number, optional, default `0`): higher renders earlier.
- `enabled` (boolean, optional, default `true`).

If no local `brainstorm.v1` extension is found, OpenMac inserts a built-in brainstorm extension as fallback.

## Runtime contract

OpenMac executes the entrypoint and sends one JSON payload to `stdin`.

### Request (`stdin`)

```json
{
  "projectName": "YouBike",
  "projectBrief": "Build a cross-platform app...",
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
