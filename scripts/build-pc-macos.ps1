#Requires -Version 7.0
[CmdletBinding()]
param([string]$GodotPath = "", [string]$PythonPath = "")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$projectRoot = Join-Path $repositoryRoot "pc-godot"
$toolRoot = Join-Path $repositoryRoot "work/tools/godot-4.7.2"
if (-not $GodotPath) { $GodotPath = Join-Path $toolRoot "editor/Godot_v4.7.2-stable_win64_console.exe" }
if (-not $PythonPath) {
    $bundledPython = Join-Path $env:USERPROFILE ".cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
    $PythonPath = if (Test-Path -LiteralPath $bundledPython) { $bundledPython } else { (Get-Command python -ErrorAction Stop).Source }
}
if ((Get-FileHash -LiteralPath $GodotPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne "c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643") {
    throw "Godot must match the pinned official 4.7.2 Windows editor."
}
$templatePath = Join-Path $toolRoot "templates/macos.zip"
if (-not (Test-Path -LiteralPath $templatePath)) {
    $archivePath = Join-Path $toolRoot "Godot_v4.7.2-stable_export_templates.tpz"
    $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA512).Hash.ToLowerInvariant()
    if ($archiveHash -ne "ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079") {
        throw "Export templates archive failed the official SHA-512 check."
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sourceZip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entry = $sourceZip.GetEntry("templates/macos.zip")
        if ($null -eq $entry) { throw "macOS export template missing from archive." }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $templatePath, $false)
    } finally { $sourceZip.Dispose() }
}
if ((Get-FileHash -LiteralPath $templatePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne "88df5e2e6fee99088699be66e6d42e4da4fb0c5619d054297d755a49558a4792") {
    throw "macOS template hash mismatch."
}
$stageDirectory = Join-Path $repositoryRoot "work/mac-export"
[System.IO.Directory]::CreateDirectory($stageDirectory) | Out-Null
$rawArchive = Join-Path $stageDirectory "IronEmbers.raw.zip"
$outputArchive = Join-Path $repositoryRoot "outputs/pc-godot/Iron-Embers-macOS-Universal-0.4.10.zip"
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputArchive)) | Out-Null

Write-Host "Importing ARM64 texture variants..."
& $GodotPath --headless --editor --path $projectRoot --quit
if ($LASTEXITCODE -ne 0) { throw "Godot resource import failed." }
Write-Host "Exporting signed Universal 2 macOS application directly to a Unix-permission-preserving ZIP..."
& $GodotPath --headless --path $projectRoot --export-release "macOS Universal" $rawArchive
if ($LASTEXITCODE -ne 0) { throw "macOS export failed." }
& $PythonPath (Join-Path $PSScriptRoot "package-macos.py") $rawArchive $outputArchive
if ($LASTEXITCODE -ne 0) { throw "macOS packaging failed." }
& $PythonPath (Join-Path $PSScriptRoot "verify-macos-package.py") $outputArchive --require-extras
if ($LASTEXITCODE -ne 0) { throw "macOS archive verification failed." }
Get-FileHash -LiteralPath $outputArchive -Algorithm SHA256 | Format-List
Write-Host "macOS package complete: $outputArchive"
Write-Host "The macOS executable cannot be launched on this Windows build host."
