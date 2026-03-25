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
    "Locales\enUS.lua",
    "Locales\deDE.lua",
    "Locales\frFR.lua",
    "Locales\ruRU.lua",
    "Locales\esES.lua",
    "Locales\esMX.lua",
    "Locales\ptBR.lua",
    "Locales\zhCN.lua",
    "Locales\zhTW.lua",
    "SpellDB.lua",
    "BlizzardAPI.lua",
    "BlizzardAPI\CooldownTracking.lua",
    "BlizzardAPI\SecretValues.lua",
    "BlizzardAPI\SpellQuery.lua",
    "BlizzardAPI\StateHelpers.lua",
    "FormCache.lua",
    "MacroParser.lua",
    "ActionBarScanner.lua",
    "RedundancyFilter.lua",
    "SpellQueue.lua",
    "UI\UIHealthBar.lua",
    "UI\UIAnimations.lua",
    "UI\UIFrameFactory.lua",
    "UI\UIRenderer.lua",
    "UI\UINameplateOverlay.lua",
    "DefensiveEngine.lua",
    "GapCloserEngine.lua",
    "BurstInjectionEngine.lua",
    "DebugCommands.lua",
    "Options\SpellSearch.lua",
    "Options\LiveSearchPopup.lua",
    "Options\General.lua",
    "Options\StandardQueue.lua",
    "Options\Offensive.lua",
    "Options\CustomQueue.lua",
    "Options\Overlay.lua",
    "Options\Defensives.lua",
    "Options\GapClosers.lua",
    "Options\BurstInjection.lua",
    "Options\Labels.lua",
    "Options\Hotkeys.lua",
    "Options\Profiles.lua",
    "Options\Core.lua",
    "TargetFrameAnchor.lua",
    "KeyPressDetector.lua",
    "LICENSE",
    "README.md"
)

$missingFiles = @()
foreach ($file in $coreFiles) {
    $src = Join-Path $PSScriptRoot $file
    if (-not (Test-Path $src)) {
        $missingFiles += $file
    }
}
if ($missingFiles.Count -gt 0) {
    Write-Host "`nBuild FAILED - missing files:" -ForegroundColor Red
    $missingFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

foreach ($file in $coreFiles) {
    $src = Join-Path $PSScriptRoot $file
    $dest = Join-Path $outputDir $file
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item $src $dest -Force
}

# Copy Libs folder
$libsDest = Join-Path $outputDir "Libs"
Copy-Item (Join-Path $PSScriptRoot "Libs") $libsDest -Recurse -Force

# Remove duplicate nested folders in Libs (cleanup)
# AceGUI-3.0-SharedMediaWidgets has a legitimate same-named subfolder — skip it
Get-ChildItem $libsDest -Directory | ForEach-Object {
    $nested = Join-Path $_.FullName $_.Name
    if ((Test-Path $nested) -and $_.Name -ne "AceGUI-3.0-SharedMediaWidgets") {
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
