<#
.SYNOPSIS
    8BitDo gamepads for Fried's Retrogaming Kit (Gamepad class).
.DESCRIPTION
    Detects the 8BitDo pad family over its own vendor id (USB\VID_2DC8) plus the individual PIDs of the
    controllers that use it - Pro 2 / Pro 3 in X-, D- and S-mode, the SN30-style receivers and the
    Ultimate software bundle hardware. Detection is read-only; the only write of this package is
    retrobat.ini [Controllers], and it goes through lightgun's audited INI writer (backup, encoding
    kept, WhatIf honoured). No downloads, no process kills, no Steam blacklist.

    MODE SWITCHING IS HARDWARE, NOT SOFTWARE: 8BitDo pads change their USB identity with a button combo
    (Fn+A/B/X/D/S style, model dependent). In D-mode a pad reports a Sony id, in S-mode a Nintendo id.
    That is not a bug the kit repairs - it is the reason the other three adapters exist. See Quirks and
    Set-EightBitDoPadInterferenceShield.
#>

function Test-EightBitDoPadHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Central scan, so the class rule (lightgun > arcade > pads) also holds when someone calls this
    # directly. -Devices binds the caller's list; only an unbound call reads PnP. Read-only either way.
    $params = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Devices')) { $params.Devices = $Devices }
    if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
    @((Get-PadDetectedGamepad @params).DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'EightBitDoPad' }).Count -gt 0
}

function Get-EightBitDoPadAdapterInfo {
    @{
        Class   = 'Gamepad'
        # 8BitDo's Ultimate Software is a Windows GUI (installer, not a portable folder): the kit does
        # not run installers, so there is nothing to unpack into tools\. Firmware and mode work stays
        # manual; Links name the source. ToolDir would only be set for a portable ZIP route.
        ToolDir = ''
        # Tight, per PID. NEVER 'VID_2DC8&' alone: the same vendor id is used by 8BitDo receivers whose
        # PID decides whether it is a pad, an adapter or a charging dock.
        MatchIds = @(
            'USB\VID_2DC8&PID_3106*'   # Pro 2 / Pro 3 series, X-mode (also the 2.4 GHz receiver)
            'USB\VID_2DC8&PID_310A*'   # Pro 2 series, D-mode wire/Bluetooth PAN
            'USB\VID_2DC8&PID_3104*'   # SN30 / Lite family
            'USB\VID_2DC8&PID_301B*'   # Ultimate series, wired
            'USB\VID_2DC8&PID_301C*'   # Ultimate series, 2.4 GHz receiver
            'USB\VID_2DC8&PID_5006*'   # receiver in pairing/dfu-adjacent mode
            'USB\VID_2DC8&PID_6001*'   # Zero-G / arcade-style pads
        )
        # Empty on purpose: a signature exists, so a friendly name may never outvote it (arcade rule).
        NameHints = @()
        Quirks    = @('mode-switch-combo', 'bt-impersonation')
        # CLASS DECISION: pads are the one input class Steam is allowed to keep (Pad.NoBlacklist).
        SteamEntries = @()
        # Pads are RetroBat-side auto-mapping, not per-emulator configuration - see adapters\README.md.
        MameValues = @()
        ControllersValues = @{ Autocontrollers = '1' }
        Model2Values      = @()
        SupermodelValues  = @()
        Links = @{
            # Documentation strings only - the kit never fetches anything (see pads\adapters\README.md).
            '8BitDo (official site: pads, manuals, Ultimate Software)' = 'https://www.8bitdo.com/'
        }
        Notes = @'
The pad answers with a different USB identity per mode: X-mode presents as an Xbox-class device
(045E:028E - arcade's GP2040-CE adapter may claim that id first, and it wins), D-mode presents as Sony
(054C, our PlayStationPad adapter sees it), S-mode presents as Nintendo (057E:2009, our SwitchProPad
adapter sees it). Only the 2DC8 ids in MatchIds come back to this adapter. Set a pad to the mode whose
driver stack the cabinet actually has; the kit changes no mode and installs no firmware.
'@
    }
}

# Deliberately does NOT download: nothing here fetches a package. With -PackagePath + -Approved the
# shared route unpacks a ZIP the user fetched themselves; with ToolDir = '' it declines to write and
# only names the official sources (Install-PadAdapterPackage logs that decision).
function Install-EightBitDoPadSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    Install-PadAdapterPackage -Name 'EightBitDoPad' -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
}

function Configure-EightBitDoPadProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [object[]] $DetectedPads)
    # Gate: only configure a family that is actually plugged in (see _Template for the reasoning).
    if ($PSBoundParameters.ContainsKey('DetectedPads')) {
        if (-not @($DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'EightBitDoPad' }).Count) { return 0 }
    }
    Set-PadGamepadConfiguration -Name 'EightBitDoPad' -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Report-only: no process is killed, nothing is blacklisted. This function's whole job is the prose
# about 8BitDo's masquerade, because only this file knows which mode shows which vendor id.
function Set-EightBitDoPadInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    Write-KitLog (Get-KitText 'Pad.Adapter.ShieldReportsOnly') -Level Info
    Write-KitLog (Get-KitText 'Pad.NoBlacklist') -Level Info
    $params = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Devices')) { $params.Devices = $Devices }
    if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
    if (@((Get-PadDetectedGamepad @params).DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'EightBitDoPad' }).Count) {
        Write-KitLog (Get-KitText 'Pad.Quirk.BtImpersonation' -f 'D', '054C (PlayStation)') -Level Info
        Write-KitLog (Get-KitText 'Pad.Quirk.BtImpersonation' -f 'S', '057E:2009 (Switch Pro)') -Level Info
    }
}
