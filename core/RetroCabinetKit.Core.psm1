#Requires -Version 5.1
# Root module. Each sub-module lives in modules\<Name>.ps1 and is dot-sourced so all of them
# share one module scope (log file, culture, text cache). Public functions follow Verb-Kit*;
# private helpers deliberately do not contain "-Kit" and are therefore not exported.

Set-StrictMode -Version 2.0

$script:KitCoreDir = $PSScriptRoot
$script:KitRoot    = Split-Path -Parent $PSScriptRoot
$script:KitI18nDir = Join-Path $script:KitRoot 'i18n'

# .NET APIs resolve relative paths against the process directory, not the PowerShell location.
function Resolve-FullPath([string] $Path) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

foreach ($name in 'Log', 'State', 'I18n', 'Step', 'Elevation', 'Sqlite', 'Text', 'Registry',
                  'Processes', 'Backup', 'Links', 'Download', 'Ui', 'Doctor', 'Recovery', 'SupportBundle', 'CarePage', 'CabinetProfile') {
    . (Join-Path $PSScriptRoot "modules\$name.ps1")
}

Export-ModuleMember -Function '*-Kit*'
