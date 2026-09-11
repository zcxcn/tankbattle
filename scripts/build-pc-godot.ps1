#Requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",

    [string]$GodotPath = "",

    [switch]$SkipTests,

    [switch]$SkipLaunchSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-LastExitCode {
    param([Parameter(Mandatory)][string]$Action)

    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

function Get-RequiredPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description was not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$projectRoot = Get-RequiredPath -Path (Join-Path $repositoryRoot "pc-godot") -Description "Godot project"
$projectFile = Get-RequiredPath -Path (Join-Path $projectRoot "project.godot") -Description "Godot project file"
$mainScene = Get-RequiredPath -Path (Join-Path $projectRoot "scenes/main/main.tscn") -Description "Main scene"
$icon = Get-RequiredPath -Path (Join-Path $projectRoot "assets/branding/icon.svg") -Description "Application icon"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    if (-not [string]::IsNullOrWhiteSpace($env:IRON_EMBERS_GODOT)) {
        $GodotPath = $env:IRON_EMBERS_GODOT
    } else {
        $GodotPath = Join-Path $repositoryRoot "work/tools/godot-4.7.2/editor/Godot_v4.7.2-stable_win64_console.exe"
    }
}
$GodotPath = Get-RequiredPath -Path $GodotPath -Description "Godot 4.7.2 console executable"
$expectedGodotHash = "c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643"
$actualGodotHash = (Get-FileHash -LiteralPath $GodotPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualGodotHash -ne $expectedGodotHash) {
    throw "Godot executable SHA-256 does not match the pinned official 4.7.2 build."
}

$templateName = if ($Configuration -eq "Release") {
    "windows_release_x86_64.exe"
} else {
    "windows_debug_x86_64.exe"
}
$templatePath = Get-RequiredPath -Path (Join-Path $repositoryRoot "work/tools/godot-4.7.2/templates/$templateName") -Description "$Configuration export template"
$expectedTemplateHash = if ($Configuration -eq "Release") {
    "d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562"
} else {
    "51498b72b3a237f882ebd7d1787f06a4bc1eaf0572daab93837adcfd3cfdc107"
}
$actualTemplateHash = (Get-FileHash -LiteralPath $templatePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualTemplateHash -ne $expectedTemplateHash) {
    throw "$Configuration template SHA-256 does not match the pinned official Godot 4.7.2 template."
}

$versionOutput = @(& $GodotPath --version)
Assert-LastExitCode -Action "Godot version check"
$godotVersion = [string]($versionOutput | Select-Object -First 1)
if (-not $godotVersion.StartsWith("4.7.2.stable.official", [System.StringComparison]::Ordinal)) {
    throw "Expected official Godot 4.7.2, found '$godotVersion'."
}

Write-Host "Importing and validating project resources with Godot $godotVersion..."
& $GodotPath --headless --editor --path $projectRoot --quit
Assert-LastExitCode -Action "Godot project import"

