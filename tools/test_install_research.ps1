$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('JustAC-research-test-' + [guid]::NewGuid().ToString('N'))
$shell = (Get-Process -Id $PID).Path
$checks = 0

function Assert($condition, $message) {
    if (-not $condition) { throw $message }
    $script:checks++
}

function InvokeInstaller($expectSuccess) {
    & $shell -NoProfile -File (Join-Path $fixture 'tools\install_research.ps1') -AddOnsPath $client *> (Join-Path $fixture 'output.log')
    Assert (($LASTEXITCODE -eq 0) -eq $expectSuccess) (Get-Content -LiteralPath (Join-Path $fixture 'output.log') -Raw)
}

try {
    foreach ($directory in @('tools', 'Debug\Research', 'client\JustAC\Debug', 'other-client')) {
        New-Item -ItemType Directory -Path (Join-Path $fixture $directory) -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'install_research.ps1') -Destination (Join-Path $fixture 'tools\install_research.ps1')
    $client = Join-Path $fixture 'client'
    $target = Join-Path $client 'JustAC_Research'
    Set-Content -LiteralPath (Join-Path $fixture 'LICENSE') 'license fixture'
    Set-Content -LiteralPath (Join-Path $fixture 'other-client\sentinel') 'untouched'
    InvokeInstaller $false
    Assert (-not (Test-Path -LiteralPath $target)) 'Missing sources created a companion.'
    $manifest = Join-Path $fixture 'Debug\Research\JustAC_Research.toc'
    Set-Content -LiteralPath $manifest @('## Interface: old', '## Dependencies: JustAC', 'Signals.lua')
    Set-Content -LiteralPath (Join-Path $fixture 'Debug\Research\Signals.lua') '-- research fixture'
    $clientToc = Join-Path $client 'JustAC\JustAC.toc'
    Set-Content -LiteralPath $clientToc '## Interface: test-client'
    InvokeInstaller $false
    Assert (-not (Test-Path -LiteralPath $target)) 'Incompatible JustAC created a companion.'
    $required = @('Debug\Common.lua', 'Debug\Capture.lua', 'Debug\Validation.lua', 'Debug\Session.lua')
    Set-Content -LiteralPath $clientToc (@('## Interface: test-client') + $required)
    foreach ($file in $required) {
        Set-Content -LiteralPath (Join-Path (Split-Path -Parent $clientToc) $file) '-- durable fixture'
    }
    $before = (Get-FileHash -LiteralPath $clientToc).Hash
    InvokeInstaller $true
    $installedToc = Get-Content -LiteralPath (Join-Path $target 'JustAC_Research.toc')
    Assert ($installedToc -contains '## Interface: test-client') 'Companion interface was not taken from the target client.'
    Assert ($installedToc -contains '## Dependencies: JustAC') 'Companion dependency missing.'
    Assert ((Get-Content -LiteralPath (Join-Path $target 'Signals.lua') -Raw).Trim() -eq '-- research fixture') 'Probe source missing.'
    Assert ((Get-Content -LiteralPath (Join-Path $target 'LICENSE') -Raw).Trim() -eq 'license fixture') 'License missing.'
    Assert ((Get-FileHash -LiteralPath $clientToc).Hash -eq $before) 'Installer modified JustAC.'
    Assert ((Get-Content -LiteralPath (Join-Path $fixture 'other-client\sentinel') -Raw).Trim() -eq 'untouched') 'Installer modified another client.'
    Set-Content -LiteralPath $manifest @('## Interface: old', '..\outside.lua')
    InvokeInstaller $false
    Assert (@(Get-ChildItem -LiteralPath $target -File).Count -eq 3) 'Invalid manifest changed the installed companion.'
    Write-Host "Research installer fixtures: $checks checks passed."
} finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
$global:LASTEXITCODE = 0
