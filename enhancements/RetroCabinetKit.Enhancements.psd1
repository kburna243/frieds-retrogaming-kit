@{
    RootModule        = 'RetroCabinetKit.Enhancements.psm1'
    ModuleVersion     = '0.7.0'
    GUID              = 'b2c3d4e5-f6g7-8901-h2i3-j4k5l6m7n8o9'
    Author            = 'Fried'
    Description       = 'Enhancement package of retro-cabinet-kit: GPU, audio, frame pacing, shader, upscaling, latency reduction, ambient lighting, and audio enhancement detection and configuration via adapter plugins.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Enhancements*', '*-Enhancement*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'enhancement', 'gpu', 'audio', 'shader', 'upscaling', 'latency', 'framepacing', 'ambient', 'mpo') } }
}