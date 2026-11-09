$ErrorActionPreference = "Stop"
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("JustAC-build-test-" + [guid]::NewGuid().ToString("N"))
$shell = (Get-Process -Id $PID).Path
$oldTemp, $oldTmp = $env:TEMP, $env:TMP
$checks = 0

function Assert($condition, $message) {
    if (-not $condition) { throw $message }
    $script:checks++
}

function InvokeFixture($expectSuccess) {
    & $shell -NoProfile -File (Join-Path $fixture "build.ps1") *> (Join-Path $fixture "output.log")
    $succeeded = $LASTEXITCODE -eq 0
    Assert ($succeeded -eq $expectSuccess) (Get-Content (Join-Path $fixture "output.log") -Raw)
    Assert (@(Get-ChildItem (Join-Path $fixture "temp") -Force).Count -eq 0) "Staging files were not cleaned up."
    Assert (@(Get-ChildItem (Join-Path $fixture "dist") -Filter ".*.zip" -Force).Count -eq 0) "Partial ZIP was not cleaned up."
}

try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    foreach ($dir in @("Data\Forever", "Libs\Test", "temp", "dist")) {
        New-Item -ItemType Directory -Path (Join-Path $fixture $dir) -Force | Out-Null
    }
    Copy-Item (Join-Path $PSScriptRoot "..\build.ps1") (Join-Path $fixture "build.ps1")
    $toc = @("## Version: test", "Data\Forever\Rotations.lua", "Libs\Test\lib.lua")
    Set-Content (Join-Path $fixture "JustAC.toc") $toc
    foreach ($file in @("LICENSE", "README.md", "Data\Forever\Rotations.lua", "Libs\Test\lib.lua")) {
        Set-Content (Join-Path $fixture $file) "fixture"
    }
    $env:TEMP = Join-Path $fixture "temp"
    $env:TMP = $env:TEMP
    $archivePath = Join-Path $fixture "dist\JustAC-test.zip"

    # Invoke from another directory and inspect the real ZIP output.
    InvokeFixture $true
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $names = @($archive.Entries | ForEach-Object { $_.FullName })
        Assert ($names -contains "JustAC/Data/Forever/Rotations.lua") "Forever subdirectory missing."
        Assert ($names -contains "JustAC/Libs/Test/lib.lua") "Library missing."
        Assert (@($names | Where-Object { $_.Contains('\') }).Count -eq 0) "ZIP paths contain backslashes."
    } finally {
        $archive.Dispose()
    }

    Set-Content (Join-Path $fixture "Data\Forever\Rotations.lua") "updated fixture"
    InvokeFixture $true
    $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $reader = [System.IO.StreamReader]::new($archive.GetEntry("JustAC/Data/Forever/Rotations.lua").Open())
        try {
            Assert ($reader.ReadToEnd().Trim() -eq "updated fixture") "Existing archive was not replaced."
        } finally {
            $reader.Dispose()
        }
    } finally {
        $archive.Dispose()
    }
    $goodHash = (Get-FileHash $archivePath).Hash

    foreach ($missing in @("Data\Forever\Rotations.lua", "Libs\Test\lib.lua")) {
        $path = Join-Path $fixture $missing
        Remove-Item -LiteralPath $path
        InvokeFixture $false
        Assert ((Get-FileHash $archivePath).Hash -eq $goodHash) "Missing input destroyed the previous archive."
        Set-Content $path "fixture"
    }

    Set-Content (Join-Path $fixture "JustAC.toc") @("## Version:", "Data\Forever\Rotations.lua")
    InvokeFixture $false
    Assert ((Get-FileHash $archivePath).Hash -eq $goodHash) "Invalid version destroyed the previous archive."
    Set-Content (Join-Path $fixture "JustAC.toc") $toc

    # A publication failure must preserve the existing archive and clean staging.
    $locked = [System.IO.File]::Open($archivePath, 'Open', 'Read', 'Read')
    try {
        InvokeFixture $false
    } finally {
        $locked.Dispose()
    }
    Assert ((Get-FileHash $archivePath).Hash -eq $goodHash) "Failed publication changed the previous archive."
    Write-Host "Build fixtures: $checks checks passed."
} finally {
    $env:TEMP, $env:TMP = $oldTemp, $oldTmp
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
$global:LASTEXITCODE = 0
