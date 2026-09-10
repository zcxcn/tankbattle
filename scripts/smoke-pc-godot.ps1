#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ArtifactDirectory = "",
    [string]$ArchivePath = "",
    [switch]$SkipLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PeMachine {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "The exported executable has no MZ header."
        }
        $stream.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0x40 -or $peOffset -gt ($stream.Length - 6)) {
            throw "The exported executable has an invalid PE offset."
        }
        $stream.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "The exported executable has no PE signature."
        }
        return $reader.ReadUInt16()
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-RelativeForwardPath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$Path
    )

    return [System.IO.Path]::GetRelativePath($BasePath, $Path).Replace("\", "/")
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($ArtifactDirectory)) {
    $ArtifactDirectory = Join-Path $repositoryRoot "outputs/pc-godot/windows-x86_64"
}
$ArtifactDirectory = (Resolve-Path -LiteralPath $ArtifactDirectory).Path

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $repositoryRoot "outputs/pc-godot/Iron-Embers-Windows-x86_64-0.4.6.zip"
}
$ArchivePath = (Resolve-Path -LiteralPath $ArchivePath).Path

$executablePath = Join-Path $ArtifactDirectory "IronEmbers.exe"
$pckPath = Join-Path $ArtifactDirectory "IronEmbers.pck"
$manifestPath = Join-Path $ArtifactDirectory "build-manifest.json"
$requiredCreditPaths = @(
    "credits/THIRD_PARTY_ASSETS.md"
    "credits/audio/battlefield/README.md"
    "credits/audio/battlefield/provenance.json"
    "credits/models/environment/CREDITS.md"
    "credits/models/environment/LICENSE.txt"
    "credits/models/ordnance/README.md"
    "credits/models/challenger2/SOURCE_LICENSE.txt"
    "credits/models/kf51/SOURCE_LICENSE.txt"
    "credits/models/kv2/SOURCE_LICENSE.txt"
) | ForEach-Object { Join-Path $ArtifactDirectory $_ }
foreach ($requiredPath in @($executablePath, $pckPath, $manifestPath) + $requiredCreditPaths) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required packaged file is missing: $requiredPath"
    }
    if ((Get-Item -LiteralPath $requiredPath).Length -eq 0) {
        throw "Required packaged file is empty: $requiredPath"
    }
}

$machine = Get-PeMachine -Path $executablePath
if ($machine -ne 0x8664) {
    throw ("Expected an AMD64 PE executable, found machine type 0x{0:X4}." -f $machine)
}

$versionInfo = (Get-Item -LiteralPath $executablePath).VersionInfo
$expectedVersionFields = [ordered]@{
    ProductName = "Iron Embers"
    CompanyName = "Iron Embers Studio"
    FileDescription = "Iron Embers — Native PC Tank Combat"
    FileVersion = "0.4.6.0"
    ProductVersion = "0.4.6.0"
}
foreach ($entry in $expectedVersionFields.GetEnumerator()) {
    if ([string]$versionInfo.($entry.Key) -ne [string]$entry.Value) {
        throw "Unexpected $($entry.Key) resource: '$($versionInfo.($entry.Key))'."
    }
}

$manifestText = Get-Content -LiteralPath $manifestPath -Raw
if ($manifestText -match '(?i)(?:[A-Z]:\\Users\\|/Users/|/home/)') {
    throw "The build manifest contains a personal filesystem path."
}
$manifest = $manifestText | ConvertFrom-Json
if ($manifest.product -ne "Iron Embers" -or $manifest.target -ne "windows-x86_64") {
    throw "The build manifest identity is invalid."
}

$expectedPayload = @{}
foreach ($fileRecord in @($manifest.files)) {
    $relativePath = [string]$fileRecord.path
    if ([System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|/)\.\.(/|$)') {
        throw "Unsafe path in build manifest: $relativePath"
    }
    $payloadPath = [System.IO.Path]::GetFullPath((Join-Path $ArtifactDirectory $relativePath))
    $artifactPrefix = $ArtifactDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $payloadPath.StartsWith($artifactPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest path escapes the artifact directory: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
        throw "Manifest payload is missing: $relativePath"
    }
    $actualFile = Get-Item -LiteralPath $payloadPath
    if ($actualFile.Length -ne [long]$fileRecord.size) {
        throw "Size mismatch for $relativePath."
    }
    $actualHash = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne [string]$fileRecord.sha256) {
        throw "SHA-256 mismatch for $relativePath."
    }
    $expectedPayload[$relativePath] = $true
}

$actualPayload = @(
    Get-ChildItem -LiteralPath $ArtifactDirectory -File -Recurse |
        Where-Object { $_.FullName -ne $manifestPath } |
        ForEach-Object { Get-RelativeForwardPath -BasePath $ArtifactDirectory -Path $_.FullName }
)
foreach ($relativePath in $actualPayload) {
    if (-not $expectedPayload.ContainsKey($relativePath)) {
        throw "Unlisted payload file found: $relativePath"
    }
    if ($relativePath -match '(?i)(^|/)(tests?|\.godot)(/|$)|\.(pdb|log|tmp|gd|tscn)$') {
        throw "Development-only file found in package: $relativePath"
    }
}
if ($actualPayload.Count -ne $expectedPayload.Count) {
    throw "The manifest contains duplicate or stale payload entries."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
try {
    $archiveFiles = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
    foreach ($entry in $archiveFiles) {
        if ($entry.FullName -match '(^|/)\.\.(/|$)' -or $entry.FullName.Contains(":")) {
            throw "Unsafe ZIP entry: $($entry.FullName)"
        }
        if ($entry.FullName -match '(?i)(^|/)(tests?|\.godot)(/|$)|\.(pdb|log|tmp|gd|tscn)$') {
            throw "Development-only ZIP entry: $($entry.FullName)"
        }
    }
    $expectedArchiveNames = @($actualPayload + "build-manifest.json" | Sort-Object)
    $actualArchiveNames = @($archiveFiles.FullName | ForEach-Object { $_.Replace("\", "/") } | Sort-Object)
    if (($expectedArchiveNames -join "`n") -ne ($actualArchiveNames -join "`n")) {
        throw "ZIP contents do not match the validated artifact directory."
    }
} finally {
    $archive.Dispose()
}

if (-not $SkipLaunch) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $executablePath
    $startInfo.WorkingDirectory = $ArtifactDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @("--headless", "--quit-after", "180", "--", "--smoke-test", "--test")) {
        $startInfo.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "The packaged game process could not be started."
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(45000)) {
            $process.Kill($true)
            throw "The packaged game did not complete its 180-frame smoke run within 45 seconds."
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "The packaged game exited with code $($process.ExitCode).`n$stdout`n$stderr"
        }
        if (($stdout + "`n" + $stderr) -match '(?m)^(?:SCRIPT ERROR|ERROR):') {
            throw "The packaged game reported a runtime error.`n$stdout`n$stderr"
        }
    } finally {
        $process.Dispose()
    }
}

$signatureStatus = (Get-AuthenticodeSignature -LiteralPath $executablePath).Status
Write-Host "Packaged build passed structural, hash, metadata, archive, and launch checks."
[pscustomobject]@{
    Executable = $executablePath
    Architecture = "AMD64"
    Archive = $ArchivePath
    SignatureStatus = [string]$signatureStatus
    LaunchChecked = -not $SkipLaunch
} | Format-List
