$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$starter=Join-Path $project 'start.cmd'
$manifest=Get-Content -LiteralPath (Join-Path $project 'profile.public.json') -Raw | ConvertFrom-Json
if($manifest.asset -notmatch '^profile-[a-f0-9]{16}\.carcar$' -or $manifest.sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Invalid public profile manifest'}
$template=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'bootstrap-profile.template.ps1'))
$crypto=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'profile-crypto.ps1'))
$install=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'command-install.ps1'))
$generated=$template.Replace('# PROFILE_CRYPTO_FUNCTIONS',$crypto).Replace('# COMMAND_INSTALL_FUNCTIONS',$install).Replace('__PROFILE_ASSET__',$manifest.asset).Replace('__PROFILE_HASH__',$manifest.sha256)
$generated=($generated -replace "`r?`n","`n").TrimEnd()+"`n"
$bootstrap=Join-Path $PSScriptRoot 'bootstrap-profile.generated.ps1'
[IO.File]::WriteAllText($bootstrap,$generated,[Text.UTF8Encoding]::new($false))
$expected=(Get-FileHash -LiteralPath $bootstrap -Algorithm SHA256).Hash.ToLowerInvariant()
$text=[IO.File]::ReadAllText($starter)
$text=$text.Replace('bootstrap-v2.ps1',('bootstrap-profile-'+$expected.Substring(0,16)+'.ps1'))
$text=[regex]::Replace($text,'bootstrap-profile-[a-f0-9]{16}\.ps1',('bootstrap-profile-'+$expected.Substring(0,16)+'.ps1'))
$text=[regex]::Replace($text,"(?<=\`$h -ne ')[a-f0-9]{64}",$expected)
if(!$text.Contains($expected)){throw 'The CMD starter does not pin the generated bootstrap hash'}
if ($text -match '[^\x00-\x7f]') { throw 'The CMD starter must contain ASCII only; localized messages belong in the PowerShell bootstrap.' }
$text=($text -replace "`r?`n","`r`n").TrimEnd()+"`r`n"
[IO.File]::WriteAllText($starter,$text,[Text.ASCIIEncoding]::new())
foreach ($name in @('c','c2','c3','c4')) { [IO.File]::WriteAllText((Join-Path $project ('docs\'+$name)),$text,[Text.ASCIIEncoding]::new()) }
