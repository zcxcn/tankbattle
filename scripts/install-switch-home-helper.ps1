param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
$ieRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ieSource = Join-Path $ieRoot 'outputs\switch-home\IronEmbersHome'
$ieReport = Get-Content -LiteralPath (Join-Path $ieSource 'IronEmbersHome.verification.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ieFile = Get-Item -LiteralPath (Join-Path $ieSource 'IronEmbersHome.nro')
if ($ieFile.Length -ne $ieReport.size -or (Get-FileHash -LiteralPath $ieFile.FullName).Hash.ToLowerInvariant() -ne $ieReport.output_sha256) {
    throw 'HOME helper differs from verified build'
}
function Find-IeItem($Folder, [string]$Name) {
    $ieItems = $Folder.Items()
    for ($ieI = 0; $ieI -lt $ieItems.Count; $ieI++) {
        $ieItem = $ieItems.Item($ieI)
        if ($ieItem.Name -eq $Name -or $ieItem.ExtendedProperty('System.FileName') -eq $Name) { return $ieItem }
    }
    return $null
}
function Find-IeRelative($Folder, [string]$Path) {
    $ieParts = $Path -split '[\\/]'
    $ieCurrent = $Folder
    for ($ieI = 0; $ieI -lt $ieParts.Length; $ieI++) {
        $ieItem = Find-IeItem $ieCurrent $ieParts[$ieI]
        if (-not $ieItem) { return $null }
        if ($ieI -eq $ieParts.Length - 1) { return $ieItem }
        if (-not $ieItem.IsFolder) { return $null }
        $ieCurrent = $ieItem.GetFolder
    }
}
$ieManifest = @(Get-ChildItem -LiteralPath $ieSource -File -Recurse | ForEach-Object {
    [pscustomobject]@{ path = [IO.Path]::GetRelativePath($ieSource, $_.FullName).Replace('\', '/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant() }
})
$ieShell = New-Object -ComObject Shell.Application
$ieDevices = @($ieShell.Namespace(17).Items() | Where-Object Name -eq 'Switch')
if ($ieDevices.Count -ne 1) { throw 'Expected one Switch device. Connect USB and open DBI Run MTP responder.' }
$ieDevice = $ieDevices[0]
$ieSd = Find-IeItem $ieDevice.GetFolder '1: SD Card'
if (-not $ieSd -or -not $ieSd.IsFolder) { throw 'Ordinary DBI SD Card storage unavailable; refusing to guess.' }
$ieSwitch = Find-IeItem $ieSd.GetFolder 'switch'
if (-not $ieSwitch -or -not $ieSwitch.IsFolder) { throw 'SD /switch directory unavailable.' }
$ieTarget = Find-IeItem $ieSwitch.GetFolder 'IronEmbersHome'
if (-not $VerifyOnly) {
    if ($ieTarget) { throw 'IronEmbersHome already exists. Use -VerifyOnly first; do not overwrite unknown content.' }
    Write-Output 'Copying verified build to sdmc:/switch/IronEmbersHome ...'
    $ieSwitch.GetFolder.CopyHere($ieSource, 0x414)
}
$ieDeadline = (Get-Date).AddSeconds(120)
do {
    $ieTarget = Find-IeItem $ieSwitch.GetFolder 'IronEmbersHome'
    $ieComplete = [bool]$ieTarget
    if ($ieTarget) {
        foreach ($ieRecord in $ieManifest) {
            $ieRemote = Find-IeRelative $ieTarget.GetFolder $ieRecord.path
            if (-not $ieRemote -or $ieRemote.IsFolder -or [long]$ieRemote.ExtendedProperty('System.Size') -ne $ieRecord.bytes) { $ieComplete = $false; break }
        }
    }
    if (-not $ieComplete) { Start-Sleep -Milliseconds 500 }
} while (-not $ieComplete -and (Get-Date) -lt $ieDeadline)
if (-not $ieComplete) { throw 'Upload did not reach expected sizes within 120 seconds; not verified.' }
Write-Output 'Remote lengths match. Reading back for SHA256 verification ...'
$ieCheck = Join-Path $ieRoot ('work\switch-readback-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $ieCheck | Out-Null
$ieShell.Namespace($ieCheck).CopyHere($ieTarget, 0x414)
$ieDeadline = (Get-Date).AddSeconds(120)
do {
    $ieComplete = $true
    foreach ($ieRecord in $ieManifest) {
        $ieReadback = Join-Path (Join-Path $ieCheck 'IronEmbersHome') $ieRecord.path
        if (-not (Test-Path -LiteralPath $ieReadback) -or (Get-Item -LiteralPath $ieReadback).Length -ne $ieRecord.bytes) { $ieComplete = $false; break }
    }
    if (-not $ieComplete) { Start-Sleep -Milliseconds 500 }
} while (-not $ieComplete -and (Get-Date) -lt $ieDeadline)
if (-not $ieComplete) { throw 'Readback incomplete; transfer is not yet verified.' }
foreach ($ieRecord in $ieManifest) {
    $ieReadback = Join-Path (Join-Path $ieCheck 'IronEmbersHome') $ieRecord.path
    if ((Get-FileHash -LiteralPath $ieReadback).Hash.ToLowerInvariant() -ne $ieRecord.sha256) { throw "Readback mismatch: $($ieRecord.path)" }
}
$ieReceipt = [pscustomobject]@{
    status = 'transferred_and_readback_verified'
    device = 'Switch'; storage = '1: SD Card'; destination = 'sdmc:/switch/IronEmbersHome'
    timestamp = (Get-Date).ToString('o'); files = $ieManifest
    hardware_execution_verified = $false; home_icon_installed = $false
}
$ieReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ieRoot 'outputs\switch\home-helper-install-receipt.json') -Encoding UTF8
Write-Output "Verified $($ieManifest.Count) files by full MTP readback SHA256. Open IronEmbers HOME Setup in Application-mode hbmenu, then press A."
