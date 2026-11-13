# Install the ignored research companion only into an explicitly chosen test client.
param([Parameter(Mandatory = $true)][string]$AddOnsPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'Debug\Research'
$manifest = Join-Path $source 'JustAC_Research.toc'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw 'Local research sources are absent. They are intentionally not distributed through Git or releases.'
}
if (-not (Test-Path -LiteralPath $AddOnsPath -PathType Container)) {
    throw 'AddOnsPath must be an existing test client AddOns directory.'
}
$target = Join-Path (Resolve-Path -LiteralPath $AddOnsPath).Path 'JustAC_Research'
$toc = @(Get-Content -LiteralPath $manifest)
$files = @($toc | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' -and $_ -notmatch '^#' })
foreach ($file in $files) {
    if ($file -notmatch '^[A-Za-z0-9_]+\.lua$' -or
        -not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) {
        throw "Invalid or missing research input: $file"
    }
}
$clientToc = Join-Path (Join-Path $AddOnsPath 'JustAC') 'JustAC.toc'
if (-not (Test-Path -LiteralPath $clientToc -PathType Leaf)) {
    throw 'Install JustAC into the target client first.'
}
$clientLines = @(Get-Content -LiteralPath $clientToc)
foreach ($required in @('Debug\Common.lua', 'Debug\Capture.lua', 'Debug\Validation.lua', 'Debug\Session.lua')) {
    if ($clientLines -notcontains $required -or
        -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $clientToc) $required) -PathType Leaf)) {
        throw 'Target JustAC lacks the split diagnostic infrastructure. Sync compatible JustAC sources separately first.'
    }
}
$interface = @($clientLines | Where-Object { $_ -match '^## Interface:' })
if ($interface.Count -ne 1) { throw 'Target JustAC.toc must have exactly one Interface field.' }
New-Item -ItemType Directory -Path $target -Force | Out-Null
foreach ($file in $files) {
    Copy-Item -LiteralPath (Join-Path $source $file) -Destination (Join-Path $target $file) -Force
}
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $target 'LICENSE') -Force
$toc | ForEach-Object {
    if ($_ -match '^## Interface:') { $interface[0] } else { $_ }
} | Set-Content -LiteralPath (Join-Path $target 'JustAC_Research.toc') -Encoding utf8
Write-Host "Installed local research companion: $target"
Write-Host 'Enable JustAC_Research in the addon list. A newly installed addon may require restarting the client.'