if (-not $SkipTests) {
    Write-Host "Running deterministic logic tests..."
    & $GodotPath --headless --path $projectRoot --script "res://tests/test_runner.gd" -- --test
    Assert-LastExitCode -Action "Godot logic tests"

    Write-Host "Running scene integration tests..."
    & $GodotPath --headless --path $projectRoot "res://tests/integration_scene.tscn" -- --test
    Assert-LastExitCode -Action "Godot integration tests"

    Write-Host "Running imported wheel geometry and motion tests..."
    & $GodotPath --headless --path $projectRoot --script "res://tests/tracked_drive_test.gd" -- --test
    Assert-LastExitCode -Action "Godot tracked drive tests"

    Write-Host "Running explosion particle resource tests..."
    & $GodotPath --headless --path $projectRoot "res://tests/explosion_fx_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot explosion particle tests"

    Write-Host "Running UI construction smoke tests..."
    & $GodotPath --headless --path $projectRoot --script "res://ui/game_ui_smoke_test.gd" -- --test
    Assert-LastExitCode -Action "Godot UI smoke tests"

    Write-Host "Running combat flow and mine regression tests..."
    & $GodotPath --headless --path $projectRoot --script "res://tests/combat_regression_test.gd" -- --test
    Assert-LastExitCode -Action "Godot combat regression tests"

    Write-Host "Running vehicle and weapon regression tests..."
    & $GodotPath --headless --path $projectRoot "res://tests/vehicle_regression_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot vehicle regression tests"

    Write-Host "Running battle overlay tests..."
    & $GodotPath --headless --path $projectRoot --script "res://tests/battle_overlay_test.gd" -- --test
    Assert-LastExitCode -Action "Godot battle overlay tests"

    Write-Host "Running tactical pacing, crew response and resupply regressions..."
    & $GodotPath --headless --path $projectRoot "res://tests/pacing_regression_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot tactical pacing tests"

    Write-Host "Running weapon, ballistics, navigation and campaign tests..."
    & $GodotPath --headless --path $projectRoot --script "res://tests/field_combat_test.gd" -- --test
    Assert-LastExitCode -Action "Godot field combat tests"
    & $GodotPath --headless --path $projectRoot "res://tests/ballistics_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot ballistic collision tests"
    & $GodotPath --headless --path $projectRoot "res://tests/barrel_elevation_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot weapon elevation tests"
    & $GodotPath --headless --path $projectRoot "res://tests/mission_navigation_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot map navigation tests"
    & $GodotPath --headless --path $projectRoot "res://tests/campaign_regression_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot campaign progression tests"
    & $GodotPath --headless --path $projectRoot --script "res://tests/camera_regression_test.gd" -- --test
    Assert-LastExitCode -Action "Godot camera collision tests"
    & $GodotPath --headless --path $projectRoot "res://tests/remote_mouse_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot remote desktop absolute mouse tests"
    & $GodotPath --headless --path $projectRoot --script "res://tests/recoil_regression_test.gd" -- --test
    Assert-LastExitCode -Action "Godot mechanical and camera recoil tests"
    & $GodotPath --headless --path $projectRoot "res://tests/hit_feedback_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot incoming damage feedback tests"
    & $GodotPath --headless --path $projectRoot --script "res://tests/gamepad_regression_test.gd" -- --test
    Assert-LastExitCode -Action "Godot controller input and menu tests"

    Write-Host "Running expanded deployment, wreck and battlefield audio tests..."
    & $GodotPath --headless --path $projectRoot --script "res://tests/deployment_expansion_test.gd" -- --test
    Assert-LastExitCode -Action "Godot expanded deployment tests"
    & $GodotPath --headless --path $projectRoot "res://tests/tank_wreck_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot wreck and cookoff tests"
    & $GodotPath --headless --path $projectRoot "res://tests/audio_battlefield_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot battlefield audio tests"
    & $GodotPath --headless --path $projectRoot "res://tests/weapon_audio_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot recorded weapon mixer capture tests"
    & $GodotPath --headless --path $projectRoot "res://tests/impact_audio_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot incoming armor impact mixer capture tests"
    & $GodotPath --headless --path $projectRoot --script "res://tests/weather_regression_test.gd" -- --test
    Assert-LastExitCode -Action "Godot rain, roof shelter and wet terrain tests"
    & $GodotPath --headless --path $projectRoot --script "res://tests/track_marks_test.gd" -- --test
    Assert-LastExitCode -Action "Godot track mark surface and lifecycle tests"
    & $GodotPath --headless --path $projectRoot --script "res://tests/weather_settings_test.gd" -- --test
    Assert-LastExitCode -Action "Godot random weather preferences and live settings tests"
    & $GodotPath --headless --path $projectRoot "res://tests/river_terrain_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot river bridge and terrain geometry tests"
    & $GodotPath --headless --path $projectRoot "res://tests/world_weather_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot city terrain weather integration tests"
    & $GodotPath --headless --fixed-fps 60 --path $projectRoot "res://tests/world_traversal_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot actual tank bridge and hill traversal tests"
    & $GodotPath --headless --fixed-fps 60 --path $projectRoot "res://tests/river_navigation_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot enemy river crossing navigation tests"
    & $GodotPath --headless --path $projectRoot "res://tests/city_architecture_test.tscn" -- --test
    Assert-LastExitCode -Action "Godot modeled city architecture tests"
}

$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "outputs/pc-godot"))
$artifactDirectoryName = if ($Configuration -eq "Release") { "windows-x86_64" } else { "windows-x86_64-debug" }
$artifactDirectory = [System.IO.Path]::GetFullPath((Join-Path $outputRoot $artifactDirectoryName))
$outputPrefix = $outputRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $artifactDirectory.StartsWith($outputPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to prepare an output directory outside $outputRoot."
}
if (Test-Path -LiteralPath $artifactDirectory) {
    Remove-Item -LiteralPath $artifactDirectory -Recurse -Force
}
[System.IO.Directory]::CreateDirectory($artifactDirectory) | Out-Null

$executablePath = Join-Path $artifactDirectory "IronEmbers.exe"
$exportFlag = if ($Configuration -eq "Release") { "--export-release" } else { "--export-debug" }
Write-Host "Exporting $Configuration Windows x86_64 build..."
& $GodotPath --headless --path $projectRoot $exportFlag "Windows Desktop" $executablePath
Assert-LastExitCode -Action "Godot Windows export"

$pckPath = Join-Path $artifactDirectory "IronEmbers.pck"
Get-RequiredPath -Path $executablePath -Description "Exported executable" | Out-Null
Get-RequiredPath -Path $pckPath -Description "Exported PCK" | Out-Null

