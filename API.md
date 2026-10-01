# Kit API (v1.6)

One stable entry point for every client of the kit — the WPF dashboard, the command line, scripts, tests and
external tools such as an agent harness. The API is a thin, versioned facade over the engine modules; it adds no
kit logic of its own. It is local only: an in-process PowerShell module, plus a one-shot JSON command for clients in
another process (stdin/stdout, no network port).

```text
  GUI · CLI · tests                    agent harness (separate repository)
        │                                         │ MCP / JSON over stdio
        ▼                                         ▼
  api\RetroCabinetKit.Api (in-process)      api\Invoke-KitApi.ps1 (one-shot JSON)
        └───────────────────┬─────────────────────┘
                            ▼
           core · pinball · lightgun (engine, unchanged)
```

## Rules

1. **Nothing changes without `-Apply`.** Every operation of kind `Change` runs as a dry run (`-WhatIf`) unless
   the caller passes `-Apply`. The dry run returns the plan (`Status = WhatIf`) and writes nothing, not even state.
2. **Approvals come from a person.** Some steps show a plan that must be confirmed (installers with SHA-256 and
   signature, scheduled tasks). The API never answers them itself: without `-Approved` every approval is declined
   and its text is returned in `Approvals`, so the client can show it to the user and call again with `-Approved`.
3. **Only plain parameters.** A client can set string, number, switch and string-array parameters. Script blocks,
   objects and the parameters that bind security or tests (`StatePath`, `Culture`, `KitUserSid`, `TrustedOwner`,
   `TaskPrefix`, `AutomationDir`, `LayersKey`, `RegistryRoots`, `AppCompatRoots`, `AnswerFile`) are never
   accepted, nor `Apply` and `Approved` in any spelling: those names belong to the API's own switches (and the
   MCP flags `apply` / `approved`), so a step parameter called that way is never offered. Unknown parameters are
   refused before anything runs.
4. **Interactive steps stay in the wizard.** Steps that need a person at the cabinet (screen calibration, the
   trigger test) are listed with `Interactive = true` and refused by the API.
5. **Local only, no telemetry.** The API opens no port and sends nothing. `-Anonymize` replaces profile paths,
   user and computer names, SIDs, private IPs and e-mail addresses in the JSON (same rules as the support bundle);
   a client that forwards results to a cloud model should always use it.
6. **Never throws for a bad request.** Unknown operations, refused parameters and failures come back as a result
   with `Success = false`; only programming errors in the caller (e.g. a missing `-Name`) throw.

## Result (`RetroCabinetKit.OperationResult`)

| Field | Type | Meaning |
| :--- | :--- | :--- |
| `ApiVersion` | string | `1.6`; a new major version is a breaking change |
| `KitVersion` | string | the kit's version (`VERSION` file), e.g. `0.3.0`; empty if the file is missing |
| `Operation` | string | the operation name as called |
| `Kind` | string | `Read` or `Change` |
| `Success` | bool | `Status` is `Ok`, `Done`, `Skipped` or `WhatIf` |
| `Status` | string | `Ok` (read) · `Done` · `Skipped` (already in place) · `WhatIf` (dry run) · `NeedsUser` · `Failed` · `NotAvailable` |
| `Applied` | bool | `-Apply` was given (changes were allowed) |
| `Message` | string | one line for people |
| `Warnings`, `Errors` | string[] | from the step logs and the operation itself |
| `Changes` | object[] | `Kind` (File, Registry, Database, Task, Setting), `Target`, `Detail` |
| `Backups` | string[] | backups made (kit zips, `<file>.bak_*` copies) |
| `Approvals` | string[] | plans that needed a person's approval (see rule 2) |
| `Duration` | number | seconds |
| `StartedAt` | string | ISO 8601 |
| `Data` | object | operation-specific payload (below) |

Change operations built from steps also carry `Data.Steps`: one entry per step result (`Name`, `Status`,
`WhatIf`, `Message`, `Duration`).

## Operations

`Get-KitOperation` returns this catalog at run time (with the parameters of every step read from its script).

