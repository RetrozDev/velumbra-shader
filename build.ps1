#Requires -Version 5.1
param(
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$src = Join-Path $root 'src'
$dist = Join-Path $root 'dist'

$manifest = Get-Content -Raw -LiteralPath (Join-Path $src 'horizon-shaders.toml')
if ($manifest -notmatch '(?m)^version\s*=\s*"([^"]+)"') { throw 'version not found in horizon-shaders.toml' }
$version = $Matches[1]
if ($manifest -notmatch '(?m)^id\s*=\s*"([^"]+)"') { throw 'id not found in horizon-shaders.toml' }
$id = $Matches[1]

if (-not $SkipValidation) {
    $python = Get-Command python, python3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $python) { throw 'python not found (or pass -SkipValidation)' }
    & $python.Source -I (Join-Path $root 'tools/check.py') $src
    if ($LASTEXITCODE -ne 0) { throw 'the pack check failed' }
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null
$package = Join-Path $dist "$id-$version.hshader"
if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package }

$entries = @(Get-ChildItem -LiteralPath $src -Recurse -File | Sort-Object FullName | ForEach-Object {
    @{ Path = $_.FullName; Name = $_.FullName.Substring($src.Length + 1).Replace('\', '/') }
})
$entries += @{ Path = (Join-Path $root 'assets/logo-256.png'); Name = 'icon.png' }
$entries += @{ Path = (Join-Path $root 'LICENSE'); Name = 'LICENSE' }
$entries += @{ Path = (Join-Path $root 'README.md'); Name = 'README.md' }

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($package, 'Create')
try {
    foreach ($entry in $entries) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $entry.Path, $entry.Name, 'Optimal') | Out-Null
    }
} finally {
    $zip.Dispose()
}
Write-Host "built $package"
