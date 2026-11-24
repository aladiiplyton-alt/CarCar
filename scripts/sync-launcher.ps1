$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$starter=Join-Path $project 'start.cmd'
$bootstrap=Join-Path $PSScriptRoot 'bootstrap-v2.ps1'
$expected=(Get-FileHash -LiteralPath $bootstrap -Algorithm SHA256).Hash.ToLowerInvariant()
$text=[IO.File]::ReadAllText($starter)
if (!$text.Contains($expected)) { throw 'start.cmd must pin the current bootstrap-v2.ps1 SHA256 before publishing.' }
if ($text -match '[^\x00-\x7f]') { throw 'The CMD starter must contain ASCII only; localized messages belong in the PowerShell bootstrap.' }
$text=($text -replace "`r?`n","`r`n").TrimEnd()+"`r`n"
[IO.File]::WriteAllText($starter,$text,[Text.ASCIIEncoding]::new())
foreach ($name in @('c','c2')) { [IO.File]::WriteAllText((Join-Path $project ('docs\'+$name)),$text,[Text.ASCIIEncoding]::new()) }
