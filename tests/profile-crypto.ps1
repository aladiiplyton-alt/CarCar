param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'scripts\profile-crypto.ps1'),[Text.Encoding]::UTF8)
. ([scriptblock]::Create($source))
$password=[Security.SecureString]::new();foreach($letter in 'fixture-only-strong-password'.ToCharArray()){$password.AppendChar($letter)};$password.MakeReadOnly()
$wrong=[Security.SecureString]::new();foreach($letter in 'wrong-fixture-password'.ToCharArray()){$wrong.AppendChar($letter)};$wrong.MakeReadOnly()
$plain=[Text.Encoding]::UTF8.GetBytes('{"version":1,"apiKey":"fixture-only-key","baseUrl":"https://api.example.test/v1","model":"fixture-model"}')
try {
    $one=Protect-CarCarProfile $plain $password
    $two=Protect-CarCarProfile $plain $password
    if([Convert]::ToBase64String($one) -eq [Convert]::ToBase64String($two)){throw 'Encryption reused salt or IV'}
    $settings=Read-CarCarProfileSettings $one $password
    if($settings.apiKey -ne 'fixture-only-key' -or $settings.baseUrl -ne 'https://api.example.test/v1' -or $settings.model -ne 'fixture-model'){throw 'Profile round trip failed'}
    foreach($case in @('password','ciphertext','iv','kdf','truncated')){
        [byte[]]$data=$one.Clone();$pw=$password
        switch($case){
            'password'{$pw=$wrong}
            'ciphertext'{$data[45]=$data[45] -bxor 1}
            'iv'{$data[29]=$data[29] -bxor 1}
            'kdf'{$data[9]=$data[9] -bxor 1}
            'truncated'{$data=$data[0..($data.Length-2)]}
        }
        $accepted=$false
        try{[void](Read-CarCarProfileSettings $data $pw);$accepted=$true}catch{}
        if($accepted){throw "Profile accepted invalid $case"}
    }
    $invalid=[Text.Encoding]::UTF8.GetBytes('{"version":1,"apiKey":"must-not-appear-in-errors","baseUrl":"http://evil.example","model":"fixture"}')
    $encrypted=Protect-CarCarProfile $invalid $password
    $rejected=$false
    try{[void](Read-CarCarProfileSettings $encrypted $password)}catch{$rejected=$true;if($_.ToString().Contains('must-not-appear-in-errors')){throw 'Secret leaked through error output'}}
    if(!$rejected){throw 'Invalid API URL was accepted'}
    Write-Output 'PASS: Windows PowerShell 5 profile encryption, random salt/IV, correct settings, wrong password, ciphertext/IV/KDF tampering, truncation, and safe validation errors.'
} finally {$password.Dispose();$wrong.Dispose();[Array]::Clear($plain,0,$plain.Length)}
