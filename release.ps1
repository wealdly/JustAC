# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026 wealdly
# Release helper: promotes UNRELEASED.md into CHANGELOG.md under a new version
# heading, bumps the .toc version, and resets UNRELEASED.md. Does NOT commit/tag -
# it prints the git commands so you can review the diff first.
#
# Run: .\release.ps1 -Version 4.24.0

param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$date = Get-Date -Format "yyyy-MM-dd"

# 1. Pull the UNRELEASED body (everything after the "## [Unreleased]" heading).
$unreleased = Get-Content "UNRELEASED.md" -Raw
$body = ($unreleased -replace '(?s)^\s*##\s*\[Unreleased\]\s*', '').Trim()
if (-not $body) {
    Write-Host "UNRELEASED.md has no notes to release. Add entries first." -ForegroundColor Red
    exit 1
}

# 2. Bump the .toc version.
$toc = Get-Content "JustAC.toc"
if (-not ($toc -match '^##\s*Version:')) {
    Write-Host "Could not find '## Version:' in JustAC.toc." -ForegroundColor Red
    exit 1
}
$toc = $toc -replace '^(##\s*Version:\s*).*', "`${1}$Version"
Set-Content "JustAC.toc" $toc

# 3. Insert "## [Version] - date" + body into CHANGELOG.md, right after "## [Unreleased]".
$changelog = Get-Content "CHANGELOG.md"
$out = [System.Collections.Generic.List[string]]::new()
$inserted = $false
foreach ($line in $changelog) {
    $out.Add($line)
    if (-not $inserted -and $line -match '^##\s*\[Unreleased\]') {
        $out.Add("")
        $out.Add("## [$Version] - $date")
        $out.Add("")
        foreach ($b in ($body -split "`r?`n")) { $out.Add($b) }
        $inserted = $true
    }
}
if (-not $inserted) {
    Write-Host "Could not find '## [Unreleased]' anchor in CHANGELOG.md." -ForegroundColor Red
    exit 1
}
Set-Content "CHANGELOG.md" $out

# 4. Reset UNRELEASED.md to the empty skeleton.
Set-Content "UNRELEASED.md" "## [Unreleased]`n"

Write-Host "Promoted UNRELEASED -> CHANGELOG [$Version] and bumped JustAC.toc." -ForegroundColor Green
Write-Host "Review the diff, then cut the release:" -ForegroundColor Cyan
Write-Host "  git add -A"
Write-Host "  git commit -m 'release: $Version'"
Write-Host "  git tag v$Version"
Write-Host "  git push"
# Push the tag BY NAME. Not `git push --follow-tags`: that pushes annotated tags only,
# and these release tags are lightweight (`git tag` without -a), so it silently skips
# them - the branch push reports success while the tag never leaves the machine and the
# CurseForge workflow never fires. Cost a release once; don't reintroduce it.
Write-Host "  git push origin v$Version    # triggers .github/workflows/release.yml"
