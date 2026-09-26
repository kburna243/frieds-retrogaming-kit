# Kit API (v1)

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
   accepted. Unknown parameters are refused before anything runs.
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
| `ApiVersion` | string | `1.0`; a new major version is a breaking change |
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
`Import-KitCabinetProfile`; until then they report `NotAvailable`.

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

## Versioning

`ApiVersion` changes its minor version when fields or operations are added and its major version when a field or
operation changes meaning or disappears. The contract tests in `tests\api\` pin the fields above.
