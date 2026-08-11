#!/usr/bin/env pwsh
# tools/check.ps1 - Lua static-analysis gate for JustAC.
#
# Prefers luacheck (undefined globals + unused locals + syntax); falls back to a
# luaparser syntax-only check; prints install steps if neither is present.
# Run this before committing a non-trivial Lua change or before a /reload - it
# catches the brace/paren and typo'd-global errors that otherwise only surface as
# an addon that fails to load in-game.
#
# Usage:
#   tools/check.ps1                     # whole addon (per .luacheckrc)
#   tools/check.ps1 SpellQueue.lua ...  # specific files
#
# Exit: 0 clean, 1 warnings/errors found, 2 no checker available.

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$root  = Split-Path -Parent $tools
# @(...) forces an array so a single file isn't splatted character-by-character.
if ($Files) { $Files = @($Files | ForEach-Object { (Resolve-Path $_).Path }) }

# 1) luacheck: bundled tools/luacheck.exe, else one on PATH
$luacheck = Join-Path $tools 'luacheck.exe'
if (-not (Test-Path $luacheck)) {
    $onPath = Get-Command luacheck -ErrorAction SilentlyContinue
    $luacheck = if ($onPath) { $onPath.Source } else { $null }
}

Push-Location $root
try {
    if ($luacheck) {
        # @(...) so a 1-element $Files doesn't unwrap to a scalar and splat as chars.
        $targets = @(if ($Files) { $Files } else { '.' })
        & $luacheck @targets
        $code = $LASTEXITCODE
    }
    else {
        # 2) luaparser syntax-only fallback (Python)
        $py = Get-Command python -ErrorAction SilentlyContinue
        $hasParser = $false
        if ($py) { & $py.Source -c 'import luaparser' 2>$null; $hasParser = ($LASTEXITCODE -eq 0) }
        if ($hasParser) {
            Write-Host 'luacheck.exe not found - luaparser syntax-only fallback (no undefined-global check).' -ForegroundColor Yellow
            $targets = @(if ($Files) { $Files } else {
                Get-ChildItem -Recurse -Filter *.lua -File |
                    Where-Object { $_.FullName -notmatch '[\\/](Libs|dist)[\\/]' } |
                    ForEach-Object FullName
            })
            & $py.Source (Join-Path $tools 'luasyntax.py') @targets
            $code = $LASTEXITCODE
        }
        else {
            # 3) nothing available - tell the user what to install
            Write-Host 'No Lua checker found. Install one:' -ForegroundColor Red
            Write-Host '  luacheck (recommended - undefined globals + syntax):'
            Write-Host '    curl -L -o tools/luacheck.exe https://github.com/mpeterv/luacheck/releases/download/0.23.0/luacheck.exe'
            Write-Host '  luaparser (syntax-only fallback, needs Python):'
            Write-Host '    python -m pip install luaparser'
            $code = 2
        }
    }
    # Locale keys, whole-addon runs only. A key the code asks for but no locale defines
    # throws "Missing entry for '<key>'" in game, and comparing the locale files against
    # each other cannot see it - they are all equally missing it. Source is the only truth.
    if (-not $Files) {
        $py = Get-Command python -ErrorAction SilentlyContinue
        if ($py) {
            $locales = & $py.Source (Join-Path $tools 'audit_locales.py') 2>&1
            if ($LASTEXITCODE -ne 0 -or ($locales -match '^FAIL')) {
                Write-Host ''
                $locales | ForEach-Object { Write-Host $_ }
                if ($code -eq 0) { $code = 1 }
            }
        }
    }
}
finally { Pop-Location }
exit $code