| Name | Kind | Parameters | `Data` |
| :--- | :--- | :--- | :--- |
| `operations` | Read | — | the catalog |
| `status` | Read | — | `Summary` (`Ok`, `Info`, `Warn`, `Error`, `Level`), `Checks[]` (`Area`, `Name`, `Level`, `Detail`) |
| `components` | Read | — | `Components[]` (`Name`, `Present`, `Version`, `Path`, `Detail`) |
| `pinbally.detect` | Read | `Path` | `Root`, `Version`, `Encoding`, `SettingsLine`, `Setting`, `System[]`, `SystemEnabled`, `Reference[]` (`Line`, `Key`, `Value`, `Kind`, `Status`, `TokenName`, `Anchor`, `Resolved`), `ReferenceAbsolute`, `ReferenceToken`, `ReferenceMissing[]`, `ReferenceForeign[]`, `Database[]`, `Game`, `Companion[]`, `Running[]`, `WriteSafe` |
| `pinbally.retarget` | Change | `Path`; `Map` (string[], pairs `Old=New`); `BackupDir` (optional) | `Root`, `Pair[]`, `Plan[]` (`File`, `FileKind`, `Line`, `Key`, `Old`, `New`, `Pair`, `Target`, `Status`, `Reason`), `Ready[]`, `Pending[]`, `Written[]`, `Backup` |
| `backups.list` | Read | `Root` (string[], optional) | `Backups[]` (`Kind`, `Path`, `Created`, `Purpose`, `Original`, `Files`, `Registry`, `SizeBytes`) |
| `backup.check` | Read | `Path` | `Ok`, `Differs`, `Problems[]` |
| `backup.restore` | Change | `Path`; `AllowedRoot` (string[]) for zip backups | `Target`, `SavedCurrent` |
| `backup.export` | Change | `Path`, `Destination` | `Exported` |
| `backup.remove` | Change | `Path` | `Removed` |
| `support.bundle` | Change | `Destination` (optional) | `Path` |
| `step.<suite>.<nn-name>` | Change | the step's plain parameters | `Steps[]` |
| `profile.export`, `profile.import` | Change | the command's plain parameters | the command's result |

`step.*` names come from the step scripts, e.g. `step.lightgun.10-teknoparrot`, `step.pinball.05-relocate`.
`profile.*` appear as soon as the migration engine provides `Export-KitCabinetProfile` /
`Import-KitCabinetProfile`; until then they report `NotAvailable`. A command without its own `-WhatIf` is not run
at all without `-Apply` (the dry run returns the call). The import's rows (`Name`, `Status`, `Detail`) count like
step results: a `NeedsUser` or `Failed` row makes the operation not succeed and appears in `Warnings` / `Errors`.
`AutoInstall` is only accepted when the command takes `-Approve`, so installers go through rule 2.

`pinbally.detect` describes a **PinballY** installation, the second front end for the same tables. It is a Read:
it asks for one folder, writes nothing (not with `-Apply`, which then changes nothing), and every path value that
does not resolve on this machine comes back in `Warnings` — a value that only exists on the machine the folder
came from is reported as `ReferenceForeign`, not as a broken setting. The folder is a parameter because PinballY
is not part of a build: it sits wherever its owner put it, and the kit does not search drives for it.
`components` shows it as soon as the pinball state holds `PinballYRoot`.

`pinbally.retarget` is the write that belongs to that read: a folder copied from another machine holds paths that
resolve there and not here. It takes pairs written as `Old=New` (both absolute, e.g. `C:\Games\Pinball=D:\Games\Pinball`,
a whole drive `C:=D:` is allowed) and rewrites the value of a **line** in `Settings.txt` and in the INI files it knows,
so long as the new path exists on this machine. What it never touches: comments (they hold path examples, not
settings), values with a token like `[STEAM]`, relative paths, values that already resolve, `DefaultSettings.txt`,
the rolling `Settings backup <date>.txt` copies and the HyperList databases. The longest matching prefix wins, and
only at a path boundary: a pair that covers `…\Scripts` never rewrites `…\ScriptsOld\tool.exe`, because that is
other content whose name merely starts with the same letters. Line endings, the
UTF-8 byte order mark and the padding around `=` stay byte for byte as the program wrote them.

The gate is rule 2 in full: without `-Apply` the answer is the plan (`WhatIf`, nothing written, not even the state
file); `-Apply` alone answers `NeedsUser` with one approval text per file; only `-Apply -Approved` writes, and it
writes to files that were put in a `New-KitBackup` ZIP beforehand (that refusal leaves no backup behind, because
nothing was touched). While PinballY or its overlay is running the write is refused — the program rewrites
`Settings.txt` when it closes. A row whose line no longer holds exactly the planned key and value when the write
arrives refuses the whole file rather than writing a line nobody approved: PinballY may have rewritten the file
between the shown plan and the yes. Values the map does not cover, or that lead to a folder that does not exist
here, stay in `Pending` and are reported as `Warnings` — never silently changed and never silently dropped. The
second run answers `Skipped`: the paths resolve now, so there is nothing left to plan.

## In-process (PowerShell)

```powershell
Import-Module .\api\RetroCabinetKit.Api.psd1
Get-KitOperation | Format-Table Name, Kind, Interactive
$r = Invoke-KitOperation -Name 'step.lightgun.07-retrobatsettings'            # dry run: Status WhatIf, the plan
$r = Invoke-KitOperation -Name 'step.lightgun.07-retrobatsettings' -Apply     # changes, backups, verify
$r = Invoke-KitOperation -Name 'backup.restore' -Parameters @{ Path = '<file>.bak_lightgun_...' } -Apply
Get-KitCabinetStatus    # = Invoke-KitOperation -Name status
```

