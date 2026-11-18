<#
.SYNOPSIS
  Runs Tabular Editor 2 C# scripts on the model's TMDL folder and writes the result back.

.DESCRIPTION
  Loads model\UKGroupFinance.SemanticModel\definition, runs each script given with -Script
  in order, saves the model as TMDL into a scratch folder, and copies back only the files
  whose content changed (line endings are ignored when comparing). With no -Script it just
  loads and saves, which is how the files were normalised to the Tabular Editor layout.

  If TE2 or a script fails (non-zero exit code, or no output written), nothing is copied back.
  The scripts read their input files through the environment variable UKFR_REPO_ROOT, which
  this wrapper sets to the root of the checkout that holds this tool.

  Files TE2 cannot round-trip are never copied back (see -Keep). The wrapper prints the list of
  changed files. Review `git diff` after every run: TE2
  reformats TMDL, so a script that is not idempotent shows up as a second diff.

.PARAMETER Script
  One or more .csx files (paths relative to the current directory or absolute).

.PARAMETER Definition
  The TMDL definition folder. Default: model\UKGroupFinance.SemanticModel\definition of this checkout.

.PARAMETER Keep
  Files (relative to the definition folder) that stay exactly as written by hand. TE2 2.29 drops
  the `ordinal` property of calculation items and unquotes the item name Favourable/Adverse, so the
  three calculation-group tables are kept. A script that must change one of them edits it as text
  in a separate step, never through TE2.

.PARAMETER TabularEditor
  The TE2 executable. Default: TabularEditor on PATH.

.EXAMPLE
  powershell.exe -NoProfile -File tools\run_te_script.ps1 -Script te\scripts\display_folders.csx

.EXAMPLE
  # normalise only
  powershell.exe -NoProfile -File tools\run_te_script.ps1
#>
[CmdletBinding()]
param(
    [string[]] $Script = @(),
    [string] $Definition,
    [string[]] $Keep = @('tables\Display Unit.tmdl', 'tables\Time Intelligence.tmdl', 'tables\Scenario Comparison.tmdl'),
    [string] $TabularEditor = 'TabularEditor'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Definition) { $Definition = Join-Path $repo 'model\UKGroupFinance.SemanticModel\definition' }
$Definition = (Resolve-Path $Definition).Path.TrimEnd('\', '/')
$env:UKFR_REPO_ROOT = $repo

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('te_run_' + [guid]::NewGuid().ToString('N'))
try {
    $teArgs = @($Definition)
    if ($Script.Count -gt 0) {
        $teArgs += '-S'
        foreach ($s in $Script) { $teArgs += (Resolve-Path $s).Path }
    }
    $teArgs += '-TMDL'
    $teArgs += $scratch

    & $TabularEditor @teArgs | Out-Host
    $code = $LASTEXITCODE
    if ($code -ne 0) { Write-Host "TabularEditor exit code $code; nothing written back."; exit $code }
    if (-not (Test-Path (Join-Path $scratch 'model.tmdl'))) { Write-Host 'TE2 wrote no model.tmdl; nothing written back.'; exit 1 }

    function Get-NormalisedText([string] $path) {
        return ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)) -replace "`r`n", "`n"
    }

    $changed = New-Object System.Collections.Generic.List[string]
    $newFiles = Get-ChildItem $scratch -Recurse -File -Filter *.tmdl
    foreach ($f in $newFiles) {
        $rel = $f.FullName.Substring($scratch.Length).TrimStart('\', '/')
        $dest = Join-Path $Definition $rel
        if ($Keep -contains $rel) { continue }
        if (-not (Test-Path $dest)) {
            New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
            Copy-Item $f.FullName $dest
            $changed.Add("added    $rel")
        }
        elseif ((Get-NormalisedText $f.FullName) -ne (Get-NormalisedText $dest)) {
            Copy-Item $f.FullName $dest -Force
            $changed.Add("changed  $rel")
        }
    }
    foreach ($f in (Get-ChildItem $Definition -Recurse -File -Filter *.tmdl)) {
        $rel = $f.FullName.Substring($Definition.Length).TrimStart('\', '/')
        if (-not (Test-Path (Join-Path $scratch $rel))) {
            Remove-Item $f.FullName
            $changed.Add("removed  $rel")
        }
    }
    if ($changed.Count -eq 0) { Write-Host 'No file changed.' }
    else { Write-Host ("Changed files ({0}):" -f $changed.Count); $changed | Sort-Object | ForEach-Object { Write-Host "  $_" } }
}
finally {
    if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
}
exit 0
