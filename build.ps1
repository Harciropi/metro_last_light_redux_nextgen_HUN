param([string]$NsisPath,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$projectRoot=$PSScriptRoot
if([string]::IsNullOrWhiteSpace($NsisPath)){
 $cmd=Get-Command makensis.exe -ErrorAction SilentlyContinue
 if($null -eq $cmd){$NsisPath=Join-Path $projectRoot '.private\tools\nsis\makensis.exe'}else{$NsisPath=$cmd.Source}
}
if(-not [IO.File]::Exists($NsisPath)){throw 'NSIS-fordító szükséges. Add meg a -NsisPath paraméterrel.'}
$NsisPath=[IO.Path]::GetFullPath($NsisPath)
$version=[IO.File]::ReadAllText((Join-Path $projectRoot 'VERSION')).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Érvénytelen verzió.'}
if([string]::IsNullOrWhiteSpace($OutputDirectory)){$OutputDirectory=Join-Path $projectRoot ('dist\v'+$version)}
$dist=[IO.Path]::GetFullPath($OutputDirectory)
$output=Join-Path $dist 'MetroLastLightRedux_NextGen_HU.exe'
if((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath (Join-Path $dist 'SHA256.txt'))){throw 'A kész kimenet már létezik. Ellenőrzéshez adj meg másik -OutputDirectory mappát.'}
$temporaryRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work=Join-Path $temporaryRoot ('MetroLastLightHuBuild-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work)|Out-Null
try{
 $package=Join-Path $work 'package'
 & python -B (Join-Path $projectRoot 'tools\package.py') --output $package
 if($LASTEXITCODE -ne 0){throw 'A csomag összeállítása sikertelen.'}
$template=[IO.File]::ReadAllText((Join-Path $projectRoot 'installer\telepito.nsi'))
$template=[regex]::Replace($template,'(?m)^VIProductVersion "[^"]+"',('VIProductVersion "'+$version+'.0"'))
$template=[regex]::Replace($template,'(?m)^VIAddVersionKey /LANG=1038 "FileVersion" "[^"]+"',('VIAddVersionKey /LANG=1038 "FileVersion" "'+$version+'"'))
$template=[regex]::Replace($template,'(?m)^VIAddVersionKey /LANG=1038 "ProductVersion" "[^"]+"',('VIAddVersionKey /LANG=1038 "ProductVersion" "'+$version+'"'))
[IO.File]::WriteAllText((Join-Path $package 'telepito.nsi'),$template,[Text.UTF8Encoding]::new($true))
& $NsisPath /V2 (Join-Path $package 'telepito.nsi')
if($LASTEXITCODE -ne 0){throw 'Az EXE összeállítása sikertelen.'}
[IO.Directory]::CreateDirectory($dist)|Out-Null
[IO.File]::Copy((Join-Path $package 'MetroLastLightRedux_NextGen_HU.exe'),$output,$false)
$hash=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
[IO.File]::WriteAllText((Join-Path $dist 'SHA256.txt'),($hash+'  '+[IO.Path]::GetFileName($output)+"`r`n"),[Text.UTF8Encoding]::new($false))
Write-Output $output
}finally{
 $resolved=[IO.Path]::GetFullPath($work)
 if(-not $resolved.StartsWith($temporaryRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^MetroLastLightHuBuild-[a-f0-9]{32}$'){throw 'Érvénytelen ideiglenes törlési cél.'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -ErrorAction Stop}
}
