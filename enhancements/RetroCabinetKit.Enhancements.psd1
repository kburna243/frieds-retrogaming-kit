@{
    RootModule        = 'RetroCabinetKit.Enhancements.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'e80d3c37-aa66-4243-bddb-85c0c73f7f24'
    Author            = 'Fried'
    Description       = 'Enhancement package of retro-cabinet-kit: GPU, audio, frame pacing, shader, upscaling, latency reduction, ambient lighting, and audio enhancement detection and configuration via adapter plugins.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Enhancements*', '*-Enhancement*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'enhancement', 'gpu', 'audio', 'shader', 'upscaling', 'latency', 'framepacing', 'ambient', 'mpo') } }
}