$ErrorActionPreference='Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    npm.cmd ci
    if ($LASTEXITCODE) { throw 'npm ci failed' }
    npm.cmd run release
    if ($LASTEXITCODE) { throw 'Tauri build failed' }
    cargo build --release -p carcar-launcher --locked
    if ($LASTEXITCODE) { throw 'Launcher build failed' }
    New-Item -ItemType Directory -Force -Path release | Out-Null
    & (Join-Path $PSScriptRoot 'sync-launcher.ps1')
    Copy-Item -LiteralPath target/release/CarCar.exe -Destination release/CarCar.exe
    Copy-Item -LiteralPath target/release/carcar-launcher.exe -Destination release/carcar-launcher.exe
    Copy-Item -LiteralPath carcar.cmd -Destination release/carcar.cmd
    Copy-Item -LiteralPath scripts/bootstrap.ps1 -Destination release/bootstrap.ps1
    Copy-Item -LiteralPath scripts/bootstrap-v2.ps1 -Destination release/bootstrap-v2.ps1
    $profile=Get-Content -LiteralPath profile.public.json -Raw | ConvertFrom-Json
    $profileBootstrap='bootstrap-profile-'+(Get-FileHash -LiteralPath scripts/bootstrap-profile.generated.ps1 -Algorithm SHA256).Hash.ToLowerInvariant().Substring(0,16)+'.ps1'
    Copy-Item -LiteralPath scripts/bootstrap-profile.generated.ps1 -Destination (Join-Path 'release' $profileBootstrap)
    Invoke-WebRequest -UseBasicParsing -Uri ('https://github.com/aladiiplyton-alt/CarCar/releases/download/v1.0.0/'+$profile.asset+'?carcar='+[guid]::NewGuid()) -OutFile (Join-Path 'release' $profile.asset)
    if((Get-FileHash -LiteralPath (Join-Path 'release' $profile.asset) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $profile.sha256){throw 'Encrypted profile SHA256 mismatch'}
    $assets = @('CarCar.exe','carcar-launcher.exe','carcar.cmd','start.cmd','bootstrap.ps1','bootstrap-v2.ps1','repository.txt','carcar.example.env','README.md','LICENSE')
    $assets+=@($profileBootstrap,$profile.asset)
    foreach ($name in @('start.cmd','repository.txt','carcar.example.env','README.md','LICENSE')) { Copy-Item -LiteralPath $name -Destination (Join-Path 'release' $name) }
    $assets | ForEach-Object { '{0}  {1}' -f (Get-FileHash -LiteralPath (Join-Path 'release' $_) -Algorithm SHA256).Hash.ToLower(),$_ } | Set-Content release/SHA256SUMS.txt -Encoding ascii
} finally { Pop-Location }
