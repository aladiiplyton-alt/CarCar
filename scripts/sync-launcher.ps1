$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$starter=Join-Path $project 'start.cmd'
$bootstrap=Join-Path $PSScriptRoot 'bootstrap-v2.ps1'
$expected=(Get-FileHash -LiteralPath $bootstrap -Algorithm SHA256).Hash.ToLowerInvariant()
$text=[IO.File]::ReadAllText($starter)
if (!$text.Contains($expected)) { throw 'start.cmd must pin the current bootstrap-v2.ps1 SHA256 before publishing.' }
[IO.File]::WriteAllText((Join-Path $project 'docs\c'),$text,[Text.UTF8Encoding]::new($false))
