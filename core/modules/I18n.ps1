# I18n: user-facing texts from i18n\<culture>.psd1 via Import-LocalizedData.
# Lookup order: selected culture -> en-US -> visible placeholder [[Key]].

$script:KitCulture   = $null
$script:KitTextCache = @{}

function Read-I18nTable([string] $Culture) {
    if ($script:KitTextCache.ContainsKey($Culture)) { return $script:KitTextCache[$Culture] }
    $table = @{}
    if (Test-Path -LiteralPath (Join-Path $script:KitI18nDir "$Culture.psd1")) {
        $loaded = $null
        Import-LocalizedData -BindingVariable loaded -BaseDirectory $script:KitI18nDir -FileName "$Culture.psd1" -UICulture $Culture -ErrorAction Stop
        if ($loaded) { $table = $loaded }
    }
    $script:KitTextCache[$Culture] = $table
    $table
}

function Get-KitCulture {
    [CmdletBinding()]
    param()
    if ($script:KitCulture) { return $script:KitCulture }
    (Get-UICulture).Name
}

function Set-KitCulture {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Culture)
    $script:KitCulture = $Culture
}

function Get-KitText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Key,
        [Parameter(Position = 1)] [Alias('f')] [object[]] $FormatArgs
    )
    $text = $null
    foreach ($culture in (Get-KitCulture), 'en-US') {
        $table = Read-I18nTable $culture
        if ($table.ContainsKey($Key)) { $text = $table[$Key]; break }
    }
    if ($null -eq $text) { return "[[$Key]]" }
    if ($FormatArgs) { return ($text -f $FormatArgs) }
    $text
}
