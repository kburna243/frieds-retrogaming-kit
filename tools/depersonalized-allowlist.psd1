# Allowlist for tools/Test-Depersonalized.ps1: legitimate examples, never real machines or people.
# Every entry: Path (wildcard on the repo-relative path with /), optional Kind (PrivateIp, HostName, DrivePath,
# Email, Secret), optional Match (regex the found text must match) and a Reason. Keep entries as narrow as
# possible; a new entry needs a reason a reviewer can check.
@{
    Entries = @(
        # --- code and tests: synthetic example roots ---------------------------------------------------------
        @{
            Path   = 'tests/*'
            Kind   = 'DrivePath'
            Match  = '^(?![A-Za-z]:[\\/]Users[\\/](?!Max$))'
            Reason = 'Test fixtures use synthetic roots (D:\Old, E:\New, X:\RetroBat, ...). A real user profile path is still reported; only the placeholder user "Max Muster" is allowed.'
        }
        @{
            Path   = 'tests/*'
            Kind   = 'HostName'
            Match  = '^\\\\(nas|host|fileserver)\\share'
            Reason = 'Tests check that network paths are refused; \\nas\share, \\host\share and \\fileserver\share are placeholders.'
        }
        @{
            Path   = 'tests/*'
            Kind   = 'Email'
            Match  = '@evil\.example$'
            Reason = 'Download URL test with user info; .example is a reserved example domain (RFC 2606).'
        }
        @{
            Path   = 'pinball/*'
            Kind   = 'DrivePath'
            Match  = '^([A-Za-z]:\\?|C:\\Program|D:\\Pin(\\Cab)?|D:\\Games|E:\\My|E:\\Games\.?)$'
            Reason = 'Example roots in code comments and parameter help (e.g. "E:\My Build", "C:\Program Files").'
        }
        @{
            Path   = 'pinball/modules/Common.ps1'
            Kind   = 'HostName'
            Match  = '^\\\\nas\\share$'
            Reason = 'Code comment explaining that network paths are refused.'
        }
        # --- documentation and website: example roots only --------------------------------------------------
        @{
            Path   = '*.md'
            Kind   = 'DrivePath'
            Match  = '^[CDE]:\\((Games|Pinball|RetroBat|Old Build|New Build|ProgramData)(\\[^\\]*)*|Windows|Program Files( \(x86\))?|Program|Old)?$'
            Reason = 'Guides use a small fixed set of example folders (D:\Pinball, C:\RetroBat, E:\Old Build, ...) and Windows system folders.'
        }
        # --- this tool --------------------------------------------------------------------------------------
        @{
            Path   = 'tools/depersonalized-allowlist.psd1'
            Reason = 'The allowlist names the example values it allows.'
        }
    )
}
