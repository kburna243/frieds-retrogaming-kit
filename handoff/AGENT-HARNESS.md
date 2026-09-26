# Handoff: agent harness (separate repository) ↔ Kit API

> **Kurz auf Deutsch:** Das Harness ist ein eigenes Repo und ein *Client* des Kits, nie ein Teil davon. Es spricht
> ausschließlich über die Kit-API (`API.md`) mit dem Kabinett: JSON über stdin/stdout, kein Netzwerkport. Das Kit
> bleibt offline und deterministisch; ohne Harness funktioniert alles wie bisher. Der Rest ist für den umsetzenden
> Agenten (Englisch).

## 1. Boundary

```text
frieds-agent-harness (own repo)                     frieds-retrogaming-kit (this repo)
┌──────────────────────────────────────┐            ┌──────────────────────────────────┐
│ runtime · planning · memory (SQLite) │            │ api\Invoke-KitApi.ps1  (JSON)    │
│ policies · model gateway             │── stdio ──▶│ api\RetroCabinetKit.Api (v1)     │
│   ├─ local (Ollama, llama.cpp, ...)  │   JSON     │ core · pinball · lightgun · gui  │
│   └─ cloud (any provider)            │            │ no network, no LLM, no telemetry │
│ Kit adapter (tools from the catalog) │            └──────────────────────────────────┘
└──────────────────────────────────────┘
```

- The kit never imports harness code and never opens a port. The harness never reads kit internals (state files,
  module functions); it only calls operations.
- Contract: `API.md` (API v1). Contract tests in the kit: `tests\api\Api.Tests.ps1`. Pin the harness to
  `ApiVersion` major `1` and refuse a different major.

## 2. Calling the kit

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <kit>\api\Invoke-KitApi.ps1
    -Operation <name> [-ParametersJson <json object>] [-Apply] [-Approved] [-Anonymize] [-Culture en-US|de-DE]
```

- Always the full path `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` (Windows PowerShell 5.1),
  like the kit's own launchers.
- Standard output: exactly one JSON document (`OperationResult`). Exit code `0` success, `1` did not succeed,
  `2` refused. Log lines never reach standard output.
- `-List` (or `-Operation operations`) returns the catalog: name, kind (`Read`/`Change`), interactive, available,
  description, parameters (name, type, mandatory). Build the tool list from it at start-up — steps and their
  parameters come from the kit and change with kit versions.

## 3. Policy mapping (non-negotiable)

| Kit rule | Harness behaviour |
| :--- | :--- |
| `Change` operations are dry runs without `-Apply` | Always call first **without** `-Apply` and show the plan (`Status = WhatIf`, `Message`, `Data.Steps`). |
| `Approvals` lists plans a person must confirm | Show them verbatim to the user. Only after an explicit "yes" call again with `-Apply -Approved`. The model never sets `-Approved` on its own. |
| `-Apply` changes the cabinet | Needs the user's go-ahead for this exact operation and parameters (no blanket approval, no "apply all"). |
| Interactive steps (`Interactive = true`) | Never callable; tell the user to run them in the wizard. |
| Plain parameters only | Build tool schemas from the catalog types; never pass objects or script blocks (the kit refuses them anyway). |
| Results may contain paths and names | Use `-Anonymize` for anything sent to a **cloud** model. For a local model it may be omitted. |
| `Read` operations | Free to call (`status`, `components`, `backups.list`, `backup.check`, `operations`). |

Suggested permission levels: **read-only** (Read operations only) · **operator** (Change with the confirmation
flow above) · no level may bypass the dry run or `-Approved`.

## 4. Tool set (first version)

| Tool | Kit operation | Kind |
| :--- | :--- | :--- |
| `cabinet_status` | `status` | Read |
| `cabinet_components` | `components` | Read |
| `list_backups` / `check_backup` | `backups.list` / `backup.check` | Read |
| `restore_backup` | `backup.restore` | Change |
| `run_step` | `step.<suite>.<nn-name>` (from the catalog) | Change |
| `export_profile` / `import_profile` | `profile.export` / `profile.import` (v0.3; `NotAvailable` before) | Change |
| `support_bundle` | `support.bundle` | Change |

Diagnosis example ("my gun does not work in game X"): `cabinet_status` → `cabinet_components` → read the
relevant checks → propose one change operation → dry run → show plan and approvals → apply only after "yes" →
`cabinet_status` again to verify.

## 5. MCP

The kit will ship an MCP server over stdio on top of the same API (roadmap, kit side). Until then the harness
wraps `Invoke-KitApi.ps1` itself. Design the adapter so that swapping the transport (one-shot process ↔ MCP
stdio) does not change the tool definitions.

## 6. Storage in the harness

Sessions, messages, tool calls, plans and approvals belong in the harness's own SQLite database — never in the
kit. The kit's source of truth is the machine itself (the doctor measures live); cache kit results only as
history, not as current state.

## 7. Acceptance for the first harness release

1. Offline: works with a local model and no network; the kit is unchanged by the harness being installed.
2. Every `Change` goes dry run → user sees plan (+ approvals) → explicit yes → `-Apply` (`-Approved` only for
   approvals) → verify with `status`. A test proves the model cannot skip a stage.
3. Cloud provider calls only ever contain `-Anonymize`d results (test with a fake user name and profile path).
4. Unknown `ApiVersion` major → the harness refuses to run tools.
5. All tool calls and approvals are logged in the harness database with timestamps.
