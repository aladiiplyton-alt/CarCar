param([Parameter(Mandatory=$true)][string]$BaseUrl,[Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$source=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'scripts\bootstrap-v2.ps1'),[Text.Encoding]::UTF8)
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
foreach ($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    $body=$function.Body.Extent.Text
    Set-Item -Path ('function:'+$function.Name) -Value ([scriptblock]::Create($body.Substring(1,$body.Length-2)))
}
$folder=Join-Path ([IO.Path]::GetTempPath()) ('CarCar-retry-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $folder | Out-Null
$target=Join-Path $folder 'good.bin'
$corrupt=Join-Path $folder 'bad.bin'
$expected='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
try {
    Save-CarCarDownload -Uri "$BaseUrl/flaky" -Path $target -Label 'тест: временная ошибка' -MaxBytes 64 -ExpectedHash $expected
    if ((Get-CarCarHash -Path $target) -ne $expected) { throw 'A recovered download has the wrong hash.' }
    $rejected=$false
    try { Save-CarCarDownload -Uri "$BaseUrl/corrupt" -Path $corrupt -Label 'тест: повреждённый файл' -MaxBytes 64 -ExpectedHash $expected } catch { $rejected=$true }
    if (!$rejected -or (Test-Path -LiteralPath $corrupt)) { throw 'A corrupt file was retained or accepted.' }
    $script:attempts=0
    $value=Invoke-CarCarRetry -Label 'тест: metadata' -Action { $script:attempts++; if ($script:attempts -lt 3) { throw 'temporary error' }; 'recovered' }
    if ($value -ne 'recovered' -or $script:attempts -ne 3) { throw 'Metadata retries failed.' }
    $counts=Invoke-RestMethod -Uri "$BaseUrl/counts"
    if ($counts.flaky -ne 3 -or $counts.corrupt -ne 3) { throw 'Retry count exceeded or stopped early.' }
    Write-Output 'PASS: transient failures recovered; corrupted downloads rejected and removed; retries bounded to three.'
} finally {
    foreach ($file in @($target,$corrupt)) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
    Remove-Item -LiteralPath $folder -Force
}
