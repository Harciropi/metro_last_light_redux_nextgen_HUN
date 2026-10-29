param([string]$GameDir)
$ErrorActionPreference='Stop'
$sdkGameDir=$GameDir
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot=Join-Path $temporaryRoot ('MetroLastLightHuTest-'+[guid]::NewGuid().ToString('N'))
function Clear-Fixtures {
 $resolved=[IO.Path]::GetFullPath($testRoot)
 if(-not $resolved.StartsWith($temporaryRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^MetroLastLightHuTest-[a-f0-9]{32}$'){throw 'Unsafe fixture cleanup'}
 if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -ErrorAction Stop}
}
function Find-TestSdk([string]$SelectedGame){
 $candidates=[Collections.Generic.List[string]]::new()
 if($SelectedGame){$candidates.Add((Join-Path $SelectedGame 'pros.sdk.x64.dll'))}
 else{
  $candidates.Add((Join-Path $projectRoot '.private\source\original\pros.sdk.x64.dll'))
  $steam=(Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
  if($steam){
   $libraries=@($steam);$vdf=Join-Path $steam 'steamapps\libraryfolders.vdf'
   if(Test-Path -LiteralPath $vdf){$libraries+=@([regex]::Matches([IO.File]::ReadAllText($vdf),'"path"\s+"([^"]+)"')|ForEach-Object {$_.Groups[1].Value.Replace('\\','\')})}
   foreach($library in $libraries){
    $manifest=Join-Path $library 'steamapps\appmanifest_287390.acf'
    if((Test-Path -LiteralPath $manifest) -and [IO.File]::ReadAllText($manifest) -match '"installdir"\s+"([^"\\/]+)"'){$candidates.Add((Join-Path $library ('steamapps\common\'+$matches[1]+'\pros.sdk.x64.dll')))}
   }
  }
 }
 foreach($path in $candidates){
  if(-not [IO.File]::Exists($path)){continue}
  $bytes=[IO.File]::ReadAllBytes($path)
  if([LastLightHu.BannerFilter]::Inspect($bytes) -eq 'ORIGINAL'){return [pscustomobject]@{Bytes=$bytes;Source=$path;VerifiedBackup=$false}}
  $backup=Join-Path ([IO.Path]::GetDirectoryName($path)) $HuBackup
  $statePath=Join-Path $backup 'state.json'
  if(-not [IO.File]::Exists($statePath)){continue}
  $s=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json
  if($s.Product -ne $HuProduct -or $s.SdkOriginalHash -notmatch '^[A-F0-9]{64}$' -or $s.SdkOriginalName -cne ('sdk-original-'+$s.SdkOriginalHash+'.dll') -or (Get-HuBytesHash $bytes) -ne $s.SdkHash){throw 'Unverified SDK backup state'}
  $saved=Join-Path $backup $s.SdkOriginalName
  Assert-HuRegular $backup;Assert-HuRegular $saved
  $original=[IO.File]::ReadAllBytes($saved)
  if((Get-HuBytesHash $original) -ne $s.SdkOriginalHash -or [LastLightHu.BannerFilter]::Inspect($original) -ne 'ORIGINAL'){throw 'Invalid SDK restoration backup'}
  return [pscustomobject]@{Bytes=$original;Source=$saved;VerifiedBackup=$true}
 }
 throw 'No verified original SDK found. Supply -GameDir or the local original SDK.'
}
try{
 [IO.Directory]::CreateDirectory($testRoot)|Out-Null
 $packageRoot=Join-Path $testRoot 'package'
 & python -B (Join-Path $projectRoot 'tools\package.py') --output $packageRoot|Out-Null
 if($LASTEXITCODE -ne 0){throw 'Test package staging failed'}
 . (Join-Path $packageRoot 'Kezeles.ps1') -LibraryOnly
 $payload=Join-Path $packageRoot 'payload';$pkg=Read-HuPackage $payload
 $currentHash=$TrustedManifestHash
 $sourceIndex=[IO.File]::ReadAllBytes((Join-Path $projectRoot '.private\source\original\content.vfx'))
 $parsed=[LastLightHu.ResourceIndex]::new($sourceIndex)
 $config=[IO.File]::ReadAllBytes((Join-Path $projectRoot '.private\source\original\config.bin'))
 $configEntry=$parsed.Files['content/config.bin'];$sourceArchive=$parsed.Archives[$configEntry.Archive]
 $fixtureIndex=[byte[]]$sourceIndex.Clone()
 $ms=[IO.MemoryStream]::new($fixtureIndex,$true);$bw=[IO.BinaryWriter]::new($ms)
 $ms.Position=$configEntry.Record+4;$bw.Write([uint32]0);$bw.Write([uint32]$config.Length);$bw.Write([uint32]$config.Length);$bw.Dispose();$ms.Dispose()
 $sdk=Find-TestSdk $sdkGameDir;$sdkBytes=$sdk.Bytes;$sdkOriginalHash=Get-HuBytesHash $sdkBytes
 $checks=[Collections.Generic.List[string]]::new()
}catch{Clear-Fixtures;throw}
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAILED: '+$Name)};$checks.Add($Name)}
function Assert-Fixture([string]$Folder){$resolved=[IO.Path]::GetFullPath($Folder);if(-not $resolved.StartsWith($testRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Test target is outside fixture root'}}
function New-Fixture([string]$Name){
 $dir=Join-Path $testRoot ($Name+'\steamapps\common\LastLightFixture');Assert-Fixture $dir
 [IO.Directory]::CreateDirectory($dir)|Out-Null
 foreach($f in @('metro.exe','steam_api64.dll','amd_fidelityfx_dx12.dll')){[IO.File]::WriteAllText((Join-Path $dir $f),'FIXTURE ONLY - not executable')}
 [IO.File]::WriteAllBytes((Join-Path $dir 'content.vfx'),$fixtureIndex)
 [IO.File]::WriteAllBytes((Join-Path $dir $sourceArchive),$config)
 [IO.File]::WriteAllText((Join-Path ([IO.Directory]::GetParent([IO.Directory]::GetParent($dir).FullName).FullName) 'appmanifest_287390.acf'),('"AppState" { "appid" "287390" "StateFlags" "4" "installdir" "LastLightFixture" "buildid" "fixture-unpinned" }'))
 [IO.File]::WriteAllText((Join-Path $dir 'user-sentinel.txt'),'preserve user data')
 return $dir
}
function Install-Fixture([string]$Dir,$Package){Assert-Fixture $Dir;return Invoke-HuOperation $Dir $Package $payload 'Install'}
function Remove-Fixture([string]$Dir,$Package){Assert-Fixture $Dir;return Invoke-HuOperation $Dir $Package $payload 'Remove'}
function Rejected([scriptblock]$Action,[string]$Expected,[string]$Name){
 $actual='NO_ERROR';try{& $Action|Out-Null}catch{$actual=$_.Exception.Message}
 Check ($actual -eq $Expected) ($Name+' ['+$actual+']')
}
