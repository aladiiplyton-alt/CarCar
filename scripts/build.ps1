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
    Copy-Item -LiteralPath target/release/CarCar.exe -Destination release/CarCar.exe
    Copy-Item -LiteralPath target/release/carcar-launcher.exe -Destination release/carcar-launcher.exe
    Copy-Item -LiteralPath carcar.cmd -Destination release/carcar.cmd
    Copy-Item -LiteralPath scripts/bootstrap.ps1 -Destination release/bootstrap.ps1
    $assets = @('CarCar.exe','carcar-launcher.exe','carcar.cmd','bootstrap.ps1','repository.txt','carcar.example.env','README.md','LICENSE')
    foreach ($name in @('repository.txt','carcar.example.env','README.md','LICENSE')) { Copy-Item -LiteralPath $name -Destination (Join-Path 'release' $name) }
    $assets | ForEach-Object { '{0}  {1}' -f (Get-FileHash -LiteralPath (Join-Path 'release' $_) -Algorithm SHA256).Hash.ToLower(),$_ } | Set-Content release/SHA256SUMS.txt -Encoding ascii
} finally { Pop-Location }
