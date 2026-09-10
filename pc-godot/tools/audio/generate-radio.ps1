param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$repositoryDirectory = Split-Path -Parent $projectDirectory
$radioLines = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'radio_lines.json') | ConvertFrom-Json
$rawDirectory = Join-Path $repositoryDirectory 'work/pc040-radio-raw'
$assetDirectory = Join-Path $projectDirectory 'assets/audio/battlefield/radio'
New-Item -ItemType Directory -Force -Path $rawDirectory, $assetDirectory | Out-Null
$speaker = New-Object -ComObject SAPI.SpVoice
$chineseVoice = @($speaker.GetVoices() | Where-Object { $_.GetDescription() -match 'Huihui.*Chinese' })[0]
if (-not $chineseVoice) { throw 'Install the Windows Microsoft Huihui desktop voice to regenerate Chinese clips.' }
$speaker.Voice = $chineseVoice
$speaker.Rate = 1
$speaker.Volume = 100
foreach ($line in $radioLines.PSObject.Properties) {
  $stream = New-Object -ComObject SAPI.SpFileStream
  $stream.Format.Type = 22
  $stream.Open((Join-Path $rawDirectory ($line.Name + '.wav')), 3, $false)
  try {
    $speaker.AudioOutputStream = $stream
    $null = $speaker.Speak($line.Value)
  } finally { $stream.Close() }
}
& $Python (Join-Path $repositoryDirectory 'scripts/process-radio.py') $rawDirectory $assetDirectory
if ($LASTEXITCODE -ne 0) { throw 'Radio processing failed.' }
