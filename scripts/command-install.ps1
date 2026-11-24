# The only permanent client component is this small, credential-free CMD file.
function Install-CarCarCommand {
    param([string]$InstallDirectory=(Join-Path $env:LOCALAPPDATA 'CarCar\bin'),[Microsoft.Win32.RegistryKey]$EnvironmentKey)
    $directory=[IO.Path]::GetFullPath($InstallDirectory)
    $target=Join-Path $directory 'carcar.cmd'
    $marker='REM CarCar registered command launcher'
    if((Test-Path -LiteralPath $target) -and !([IO.File]::ReadAllText($target).Contains($marker))){throw 'В папке CarCar уже есть другой carcar.cmd. Он не перезаписан.'}
    $lines=@('@echo off','setlocal EnableExtensions DisableDelayedExpansion',$marker,'curl.exe -fL --retry 3 https://aladiiplyton-alt.github.io/CarCar/c4 -o "%TEMP%\cc.cmd"','if errorlevel 1 exit /b %errorlevel%','call "%TEMP%\cc.cmd"','exit /b %errorlevel%')
    $content=($lines -join "`r`n")+"`r`n"
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    [IO.File]::WriteAllText($target,$content,[Text.ASCIIEncoding]::new())
    $ownsKey=$null -eq $EnvironmentKey
    if($ownsKey){$EnvironmentKey=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')}
    try{
        $existing=$EnvironmentKey.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind=if($null -eq $existing){[Microsoft.Win32.RegistryValueKind]::ExpandString}else{$EnvironmentKey.GetValueKind('Path')}
        if($kind -ne [Microsoft.Win32.RegistryValueKind]::String -and $kind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString){throw 'Неожиданный тип пользовательского PATH. PATH не изменён.'}
        $present=$false
        foreach($entry in ([string]$existing).Split(';')){
            if([Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"')).TrimEnd('\') -ieq $directory.TrimEnd('\')){$present=$true;break}
        }
        if(!$present){
            $updated=if([string]::IsNullOrEmpty($existing)){$directory}else{$directory+';'+$existing}
            if($ownsKey){
                # Notify Explorer with the effective value, then preserve the raw
                # registry text and its original REG_SZ/REG_EXPAND_SZ type.
                try{[Environment]::SetEnvironmentVariable('Path',[Environment]::ExpandEnvironmentVariables($updated),'User')}
                finally{$EnvironmentKey.SetValue('Path',$updated,$kind)}
            }else{$EnvironmentKey.SetValue('Path',$updated,$kind)}
        }
    }finally{if($ownsKey){$EnvironmentKey.Dispose()}}
    return $target
}
