$ErrorActionPreference='Stop'
$ieRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ieSource=Join-Path $ieRoot 'outputs\switch\IronEmbers'
$iePrevious=Get-Content -LiteralPath (Join-Path $ieRoot 'outputs\switch\install-receipt.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($iePrevious.status -ne 'transferred_and_readback_verified' -or $iePrevious.destination -ne 'sdmc:/switch/IronEmbers') { throw 'A verified installation receipt is required.' }
function Find-IeItem($Folder,[string]$Name) {
    foreach ($ieItem in $Folder.Items()) {
        if ($ieItem.ExtendedProperty('System.FileName') -eq $Name -or $ieItem.Name -eq $Name) { return $ieItem }
    }
    return $null
}
$ieShell=New-Object -ComObject Shell.Application
$ieDevices=@($ieShell.Namespace(17).Items() | Where-Object Name -eq 'Switch')
if ($ieDevices.Count -ne 1) { throw 'Connect Switch and open DBI MTP to update the game.' }
$ieSd=Find-IeItem $ieDevices[0].GetFolder '1: SD Card'
$ieSwitch=Find-IeItem $ieSd.GetFolder 'switch'
$ieTarget=Find-IeItem $ieSwitch.GetFolder 'IronEmbers'
if (-not $ieTarget -or -not $ieTarget.IsFolder) { throw 'The previously installed game is missing.' }
$ieChanged=@()
foreach ($ieFile in Get-ChildItem -LiteralPath $ieSource -File) {
    $ieOld=@($iePrevious.files | Where-Object path -eq $ieFile.Name)
    if ($ieOld.Count -ne 1) { throw "No prior provenance for $($ieFile.Name)" }
    $ieNewHash=(Get-FileHash -LiteralPath $ieFile.FullName).Hash.ToLowerInvariant()
    if ($ieNewHash -eq $ieOld[0].sha256) { continue }
    $ieRemote=Find-IeItem $ieTarget.GetFolder $ieFile.Name
    if (-not $ieRemote -or $ieRemote.IsFolder -or [long]$ieRemote.ExtendedProperty('System.Size') -ne $ieOld[0].bytes) { throw 'Remote game changed since installation; inspect before updating.' }
    $ieChanged += [pscustomobject]@{ file=$ieFile; previous=$ieOld[0]; remote=$ieRemote }
}
$ieReadback=Join-Path $ieRoot ('work\switch-before-update-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $ieReadback | Out-Null
Write-Output "Verifying $($ieChanged.Count) existing files before updating ..."
foreach ($ieRecord in $ieChanged) { $ieShell.Namespace($ieReadback).CopyHere($ieRecord.remote,0x414) }
$ieDeadline=(Get-Date).AddSeconds(120)
do {
    $ieComplete=$true
    foreach ($ieRecord in $ieChanged) {
        $iePath=Join-Path $ieReadback $ieRecord.file.Name
        if (-not (Test-Path -LiteralPath $iePath) -or (Get-Item -LiteralPath $iePath).Length -ne $ieRecord.previous.bytes) { $ieComplete=$false; break }
    }
    if (-not $ieComplete) { Start-Sleep -Milliseconds 500 }
} while (-not $ieComplete -and (Get-Date) -lt $ieDeadline)
if (-not $ieComplete) { throw 'Previous file readback timed out; nothing was overwritten.' }
foreach ($ieRecord in $ieChanged) {
    if ((Get-FileHash -LiteralPath (Join-Path $ieReadback $ieRecord.file.Name)).Hash.ToLowerInvariant() -ne $ieRecord.previous.sha256) { throw 'Remote file differs from our prior release; no files overwritten.' }
}
Write-Output 'Previous hashes confirmed. Updating only changed release files ...'
foreach ($ieRecord in $ieChanged) { $ieTarget.GetFolder.CopyHere($ieRecord.file.FullName,0x414) }
# The original installer waits for new sizes and then performs a full readback.
& (Join-Path $ieRoot 'switch-godot\tools\install-mtp.ps1') -VerifyOnly
