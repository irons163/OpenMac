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
