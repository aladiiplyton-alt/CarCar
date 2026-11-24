param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $ProjectRoot 'scripts\command-install.ps1'),[Text.Encoding]::UTF8)))
$folder=Join-Path ([IO.Path]::GetTempPath()) ('CarCar-install-test-'+[guid]::NewGuid())
$subkey='Software\CarCar\Tests\'+[guid]::NewGuid().ToString()
$key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subkey)
try{
    foreach($kind in @([Microsoft.Win32.RegistryValueKind]::String,[Microsoft.Win32.RegistryValueKind]::ExpandString)){
        $original=if($kind -eq [Microsoft.Win32.RegistryValueKind]::String){'C:\Existing One;C:\Other\'}else{'%LOCALAPPDATA%\Existing Tool;C:\Other;'}
        $key.SetValue('Path',$original,$kind)
        $directory=Join-Path $folder $kind.ToString()
        $target=Install-CarCarCommand -InstallDirectory $directory -EnvironmentKey $key
        $once=$key.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if($once -ne ([IO.Path]::GetFullPath($directory)+';'+$original)){throw 'Existing raw PATH was not preserved'}
        if($key.GetValueKind('Path') -ne $kind){throw 'Registry type changed'}
        [void](Install-CarCarCommand -InstallDirectory $directory -EnvironmentKey $key)
        if($key.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -ne $once){throw 'Repeated registration duplicated PATH'}
        $bytes=[IO.File]::ReadAllBytes($target)
        if(@($bytes | Where-Object {$_ -gt 127}).Count -or [Text.Encoding]::ASCII.GetString($bytes).Replace("`r`n",'').Contains("`n")){throw 'Registered command encoding is not ASCII/CRLF'}
        $text=[Text.Encoding]::ASCII.GetString($bytes)
        if(!$text.Contains('CarCar/c4') -or $text.Contains('CARCAR_API_KEY') -or $text.Contains('ProfilePassword')){throw 'Registered command contains configuration or an invalid URL'}
    }
    $conflict=Join-Path $folder 'unrelated'
    New-Item -ItemType Directory -Force -Path $conflict | Out-Null
    [IO.File]::WriteAllText((Join-Path $conflict 'carcar.cmd'),'@echo KEEP-USER-FILE')
    $blocked=$false
    try{[void](Install-CarCarCommand -InstallDirectory $conflict -EnvironmentKey $key)}catch{$blocked=$true}
    if(!$blocked -or [IO.File]::ReadAllText((Join-Path $conflict 'carcar.cmd')) -ne '@echo KEEP-USER-FILE'){throw 'An unrelated file was overwritten'}
    Write-Output 'PASS: user PATH text and registry type preserved, idempotent registration, ASCII/CRLF launcher with no credentials, unrelated files protected.'
}finally{
    $key.Dispose()
    if($subkey -notmatch '^Software\\CarCar\\Tests\\[a-f0-9-]{36}$'){throw 'Unsafe registry cleanup path'}
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($subkey,$false)
    $resolved=[IO.Path]::GetFullPath($folder)
    if([IO.Path]::GetDirectoryName($resolved) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')){throw 'Unsafe test cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
