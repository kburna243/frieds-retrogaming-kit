@{
    RootModule        = 'RetroCabinetKit.Emulators.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = 'e9f8a7b6-c5d4-3210-9876-fedcba543210'
    Author            = 'Fried'
    Description       = 'Emulator package of retro-cabinet-kit: detect, install, configure, patch, and verify emulators for retro gaming cabinets. Covers MAME, RetroArch, TeknoParrot, Supermodel, Model2, Cemu, Dolphin, RPCS3, Xemu, DuckStation, PCSX2 and more via adapter plugins.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Emulators*', '*-Emulator*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'emulator', 'mame', 'retroarch', 'teknoparrot', 'supermodel', 'model2', 'cemu', 'dolphin', 'rpcs3', 'xemu', 'duckstation', 'pcsx2') } }
}

