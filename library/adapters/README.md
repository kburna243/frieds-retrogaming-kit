# Library adapters — RetroBat, PinballY, Playnite, LaunchBox, Generic frontend ROM and media management.

This directory contains adapter modules for various frontend applications used in retro gaming cabinets.
Each adapter follows the standard five-function shape:
- Test-<Frontend>Frontend - Detects if the frontend is installed
- Get-<Frontend>FrontendInfo - Returns frontend-specific configuration details
- Install-<Frontend>Frontend - Installs the frontend (if supported)
- Configure-<Frontend>Frontend - Applies configuration profiles
- Set-<Frontend>InterferenceShield - Toggles interference mitigation

Supported frontends will include:
- RetroBat
- PinballY
- Playnite
- LaunchBox
- Generic (for custom frontend implementations)

Each adapter provides frontend-specific fields in Get-<Frontend>FrontendInfo:
- DatabaseFormat: xml, sqlite, json
- RomPathPattern: system/rom.ext or roms/system/rom.ext
- MediaPathPattern: media/system/rom.*
- PlaylistFormat: how this frontend stores playlists