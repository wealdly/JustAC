# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2025 wealdly
# Build script for JustAC distribution package
# Run: .\build.ps1 (input paths are relative to this script, not the working directory)

$ErrorActionPreference = "Stop"
$addonName = "JustAC"
$tocPath = Join-Path $PSScriptRoot "JustAC.toc"
$tocLines = Get-Content -LiteralPath $tocPath
$versions = @($tocLines | Where-Object { $_ -match '^## Version:\s*' } |
    ForEach-Object { ($_ -replace '^## Version:\s*', '').Trim() })
if ($versions.Count -ne 1 -or [string]::IsNullOrWhiteSpace($versions[0])) {
    throw "JustAC.toc must contain exactly one non-empty Version field."
}
$version = $versions[0]
if ($version.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw "JustAC.toc contains a version that is not a valid filename."
}

# Output to a "dist" folder inside the addon
$distDir = Join-Path $PSScriptRoot "dist"
$buildID = [guid]::NewGuid().ToString("N")
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "$addonName-build-$buildID"
$outputDir = Join-Path $tempDir $addonName
$zipFile = Join-Path $distDir "$addonName-$version.zip"
$pendingZip = Join-Path $distDir ".$addonName-$buildID.zip"

# Derive addon source files from JustAC.toc (single source of truth for load order).
# Libs entries are excluded here - the Libs folder is copied as a directory below.
$tocFiles = @($tocLines | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -notmatch '^#' -and $_ -ne '' })
$addonFiles = @($tocFiles | Where-Object { $_ -notmatch '^Libs[\\/]' })
$coreFiles = @("JustAC.toc", "LICENSE", "README.md") + $addonFiles

$missingFiles = @()
foreach ($file in (@("JustAC.toc", "LICENSE", "README.md") + $tocFiles)) {
    $src = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        $missingFiles += $file
    }
}
if ($missingFiles.Count -gt 0) {
    throw "Build FAILED - missing files: $($missingFiles -join ', ')"
}
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "Libs") -PathType Container)) {
    throw "Build FAILED - missing Libs directory."
}

try {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "Building $addonName v$version..." -ForegroundColor Cyan

    foreach ($file in $coreFiles) {
        $src = Join-Path $PSScriptRoot $file
        $dest = Join-Path $outputDir $file
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dest -Force
    }

    # Copy Libs folder
    $libsDest = Join-Path $outputDir "Libs"
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Libs") -Destination $libsDest -Recurse -Force

    # AceGUI-3.0-SharedMediaWidgets has a legitimate same-named subfolder - skip it.
    Get-ChildItem -LiteralPath $libsDest -Directory | ForEach-Object {
        $nested = Join-Path $_.FullName $_.Name
        if ((Test-Path -LiteralPath $nested) -and $_.Name -ne "AceGUI-3.0-SharedMediaWidgets") {
            Write-Host "  Removing duplicate: Libs/$($_.Name)/$($_.Name)" -ForegroundColor Yellow
            Remove-Item -LiteralPath $nested -Recurse -Force
        }
    }

    # Create ZIP with forward slashes for macOS/Linux compatibility.
    Write-Host "Creating ZIP archive..." -ForegroundColor Cyan
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($pendingZip, 'Create')
    try {
        Get-ChildItem -LiteralPath $outputDir -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($tempDir.Length + 1).Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $_.FullName, $relativePath, [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    } finally {
        $zip.Dispose()
    }

    # Publish on the same filesystem only after the archive has closed successfully.
    if (Test-Path -LiteralPath $zipFile) {
        [System.IO.File]::Replace($pendingZip, $zipFile, [NullString]::Value)
    } else {
        [System.IO.File]::Move($pendingZip, $zipFile)
    }
} finally {
    if (Test-Path -LiteralPath $pendingZip) {
        Remove-Item -LiteralPath $pendingZip -Force
    }
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}

Write-Host "`nBuild complete!" -ForegroundColor Green
Write-Host "  ZIP: $zipFile" -ForegroundColor White

# Show package size
$size = (Get-Item $zipFile).Length / 1KB
Write-Host "  Size: $([math]::Round($size, 1)) KB" -ForegroundColor White
