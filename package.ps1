# Builds the zip an addon site expects: one folder named after the addon, with the files inside it.
#
# Compress-Archive is not used. On this PowerShell it writes backslashes as the path separator inside
# the archive, which is not what a zip is meant to hold: some unpackers then make one file called
# "MacroBench\Core.lua" rather than a folder with Core.lua in it. Windows' own bsdtar writes them the
# way the format says, so that is what builds it.
#
#   .\package.ps1            builds MacroBench-<version>.zip beside your other addon zips
#   .\package.ps1 -Out .     builds it here instead

param(
    [string]$Out = "$env:USERPROFILE"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$name = "MacroBench"

# The version is whatever the TOC says, so the zip can never be named after a different one.
$toc = Get-Content (Join-Path $root "$name.toc")
$version = ($toc | Select-String '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()

# What goes in: the addon itself, and the two files worth reading beside it. The listing copy and
# this script stay behind.
$files = @(
    "$name.toc", "$name.xml",
    "Core.lua", "Grammar.lua", "Validate.lua", "Templates.lua", "Tutorial.lua", "UI.lua",
    "README.md", "CHANGELOG.md"
)

$stage = Join-Path $env:TEMP "$name-package"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path (Join-Path $stage $name) | Out-Null
foreach ($f in $files) {
    Copy-Item (Join-Path $root $f) (Join-Path $stage "$name\$f")
}

$zip = Join-Path $Out "$name-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Push-Location $stage
try {
    & "$env:SystemRoot\System32\tar.exe" -a -c -f $zip $name
    if ($LASTEXITCODE -ne 0) { throw "tar would not build the zip" }
} finally {
    Pop-Location
}

Copy-Item (Join-Path $root "CHANGELOG.md") (Join-Path $Out "$name-$version-changelog.md") -Force
Remove-Item -Recurse -Force $stage

"{0}  ({1:N0} bytes)" -f $zip, (Get-Item $zip).Length
