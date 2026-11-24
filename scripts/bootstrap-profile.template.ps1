param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,[Security.SecureString]$ProfilePassword)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

# PROFILE_CRYPTO_FUNCTIONS

function Get-CarCarVerifiedBytes {
    param([string]$Uri,[string]$Hash,[int]$Maximum)
    for($attempt=1;$attempt -le 3;$attempt++){
        try {
            $response=Invoke-WebRequest -UseBasicParsing -TimeoutSec 40 -Uri ($Uri+'?carcar='+[guid]::NewGuid())
            if($response.Content -isnot [byte[]]){throw 'Expected a binary release asset'}
            [byte[]]$bytes=$response.Content
            if($bytes.Length -eq 0 -or $bytes.Length -gt $Maximum){throw 'Invalid asset size'}
            $hasher=[Security.Cryptography.SHA256]::Create()
            try {$actual=[BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$hasher.Dispose()}
            if($actual -ne $Hash){throw 'Release asset SHA256 mismatch'}
            return ,$bytes
        }catch{if($attempt -eq 3){throw 'Не удалось скачать проверенные файлы CarCar. Проверьте доступ к GitHub и повторите запуск.'};Write-Host 'CarCar: повторная загрузка…';Start-Sleep -Seconds 2}
    }
}

$environmentNames=@('CARCAR_API_KEY','CARCAR_BASE_URL','CARCAR_MODEL')
$previous=@{}
foreach($name in $environmentNames){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$settings=$null
try {
    $encrypted=Get-CarCarVerifiedBytes -Uri 'https://github.com/aladiiplyton-alt/CarCar/releases/download/v1.0.0/__PROFILE_ASSET__' -Hash '__PROFILE_HASH__' -Maximum 65536
    if($null -ne $ProfilePassword){$settings=Read-CarCarProfileSettings $encrypted $ProfilePassword}
    else {
        for($attempt=1;$attempt -le 3;$attempt++){
            $password=Read-Host -Prompt 'Пароль CarCar' -AsSecureString
            try {$settings=Read-CarCarProfileSettings $encrypted $password;break}
            catch{if($attempt -eq 3){throw 'Пароль CarCar не принят. Запустите команду ещё раз с верным паролем.'};Write-Host 'Неверный пароль. Повторите ввод.'}
            finally{$password.Dispose()}
        }
    }
    [Environment]::SetEnvironmentVariable('CARCAR_API_KEY',$settings.apiKey,'Process')
    [Environment]::SetEnvironmentVariable('CARCAR_BASE_URL',$settings.baseUrl,'Process')
    [Environment]::SetEnvironmentVariable('CARCAR_MODEL',$settings.model,'Process')
    Write-Host 'Профиль открыт. Запускаю CarCar…'
    $bootstrap=Get-CarCarVerifiedBytes -Uri 'https://github.com/aladiiplyton-alt/CarCar/releases/download/v1.0.0/bootstrap-v2.ps1' -Hash '1cadfedd0cdfde937e3ce108d326f7cd23d1d358beea1d57d7063078de916dd8' -Maximum 65536
    & ([scriptblock]::Create([Text.Encoding]::UTF8.GetString($bootstrap))) -Repository $Repository
} finally {
    foreach($name in $environmentNames){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
    $settings=$null; $encrypted=$null; $bootstrap=$null
}
