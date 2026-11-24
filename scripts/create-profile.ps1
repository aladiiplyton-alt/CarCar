param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'profile-crypto.ps1')
$values=@{}
foreach($line in [IO.File]::ReadAllLines([IO.Path]::GetFullPath($ConfigPath))){$parts=$line.TrimStart([char]0xfeff).Split(@('='),2);if($parts.Length -eq 2){$values[$parts[0].Trim()]=$parts[1].Trim()}}
foreach($name in @('CARCAR_API_KEY','CARCAR_BASE_URL','CARCAR_MODEL')){if(!$values[$name]){throw "Private configuration is missing $name"}}
$rng=[Security.Cryptography.RandomNumberGenerator]::Create();$random=New-Object byte[] 12
$rng.GetBytes($random);$rng.Dispose()
$hex=[BitConverter]::ToString($random).Replace('-','')
$passwordText=($hex.Substring(0,6),$hex.Substring(6,6),$hex.Substring(12,6),$hex.Substring(18,6)) -join '-'
$password=ConvertTo-SecureString -String $passwordText -AsPlainText -Force
$plain=$null
try {
    $json=@{version=1;apiKey=$values['CARCAR_API_KEY'];baseUrl=$values['CARCAR_BASE_URL'];model=$values['CARCAR_MODEL']} | ConvertTo-Json -Compress
    $plain=[Text.Encoding]::UTF8.GetBytes($json)
    $encrypted=Protect-CarCarProfile $plain $password
    $verified=Read-CarCarProfileSettings $encrypted $password
    if($verified.apiKey -ne $values['CARCAR_API_KEY'] -or $verified.baseUrl -ne $values['CARCAR_BASE_URL'].TrimEnd('/') -or $verified.model -ne $values['CARCAR_MODEL']){throw 'Profile round trip failed'}
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $sha=[Security.Cryptography.SHA256]::Create();try{$hash=[BitConverter]::ToString($sha.ComputeHash($encrypted)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    $asset='profile-'+$hash.Substring(0,16)+'.carcar'
    [IO.File]::WriteAllBytes((Join-Path $OutputDirectory $asset),$encrypted)
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'CarCar-Profile-Password.txt'),$passwordText+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    $manifest=@{version=1;asset=$asset;sha256=$hash} | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path (Split-Path $PSScriptRoot) 'profile.public.json'),$manifest+"`n",[Text.UTF8Encoding]::new($false))
    Write-Output "Encrypted profile created: $asset"
    Write-Output 'Password saved only in the private password file. Plain settings were not written to temporary files.'
} finally {
    if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
    [Array]::Clear($random,0,$random.Length);$password.Dispose();$passwordText=$null;$hex=$null;$json=$null;$values.Clear();$verified=$null
}