## Other processes (JSON over stdio)

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -File api\Invoke-KitApi.ps1 -Operation status -Anonymize
powershell -NoProfile -ExecutionPolicy Bypass -File api\Invoke-KitApi.ps1 -Operation backup.restore -ParametersJson "{\"Path\":\"...\"}" -Apply
```

Standard output carries exactly one JSON document (the result); log lines never go to standard output. Exit code:
`0` success, `1` the operation did not succeed, `2` the request was refused (unknown operation or parameter).

## MCP server (stdio)

`api\Start-KitMcpServer.ps1` offers the same operations as [MCP](https://modelcontextprotocol.io) tools to an
agent (the separate harness, or any MCP client). Transport is stdio only: JSON-RPC 2.0, one message per line,
UTF-8; the client starts the server as a child process. There is no network port.

```json
{
  "mcpServers": {
    "retro-cabinet": {
      "command": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
      "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<kit>\\api\\Start-KitMcpServer.ps1", "-ReadOnly"]
    }
  }
}
```

- Tools: every available operation of the catalog except `operations`; the name has `.` replaced by `_`
  (`backup.restore` → `backup_restore`, `step.lightgun.10-teknoparrot` → `step_lightgun_10-teknoparrot`). Input
  schemas come from the parameter types; `readOnlyHint` marks `Read`, `destructiveHint` marks `Change`.
- Change tools take `apply` and `approved` (booleans) with exactly the meaning of `-Apply` and `-Approved` (rules
  1 and 2): without `apply` the call is a dry run. Read tools ignore both.
- The result is the `OperationResult` as JSON text; `isError` is `true` when `Success` is `false`. Unknown tools,
  methods and unreadable lines are JSON-RPC errors (`-32602`, `-32601`, `-32700`).
- Results are anonymized (rule 5) unless the server is started with `-NoAnonymize` — only for a local model.
  `-ReadOnly` offers only the read tools; `-Culture de-DE` returns German messages.
- Supported protocol versions: `2025-06-18`, `2025-03-26`, `2024-11-05`. Log lines go to standard error.

## Versioning

`ApiVersion` changes its minor version when fields or operations are added and its major version when a field or
operation changes meaning or disappears. The contract tests in `tests\api\` pin the fields above.

| ApiVersion | Kit | Change |
| :--- | :--- | :--- |
| `1.0` | 0.2.0 | first version |
| `1.1` | 0.3.x | operation `backup.remove`, field `KitVersion`; `Apply` / `Approved` refused as parameter names |
| `1.2` | unreleased | operation `pinbally.detect` and the `PinballY` component row: the second front end can be described (reads only, never writes) |
| `1.3` | unreleased | operation `pinbally.retarget`: the paths of a copied PinballY installation get their targets on this machine, gated by rule 2 like every other change |
| `1.4` | 1.2.0 | operations `setup.set_mode`, `presets.list`, `presets.apply` (setup levels Easy / Custom / NerdExtreme and presets), `status.health` (fast health snapshot: USB hardware, storage reachability, interfering processes, vitals; reads only), `auto.detect` (a plain-language description mapped to kit settings by keyword scoring; reads only), `backups.snapshot`, `backups.rollback` (named rollback points), `outputs.wiimote_hook` (the Wiimote output chain; reads only). The full list with parameters is what `operations` returns |
| `1.5` | 1.3.0 | operations `controllers.input_profiles` (the input profiles: one button layout for the whole cabinet; reads only) and `controllers.input_apply` (a profile written as a MAME ctrlr file of the kit's own; never a file the kit did not write, never `retrobat_auto.cfg`; the plan warns about every RetroBat setting that would keep MAME from loading it) |
| `1.6` | 1.4.0 | operation `controllers.xinput_slots` (the four XInput slots: in use or not, device kind, the MAME joystick number `JOY<n>` — MAME counts connected slots only — and the source names of the buttons as MAME numbers them, triggers as buttons 5/6 on arcade sticks; reads only); operations `controllers.wiimote_order` (which Wiimote is player 1, 2 in Gunmote now — Gunmote numbers them in the order they connect, Windows keeps that as LastArrivalDate, the Bluetooth address comes from the HID entry's parent — and whether that matches the saved binding: `Ok`, `Swapped`, `Unbound`, `Unclear`, `NoGunmote`, `NoWiimote`; reads only) and `controllers.wiimote_bind` (save the current order as the binding in `%USERPROFILE%\RetroCabinet\wiimotes.json`, old file kept as `.bak_<time>`) |