$creditSources = [ordered]@{
    "THIRD_PARTY_ASSETS.md" = "assets/THIRD_PARTY_ASSETS.md"
    "audio/README.md" = "assets/audio/combat/README.md"
    "audio/provenance.json" = "assets/audio/combat/provenance.json"
    "audio/battlefield/README.md" = "assets/audio/battlefield/README.md"
    "audio/battlefield/provenance.json" = "assets/audio/battlefield/provenance.json"
    "audio/battlefield/radio/credits/Kenney-Voiceover-License.txt" = "assets/audio/battlefield/radio/credits/Kenney-Voiceover-License.txt"
    "audio/battlefield/radio/credits/Kenney-Voiceover-Credits.txt" = "assets/audio/battlefield/radio/credits/Kenney-Voiceover-Credits.txt"
    "fx/fluid/README.md" = "assets/fx/fluid/README.md"
    "fx/fluid/provenance.json" = "assets/fx/fluid/provenance.json"
    "models/environment/CREDITS.md" = "assets/models/environment/polyhaven_factory/CREDITS.md"
    "models/environment/LICENSE.txt" = "assets/models/environment/polyhaven_factory/LICENSE.txt"
    "models/environment/rock09/CREDITS.md" = "assets/models/environment/polyhaven_rock09/CREDITS.md"
    "models/environment/rock09/LICENSE.txt" = "assets/models/environment/polyhaven_rock09/LICENSE.txt"
    "models/environment/concrete_facade/CREDITS.md" = "assets/models/environment/polyhaven_concrete_facade/CREDITS.md"
    "models/environment/concrete_facade/LICENSE.txt" = "assets/models/environment/polyhaven_concrete_facade/LICENSE.txt"
    "models/environment/aerial_grass/CREDITS.md" = "assets/models/environment/polyhaven_aerial_grass/CREDITS.md"
    "models/environment/aerial_grass/LICENSE.txt" = "assets/models/environment/polyhaven_aerial_grass/LICENSE.txt"
    "models/ordnance/README.md" = "assets/models/ordnance/README.md"
    "models/challenger2/SOURCE_LICENSE.txt" = "assets/models/realistic/challenger2/SOURCE_LICENSE.txt"
    "models/kf51/SOURCE_LICENSE.txt" = "assets/models/realistic/kf51/SOURCE_LICENSE.txt"
    "models/kv2/SOURCE_LICENSE.txt" = "assets/models/realistic/kv2/SOURCE_LICENSE.txt"
}
$creditsDirectory = Join-Path $artifactDirectory "credits"
foreach ($credit in $creditSources.GetEnumerator()) {
    $sourcePath = Get-RequiredPath -Path (Join-Path $projectRoot $credit.Value) -Description "Third-party credit"
    $destinationPath = Join-Path $creditsDirectory $credit.Key
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destinationPath)) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
    if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf) -or (Get-Item -LiteralPath $destinationPath).Length -eq 0) {
        throw "Third-party credit was not packaged correctly: $destinationPath"
    }
}

$productVersion = "0.4.7"
$manifestPath = Join-Path $artifactDirectory "build-manifest.json"
$payloadFiles = @(Get-ChildItem -LiteralPath $artifactDirectory -File -Recurse | Sort-Object FullName)
$manifestFiles = @(
    foreach ($file in $payloadFiles) {
        $relativePath = [System.IO.Path]::GetRelativePath($artifactDirectory, $file.FullName).Replace("\", "/")
        [ordered]@{
            path = $relativePath
            size = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
)
$manifest = [ordered]@{
    manifest_version = 1
    product = "Iron Embers"
    product_version = $productVersion
    configuration = $Configuration
    engine = "Godot"
    engine_version = $godotVersion
    target = "windows-x86_64"
    files = $manifestFiles
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM

$archiveName = if ($Configuration -eq "Release") {
    "Iron-Embers-Windows-x86_64-$productVersion.zip"
} else {
    "Iron-Embers-Windows-x86_64-$productVersion-Debug.zip"
}
$archivePath = Join-Path $outputRoot $archiveName
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $archiveTimestamp = [System.DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
    foreach ($file in @(Get-ChildItem -LiteralPath $artifactDirectory -File -Recurse | Sort-Object FullName)) {
        $relativePath = [System.IO.Path]::GetRelativePath($artifactDirectory, $file.FullName).Replace("\", "/")
        $entry = $archive.CreateEntry($relativePath, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $archiveTimestamp
        $entryStream = $entry.Open()
        $fileStream = [System.IO.File]::OpenRead($file.FullName)
        try {
            $fileStream.CopyTo($entryStream)
        } finally {
            $fileStream.Dispose()
            $entryStream.Dispose()
        }
    }
} finally {
    $archive.Dispose()
}

$smokeArguments = @(
    "-NoProfile",
    "-File", (Join-Path $PSScriptRoot "smoke-pc-godot.ps1"),
    "-ArtifactDirectory", $artifactDirectory,
    "-ArchivePath", $archivePath
)
if ($SkipLaunchSmoke) {
    $smokeArguments += "-SkipLaunch"
}
& pwsh @smokeArguments
Assert-LastExitCode -Action "Packaged build smoke test"

Write-Host "Build complete."
[pscustomobject]@{
    Executable = $executablePath
    DataPack = $pckPath
    Manifest = $manifestPath
    Archive = $archivePath
    Template = $templatePath
} | Format-List
