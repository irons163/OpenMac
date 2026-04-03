#!/usr/bin/env python3
"""OpenMac PM plugin example with real AI planning.

Auth strategy (`OPENMAC_PM_PLUGIN_AUTH`):
- `auto` (default): try OpenAI API key first, then Codex CLI.
- `openai`: require OPENAI_API_KEY / OPENAI_COMPAT_API_KEY.
- `codex`: require local `codex` CLI login.

Outputs PM Plugin API v1 JSON to stdout.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from typing import Any
from urllib import error as urlerror
from urllib import request as urlrequest


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def extract_json_object(raw: str) -> dict[str, Any]:
    raw = (raw or "").strip()
    if not raw:
        fail("AI plugin produced empty output")
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end < start:
        fail("AI plugin output did not contain a JSON object")
    try:
        parsed = json.loads(raw[start : end + 1])
    except json.JSONDecodeError as exc:
        fail(f"AI plugin returned invalid JSON: {exc}")
    if not isinstance(parsed, dict):
        fail("AI plugin JSON root must be an object")
    return parsed


def normalize_text(value: Any) -> str:
    if isinstance(value, str):
        return value.strip()
    return ""


def normalize_skills(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    output: list[str] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, str):
            continue
        trimmed = item.strip()
        if not trimmed:
            continue
        key = trimmed.lower()
        if key in seen:
            continue
        seen.add(key)
        output.append(trimmed)
    return output


def normalize_story_points(value: Any, default_value: int) -> int:
    if isinstance(value, bool):
        return default_value
    if isinstance(value, (int, float)):
        points = int(value)
        return min(13, max(1, points))
    return default_value


def ensure_acceptance_block(details: str, dependency: str) -> str:
    normalized = details.strip()
    if not normalized:
        normalized = "- Define scope and measurable outcomes."
    lower = normalized.lower()
    lines: list[str] = []
    if "acceptance:" not in lower:
        lines.append("Acceptance:")
    lines.append(normalized)
    joined = "\n".join(lines)
    if "depends on:" not in joined.lower():
        joined = f"{joined}\nDepends on: {dependency}"
    return joined


def normalize_plan(candidate: dict[str, Any], request_payload: dict[str, Any], source_label: str) -> dict[str, Any]:
    request_name = normalize_text(request_payload.get("projectName")) or "PM Project"
    project_name = normalize_text(candidate.get("projectName")) or request_name
    summary = normalize_text(candidate.get("summary")) or "AI-generated PM plan."

    raw_tickets = candidate.get("tickets")
    if not isinstance(raw_tickets, list):
        fail("AI plugin output is missing `tickets` array")

    tickets: list[dict[str, Any]] = []
    for index, raw_ticket in enumerate(raw_tickets):
        if not isinstance(raw_ticket, dict):
            continue
        title = normalize_text(raw_ticket.get("title"))
        if not title:
            continue
        default_dependency = "none" if not tickets else tickets[-1]["title"]
        details = ensure_acceptance_block(
            normalize_text(raw_ticket.get("details")),
            normalize_text(raw_ticket.get("dependsOn")) or default_dependency,
        )
        ticket = {
            "title": title,
            "details": details,
            "requiredSkills": normalize_skills(raw_ticket.get("requiredSkills")),
            "storyPoints": normalize_story_points(raw_ticket.get("storyPoints"), 2 if index == 0 else 3),
            "epic": normalize_text(raw_ticket.get("epic")) or ("Planning" if index == 0 else "Execution"),
            "milestone": normalize_text(raw_ticket.get("milestone")) or ("M1 Scope Locked" if index <= 1 else "M2 MVP Complete"),
        }
        tickets.append(ticket)

    if not tickets:
        fail("AI plugin produced no valid tickets")

    return {
        "projectName": project_name,
        "summary": f"{summary}\nPlanning engine: OpenMac AI Brainstorm ({source_label})",
        "tickets": tickets,
    }


def build_llm_messages(request_payload: dict[str, Any]) -> tuple[str, str]:
    project_name = normalize_text(request_payload.get("projectName")) or "PM Project"
    project_brief = normalize_text(request_payload.get("projectBrief")) or "(empty brief)"
    agents = request_payload.get("availableAgents")
    if isinstance(agents, list):
        compact_agents = []
        for item in agents:
            if not isinstance(item, dict):
                continue
            compact_agents.append(
                {
                    "name": normalize_text(item.get("name")),
                    "skills": normalize_skills(item.get("skills")),
                    "maxConcurrentTasks": normalize_story_points(item.get("maxConcurrentTasks"), 1),
                }
            )
    else:
        compact_agents = []

    system_prompt = (
        "You are a senior product manager. "
        "Return STRICT JSON only. No markdown. No explanation text. "
        "Output schema: {projectName, summary, tickets[]} and each ticket has "
        "{title, details, requiredSkills, storyPoints, epic, milestone}. "
        "Ticket details must include 'Acceptance:' and 'Depends on:'. "
        "Produce 4-8 practical, dependency-aware tickets."
    )
    user_prompt = json.dumps(
        {
            "task": "Generate execution-ready PM tickets.",
            "projectName": project_name,
            "projectBrief": project_brief,
            "availableAgents": compact_agents,
        },
        ensure_ascii=False,
    )
    return system_prompt, user_prompt


def run_with_openai(request_payload: dict[str, Any]) -> dict[str, Any]:
    api_key = (os.getenv("OPENAI_API_KEY") or os.getenv("OPENAI_COMPAT_API_KEY") or "").strip()
    if not api_key:
        fail("Missing OPENAI_API_KEY / OPENAI_COMPAT_API_KEY for AI PM plugin")

    base = (os.getenv("OPENAI_BASE_URL") or "https://api.openai.com").strip().rstrip("/")
    if "/chat/completions" in base:
        endpoint = base
    else:
        endpoint = f"{base}/v1/chat/completions"
    model = (os.getenv("OPENMAC_PM_PLUGIN_MODEL") or "gpt-5").strip() or "gpt-5"

    system_prompt, user_prompt = build_llm_messages(request_payload)
    payload = {
        "model": model,
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
    }
    req = urlrequest.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urlrequest.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except urlerror.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        fail(f"OpenAI API request failed ({exc.code}): {body}")
    except Exception as exc:  # noqa: BLE001
        fail(f"OpenAI API request failed: {exc}")

    envelope = extract_json_object(raw)
    choices = envelope.get("choices")
    if not isinstance(choices, list) or not choices:
        fail("OpenAI API response missing `choices`")
    message = choices[0].get("message") if isinstance(choices[0], dict) else None
    if not isinstance(message, dict):
        fail("OpenAI API response missing message payload")
    content = message.get("content")
    if isinstance(content, list):
        content = "".join(
            part.get("text", "") for part in content if isinstance(part, dict) and isinstance(part.get("text"), str)
        )
    if not isinstance(content, str):
        fail("OpenAI API response content is not text")
    return normalize_plan(extract_json_object(content), request_payload, "OpenAI API")


def run_with_codex(request_payload: dict[str, Any]) -> dict[str, Any]:
    codex = shutil.which("codex")
    if not codex:
        fail("codex CLI not found for Codex-auth AI PM plugin mode")

    model = (os.getenv("OPENMAC_PM_CODEX_MODEL") or "gpt-5").strip()
    profile = (os.getenv("OPENMAC_PM_CODEX_PROFILE") or "").strip()
    sandbox = (os.getenv("OPENMAC_PM_CODEX_SANDBOX") or "read-only").strip()

    system_prompt, user_prompt = build_llm_messages(request_payload)
    prompt = f"{system_prompt}\n\nInput:\n{user_prompt}"

    with tempfile.NamedTemporaryFile(prefix="openmac-pm-plugin-", suffix=".txt", delete=False) as tmp:
        output_path = tmp.name

    args = [
        codex,
        "exec",
        "--skip-git-repo-check",
        "--json",
        "--output-last-message",
        output_path,
    ]
    if sandbox:
        args.extend(["--sandbox", sandbox])
    if model:
        args.extend(["--model", model])
    if profile:
        args.extend(["--profile", profile])
    args.append(prompt)

    try:
        completed = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            text=True,
            encoding="utf-8",
        )
    except Exception as exc:  # noqa: BLE001
        fail(f"Failed to run codex CLI: {exc}")

    if completed.returncode != 0:
        fail((completed.stdout or "").strip() or f"codex exited with code {completed.returncode}")

    content = ""
    try:
        with open(output_path, "r", encoding="utf-8") as handle:
            content = handle.read().strip()
    except OSError:
        pass
    finally:
        try:
            os.remove(output_path)
        except OSError:
            pass

    if not content:
        content = (completed.stdout or "").strip()
    return normalize_plan(extract_json_object(content), request_payload, "Codex CLI")


def main() -> None:
    raw = sys.stdin.read()
    if not raw.strip():
        fail("Missing stdin request payload")
    try:
        request_payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"Invalid stdin JSON payload: {exc}")
    if not isinstance(request_payload, dict):
        fail("stdin payload must be a JSON object")

    auth_mode = (os.getenv("OPENMAC_PM_PLUGIN_AUTH") or "auto").strip().lower()

    if auth_mode == "openai":
        result = run_with_openai(request_payload)
    elif auth_mode == "codex":
        result = run_with_codex(request_payload)
    elif auth_mode == "auto":
        api_key = (os.getenv("OPENAI_API_KEY") or os.getenv("OPENAI_COMPAT_API_KEY") or "").strip()
        if api_key:
            result = run_with_openai(request_payload)
        else:
            result = run_with_codex(request_payload)
    else:
        fail("OPENMAC_PM_PLUGIN_AUTH must be one of: auto, openai, codex")

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
