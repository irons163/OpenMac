# OpenMac AI Brainstorm Plugin (Real LLM)

This example plugin performs real AI planning (not static/mock output).

It supports:
- OpenAI-compatible API key mode (`OPENAI_API_KEY` / `OPENAI_COMPAT_API_KEY`)
- Codex CLI login mode (`codex login`)

## Files

- `plugin.json`: PM plugin manifest (`pm.plan.generate`) + PM planner `uiExtensions`
- `run.sh`: shell entrypoint used by OpenMac
- `run.py`: AI planner implementation

## Quick setup

1. Copy this folder to:

`~/Library/Application Support/OpenMac/Plugins/pm-ai-brainstorm`

2. In OpenMac:
- PM planner mode = `Brainstorm Plugin (Preferred)`
- PM plugin discovery = enabled
- Click `Rescan PM Plugins`

## Auth mode

Use env var `OPENMAC_PM_PLUGIN_AUTH`:

- `auto` (default): OpenAI API key first, then Codex CLI
- `openai`: require API key
- `codex`: require `codex` CLI login

## OpenAI API mode

Required:
- `OPENAI_API_KEY` or `OPENAI_COMPAT_API_KEY`

Optional:
- `OPENAI_BASE_URL` (default: `https://api.openai.com`)
- `OPENMAC_PM_PLUGIN_MODEL` (default: `gpt-5`)

## Codex CLI mode

Required:
- `codex` executable available
- completed `codex login`

Optional:
- `OPENMAC_PM_CODEX_MODEL` (default: `gpt-5`)
- `OPENMAC_PM_CODEX_PROFILE`
- `OPENMAC_PM_CODEX_SANDBOX` (default: `read-only`)

## Behavior

- If plugin execution fails, OpenMac falls back to built-in planning.
- Successful output includes a summary marker with source:
  - `Planning engine: OpenMac AI Brainstorm (OpenAI API)` or
  - `Planning engine: OpenMac AI Brainstorm (Codex CLI)`
