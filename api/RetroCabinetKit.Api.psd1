@{
    RootModule        = 'RetroCabinetKit.Api.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = '9a3e6c41-7b2d-4f88-a5c0-3d1e8f6b2a77'
    Author            = 'retro-cabinet-kit contributors'
    Description       = 'Kit API v1 (API.md): one facade for GUI, CLI, tests and external clients. Operations return OperationResult; changes only with -Apply; approvals only with -Approved; plain parameters only.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-KitApiVersion', 'New-KitOperationResult', 'Get-KitOperation', 'Invoke-KitOperation', 'Invoke-KitOperationIsolated',
                          'Get-KitCabinetStatus', 'Get-KitCabinetComponent', 'Get-KitBackupList', 'ConvertTo-KitApiJson')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
