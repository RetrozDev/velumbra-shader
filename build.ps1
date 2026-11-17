#Requires -Version 5.1
param(
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$src = Join-Path $root 'src'
$prelude = Join-Path $root 'tools/prelude'
$dist = Join-Path $root 'dist'

$manifest = Get-Content -Raw -LiteralPath (Join-Path $src 'horizon-shaders.toml')
if ($manifest -notmatch '(?m)^version\s*=\s*"([^"]+)"') { throw 'version not found in horizon-shaders.toml' }
$version = $Matches[1]
if ($manifest -notmatch '(?m)^id\s*=\s*"([^"]+)"') { throw 'id not found in horizon-shaders.toml' }
$id = $Matches[1]

# Each module is what Horizon compiles: its prelude, the shared files, then the stage's files.
$modules = @(
    'sky:sky.wgsl'
    'terrain:material.wgsl vertex.wgsl'
    'weather:weather.wgsl'
    'post:post/atmosphere.wgsl'
    'post:post/grade.wgsl'
)

if (-not $SkipValidation) {
    $naga = Get-Command naga -ErrorAction SilentlyContinue
    if (-not $naga) { throw 'naga not found: cargo install naga-cli (or pass -SkipValidation)' }
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "velumbra-validate-$PID"
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $failed = $false
    try {
        foreach ($module in $modules) {
            $name, $list = $module -split ':', 2
            $files = $list -split ' '
            $parts = @((Join-Path $prelude 'base.wgsl'), (Join-Path $prelude "$name.wgsl"), (Join-Path $src 'common.wgsl'))
            $parts += $files | ForEach-Object { Join-Path $src $_ }
            $label = ($files -join ' + ')
            $out = Join-Path $work (($label -replace '[^A-Za-z0-9]+', '_') + '.wgsl')
            ($parts | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join "`n" | Set-Content -LiteralPath $out -Encoding ascii -NoNewline
            # Windows PowerShell turns a native command's stderr into terminating errors under Stop.
            $ErrorActionPreference = 'Continue'
            $result = & $naga.Source $out 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" } }
            $exit = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($exit -ne 0) {
                $failed = $true
                Write-Host "FAIL $label" -ForegroundColor Red
                $result | ForEach-Object { Write-Host "  $_" }
            } else {
                Write-Host "ok   $label"
            }
        }
    } finally {
        Remove-Item -Recurse -Force -LiteralPath $work
    }
    if ($failed) { throw 'WGSL validation failed' }
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null
$package = Join-Path $dist "$id-$version.hshader"
if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package }

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($package, 'Create')
try {
    $entries = @(Get-ChildItem -LiteralPath $src -Recurse -File | ForEach-Object {
        @{ Path = $_.FullName; Name = $_.FullName.Substring($src.Length + 1).Replace('\', '/') }
    })
    $entries += @{ Path = (Join-Path $root 'LICENSE'); Name = 'LICENSE' }
    $entries += @{ Path = (Join-Path $root 'README.md'); Name = 'README.md' }
    foreach ($entry in $entries) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $entry.Path, $entry.Name, 'Optimal') | Out-Null
    }
} finally {
    $zip.Dispose()
}
Write-Host "built $package"
