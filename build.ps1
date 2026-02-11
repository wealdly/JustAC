# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2025 wealdly
# Build script for JustAC distribution package
# Run: .\build.ps1

$addonName = "JustAC"
$version = (Get-Content "JustAC.toc" | Select-String "## Version:" | ForEach-Object { $_ -replace "## Version:\s*", "" }).Trim()
if (-not $version) { $version = "dev" }

# Output to a "dist" folder inside the addon
$distDir = Join-Path $PSScriptRoot "dist"
$tempDir = Join-Path $env:TEMP "$addonName-build"
$outputDir = Join-Path $tempDir $addonName
$zipFile = Join-Path $distDir "$addonName-$version.zip"

# Clean previous build
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }

# Create directories
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

Write-Host "Building $addonName v$version..." -ForegroundColor Cyan

# Core addon files (explicit list for clarity)
$coreFiles = @(
    "JustAC.toc",
    "JustAC.lua",
    "Locale.lua",
    "SpellDB.lua",
    "BlizzardAPI.lua",
    "FormCache.lua",
    "MacroParser.lua",
    "ActionBarScanner.lua",
    "RedundancyFilter.lua",
    "SpellQueue.lua",
    "UIHealthBar.lua",
    "UIAnimations.lua",
    "UIFrameFactory.lua",
    "UIRenderer.lua",
    "UIManager.lua",
    "DebugCommands.lua",
    "Options.lua",
    "LICENSE",
    "README.md"
)

foreach ($file in $coreFiles) {
    $src = Join-Path $PSScriptRoot $file
    if (Test-Path $src) {
        Copy-Item $src $outputDir -Force
    }
}

# Copy Libs folder
$libsDest = Join-Path $outputDir "Libs"
Copy-Item (Join-Path $PSScriptRoot "Libs") $libsDest -Recurse -Force

# Remove duplicate nested folders in Libs (cleanup)
Get-ChildItem $libsDest -Directory | ForEach-Object {
    $nested = Join-Path $_.FullName $_.Name
    if (Test-Path $nested) {
        Write-Host "  Removing duplicate: Libs/$($_.Name)/$($_.Name)" -ForegroundColor Yellow
        Remove-Item $nested -Recurse -Force
    }
}

# Create ZIP with forward slashes for macOS/Linux compatibility
# (Compress-Archive uses backslashes which breaks non-Windows extractors)
Write-Host "Creating ZIP archive..." -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipFile, 'Create')
Get-ChildItem $outputDir -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($tempDir.Length + 1).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, $_.FullName, $relativePath, [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
}
$zip.Dispose()

# Clean up temp folder
Remove-Item $tempDir -Recurse -Force

Write-Host "`nBuild complete!" -ForegroundColor Green
Write-Host "  ZIP: $zipFile" -ForegroundColor White

# Show package size
$size = (Get-Item $zipFile).Length / 1KB
Write-Host "  Size: $([math]::Round($size, 1)) KB" -ForegroundColor White
