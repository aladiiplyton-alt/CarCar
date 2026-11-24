# Portable profile: PBKDF2-HMAC-SHA256, AES-256-CBC, then HMAC-SHA256.
# The MAC covers the version, iteration count, salt, IV and ciphertext.
function Get-CarCarPasswordBytes {
    param([Security.SecureString]$Password)
    $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try { $text=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer); return ,([Text.Encoding]::UTF8.GetBytes($text)) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $text=$null }
}

function Protect-CarCarProfile {
    param([byte[]]$Plaintext,[Security.SecureString]$Password)
    $passwordBytes=$null; $material=$null; $aesKey=$null; $macKey=$null; $kdf=$null; $aes=$null; $hmac=$null; $transform=$null
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $salt=New-Object byte[] 16; $iv=New-Object byte[] 16
        $rng.GetBytes($salt); $rng.GetBytes($iv)
        $passwordBytes=Get-CarCarPasswordBytes $Password
        $kdf=[Security.Cryptography.Rfc2898DeriveBytes]::new($passwordBytes,$salt,300000,[Security.Cryptography.HashAlgorithmName]::SHA256)
        $material=$kdf.GetBytes(64); [byte[]]$aesKey=$material[0..31]; [byte[]]$macKey=$material[32..63]
        $aes=[Security.Cryptography.Aes]::Create(); $aes.KeySize=256; $aes.Mode=[Security.Cryptography.CipherMode]::CBC; $aes.Padding=[Security.Cryptography.PaddingMode]::PKCS7; $aes.Key=$aesKey; $aes.IV=$iv
        $transform=$aes.CreateEncryptor(); $cipher=$transform.TransformFinalBlock($Plaintext,0,$Plaintext.Length)
        $payload=New-Object byte[] (45+$cipher.Length)
        [Buffer]::BlockCopy([Text.Encoding]::ASCII.GetBytes('CCPROFILE'),0,$payload,0,9)
        [Buffer]::BlockCopy([BitConverter]::GetBytes([int]300000),0,$payload,9,4)
        [Buffer]::BlockCopy($salt,0,$payload,13,16); [Buffer]::BlockCopy($iv,0,$payload,29,16); [Buffer]::BlockCopy($cipher,0,$payload,45,$cipher.Length)
        $hmac=[Security.Cryptography.HMACSHA256]::new($macKey); $tag=$hmac.ComputeHash($payload)
        $result=New-Object byte[] ($payload.Length+32)
        [Buffer]::BlockCopy($payload,0,$result,0,$payload.Length); [Buffer]::BlockCopy($tag,0,$result,$payload.Length,32)
        return ,$result
    } finally {
        foreach($buffer in @($passwordBytes,$material,$aesKey,$macKey)){if($null -ne $buffer){[Array]::Clear($buffer,0,$buffer.Length)}}
        foreach($object in @($transform,$aes,$hmac,$kdf,$rng)){if($null -ne $object){$object.Dispose()}}
    }
}

function Unprotect-CarCarProfile {
    param([byte[]]$Data,[Security.SecureString]$Password)
    $passwordBytes=$null; $material=$null; $aesKey=$null; $macKey=$null; $kdf=$null; $aes=$null; $hmac=$null; $transform=$null
    try {
        if($Data.Length -lt 93 -or $Data.Length -gt 65536 -or (($Data.Length-77)%16) -ne 0){throw 'Invalid profile length'}
        if([Text.Encoding]::ASCII.GetString($Data,0,9) -ne 'CCPROFILE'){throw 'Invalid profile version'}
        $iterations=[BitConverter]::ToInt32($Data,9)
        if($iterations -lt 100000 -or $iterations -gt 1000000){throw 'Invalid profile KDF'}
        [byte[]]$salt=$Data[13..28]; [byte[]]$iv=$Data[29..44]
        $passwordBytes=Get-CarCarPasswordBytes $Password
        $kdf=[Security.Cryptography.Rfc2898DeriveBytes]::new($passwordBytes,$salt,$iterations,[Security.Cryptography.HashAlgorithmName]::SHA256)
        $material=$kdf.GetBytes(64); [byte[]]$aesKey=$material[0..31]; [byte[]]$macKey=$material[32..63]
        $authenticatedLength=$Data.Length-32
        $hmac=[Security.Cryptography.HMACSHA256]::new($macKey); $expected=$hmac.ComputeHash($Data,0,$authenticatedLength)
        $difference=0
        for($i=0;$i -lt 32;$i++){$difference=$difference -bor ($expected[$i] -bxor $Data[$authenticatedLength+$i])}
        if($difference -ne 0){throw 'Profile authentication failed'}
        $aes=[Security.Cryptography.Aes]::Create(); $aes.KeySize=256; $aes.Mode=[Security.Cryptography.CipherMode]::CBC; $aes.Padding=[Security.Cryptography.PaddingMode]::PKCS7; $aes.Key=$aesKey; $aes.IV=$iv
        $transform=$aes.CreateDecryptor()
        return ,($transform.TransformFinalBlock($Data,45,$authenticatedLength-45))
    } catch { throw 'Неверный пароль или повреждён зашифрованный профиль CarCar.' }
    finally {
        foreach($buffer in @($passwordBytes,$material,$aesKey,$macKey)){if($null -ne $buffer){[Array]::Clear($buffer,0,$buffer.Length)}}
        foreach($object in @($transform,$aes,$hmac,$kdf)){if($null -ne $object){$object.Dispose()}}
    }
}

function Read-CarCarProfileSettings {
    param([byte[]]$Data,[Security.SecureString]$Password)
    $plain=$null
    try {
        $plain=Unprotect-CarCarProfile $Data $Password
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($plain)
        $profile=ConvertFrom-Json -InputObject $json -ErrorAction Stop
        if($profile.version -ne 1 -or $profile.apiKey -isnot [string] -or $profile.baseUrl -isnot [string] -or $profile.model -isnot [string]){throw 'Invalid profile fields'}
        if(!$profile.apiKey.Trim() -or $profile.apiKey.Length -gt 4096 -or $profile.apiKey.Contains("`r") -or $profile.apiKey.Contains("`n") -or !$profile.model.Trim() -or $profile.model.Length -gt 256){throw 'Invalid profile settings'}
        $uri=$null
        if(![Uri]::TryCreate($profile.baseUrl,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment){throw 'Invalid API URL'}
        return [pscustomobject]@{apiKey=$profile.apiKey.Trim();baseUrl=$profile.baseUrl.Trim().TrimEnd('/');model=$profile.model.Trim()}
    } catch { throw 'Не удалось открыть профиль. Проверьте пароль CarCar.' }
    finally {if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}; $json=$null; $profile=$null}
}
