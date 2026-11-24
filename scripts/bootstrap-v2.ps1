param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-CarCarRetry {
    param([scriptblock]$Action, [string]$Label, [int]$Attempts=3)
    for ($attempt=1; $attempt -le $Attempts; $attempt++) {
        try { return (& $Action) }
        catch {
            if ($attempt -eq $Attempts) { throw "Не удалось получить ${Label} после $Attempts попыток. Проверьте интернет, доступ к GitHub и свободное место во временной папке." }
            Write-Host "CarCar: повторная загрузка ${Label} ($($attempt+1)/$Attempts)…"
            Start-Sleep -Seconds ([Math]::Min($attempt*2,4))
        }
    }
}

function Get-CarCarHash {
    param([string]$Path)
    $hasher=[Security.Cryptography.SHA256]::Create()
    $stream=[IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $hasher.Dispose() }
}

function Save-CarCarDownload {
    param([string]$Uri, [string]$Path, [string]$Label, [long]$MaxBytes, [string]$ExpectedHash='')
    Invoke-CarCarRetry -Label $Label -Action {
        try {
            $separator=if ($Uri.Contains('?')) { '&' } else { '?' }
            $requestUri=$Uri+$separator+'retry='+[guid]::NewGuid()
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 180 -Uri $requestUri -OutFile $Path
            $length=(Get-Item -LiteralPath $Path).Length
            if ($length -eq 0 -or $length -gt $MaxBytes) { throw 'Неверный размер загрузки.' }
            if ($ExpectedHash -and (Get-CarCarHash -Path $Path) -ne $ExpectedHash.ToLowerInvariant()) { throw 'SHA256 не совпал.' }
        } catch {
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            throw
        }
    }
}

$root=Join-Path ([IO.Path]::GetTempPath()) 'CarCar-Bootstrap'
New-Item -ItemType Directory -Force -Path $root | Out-Null
Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -match '^[a-fA-F0-9-]{36}$' -and !($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object {
    $candidate=[IO.Path]::GetFullPath($_.FullName)
    $ownerFile=Join-Path $candidate 'owner.pid'
    $ownerId=if (Test-Path -LiteralPath $ownerFile) { Get-Content -LiteralPath $ownerFile -ErrorAction SilentlyContinue } else { $null }
    $active=$ownerId -and (Get-Process -Id ([int]$ownerId) -ErrorAction SilentlyContinue)
    if (!$active -and [IO.Path]::GetDirectoryName($candidate) -eq [IO.Path]::GetFullPath($root)) { Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue }
}
$folder=Join-Path $root ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $folder | Out-Null
Set-Content -LiteralPath (Join-Path $folder 'owner.pid') -Value $PID -Encoding ascii
try {
    try {
        $release=Invoke-CarCarRetry -Label 'номер релиза' -Action { Invoke-RestMethod -TimeoutSec 20 -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers @{'User-Agent'='CarCar-Bootstrap/2.0';'Cache-Control'='no-cache'} }
        $tag=[string]$release.tag_name
        if (!$tag -or $tag -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Неверный номер релиза.' }
    } catch {
        Write-Host 'CarCar: последняя версия недоступна через GitHub API. Используется опубликованная версия v1.0.0.'
        $tag='v1.0.0'
    }
    $base="https://github.com/$Repository/releases/download/$tag"
    $sums=Join-Path $folder 'SHA256SUMS.txt'
    Save-CarCarDownload -Uri ("$base/SHA256SUMS.txt?carcar="+[guid]::NewGuid()) -Path $sums -Label 'контрольные суммы' -MaxBytes 32768
    foreach ($name in @('carcar-launcher.exe','CarCar.exe')) {
        $line=Get-Content -LiteralPath $sums | Where-Object { ($_ -split '\s+')[-1] -eq $name } | Select-Object -First 1
        $expected=if ($line) { ($line -split '\s+')[0] } else { '' }
        if ($expected -notmatch '^[A-Fa-f0-9]{64}$') { throw "В релизе отсутствует SHA256 для $name." }
        Save-CarCarDownload -Uri ("$base/${name}?carcar="+[guid]::NewGuid()) -Path (Join-Path $folder $name) -Label $name -MaxBytes 67108864 -ExpectedHash $expected
    }
    Set-Content -LiteralPath (Join-Path $folder 'repository.txt') -Value $Repository -Encoding ascii
    & (Join-Path $folder 'carcar-launcher.exe')
    if ($LASTEXITCODE -ne 0) { throw 'CarCar не запустился или завершился с ошибкой. Проверьте WebView2 Runtime и сообщение загрузчика.' }
} finally {
    $resolved=[IO.Path]::GetFullPath($folder)
    if ([IO.Path]::GetDirectoryName($resolved) -ne [IO.Path]::GetFullPath($root)) { throw 'Небезопасный путь очистки.' }
    for ($attempt=0; $attempt -lt 40; $attempt++) {
        if (!(Test-Path -LiteralPath $resolved)) { break }
        try { Remove-Item -LiteralPath $resolved -Recurse -Force; break } catch { Start-Sleep -Milliseconds 250 }
    }
}
