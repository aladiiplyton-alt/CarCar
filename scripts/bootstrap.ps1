param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$base = "https://github.com/$Repository/releases/latest/download"
$root = Join-Path ([IO.Path]::GetTempPath()) 'CarCar-Bootstrap'
New-Item -ItemType Directory -Force -Path $root | Out-Null
Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -match '^[a-fA-F0-9-]{36}$' -and !($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object {
    $candidate = [IO.Path]::GetFullPath($_.FullName)
    $ownerFile = Join-Path $candidate 'owner.pid'
    $ownerId = if (Test-Path -LiteralPath $ownerFile) { Get-Content -LiteralPath $ownerFile -ErrorAction SilentlyContinue } else { $null }
    $active = $ownerId -and (Get-Process -Id ([int]$ownerId) -ErrorAction SilentlyContinue)
    if (!$active -and [IO.Path]::GetDirectoryName($candidate) -eq [IO.Path]::GetFullPath($root)) {
        Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$folder = Join-Path $root ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $folder | Out-Null
Set-Content -LiteralPath (Join-Path $folder 'owner.pid') -Value $PID -Encoding ascii
try {
    Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS.txt" -OutFile (Join-Path $folder 'SHA256SUMS.txt')
    foreach ($name in @('carcar-launcher.exe','CarCar.exe')) {
        $target = Join-Path $folder $name
        Invoke-WebRequest -UseBasicParsing -Uri "$base/$name" -OutFile $target
        $line = Get-Content -LiteralPath (Join-Path $folder 'SHA256SUMS.txt') | Where-Object { ($_ -split '\s+')[-1] -eq $name } | Select-Object -First 1
        $actualHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([IO.File]::ReadAllBytes($target))).Replace('-','')
        if (!$line -or $actualHash -ne ($line -split '\s+')[0]) { throw "SHA256 не совпал: $name" }
    }
    Set-Content -LiteralPath (Join-Path $folder 'repository.txt') -Value $Repository -Encoding ascii
    & (Join-Path $folder 'carcar-launcher.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка запуска CarCar. Проверьте наличие WebView2 Runtime.' }
} finally {
    $resolved = [IO.Path]::GetFullPath($folder)
    $expectedParent = [IO.Path]::GetFullPath($root)
    if ([IO.Path]::GetDirectoryName($resolved) -ne $expectedParent) { throw 'Небезопасный путь очистки.' }
    for ($attempt=0; $attempt -lt 40; $attempt++) {
        if (!(Test-Path -LiteralPath $resolved)) { break }
        try { Remove-Item -LiteralPath $resolved -Recurse -Force; break } catch { Start-Sleep -Milliseconds 250 }
    }
}
