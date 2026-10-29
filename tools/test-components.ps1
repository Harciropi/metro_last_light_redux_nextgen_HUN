# Independent components, original SDK restoration and transactional rollback.
param([string]$GameDir)
$ErrorActionPreference='Stop'
try {
 . (Join-Path $PSScriptRoot 'test-backend.ps1') -GameDir $GameDir -FixtureLibrary
 $checks=[Collections.Generic.List[string]]::new()
function New-ComponentsFixture([string]$Name){$f=New-Fixture $Name;[IO.File]::WriteAllBytes((Join-Path $f 'pros.sdk.x64.dll'),$sdkBytes);return $f}
function Apply-Components([string]$Folder,[string]$Selection,$Package=$pkg){Assert-Fixture $Folder;Invoke-HuOperation $Folder $Package $payload 'Apply' $Selection}
function Check-Components([string]$Folder,[string]$Selection){
 $s=Read-HuState $Folder;Check ((Format-HuComponents @(Get-HuInstalledComponents $s)) -eq $Selection) ('state selection '+$Selection)
 $index=[LastLightHu.ResourceIndex]::new([IO.File]::ReadAllBytes((Join-Path $Folder 'content.vfx')))
 if($Selection -like '*Translation*'){
  Check ($index.Archives.Contains($HuArchive)) 'selected translation has its own archive'
  Check ((Get-HuBytesHash ($index.Extract($Folder,'content/localization/stable_us.lng'))) -eq (Get-HuHash (Join-Path $payload 'stable_us.lng'))) 'selected translation has exact language payload'
 }else{
  Check ((Get-HuHash (Join-Path $Folder 'content.vfx')) -eq (Get-HuBytesHash $fixtureIndex)) 'ads-only index remains byte exact original'
  Check (-not [IO.File]::Exists((Join-Path $Folder $HuArchive))) 'ads-only has no translation archive'
 }
 $sdk=[IO.File]::ReadAllBytes((Join-Path $Folder 'pros.sdk.x64.dll'))
 if($Selection -like '*HideAds*'){
  Check ([LastLightHu.BannerFilter]::Inspect($sdk) -eq 'FILTERED') 'selected banner filtering present'
  Check ($sdk.Length -eq $sdkBytes.Length -and (Get-HuBytesHash $sdk) -eq (Get-HuBytesHash ([LastLightHu.BannerFilter]::Apply($sdkBytes)))) 'SDK equals validated panel-disable result'
  Check ((Get-HuHash (Join-Path (Join-Path $Folder $HuBackup) $s.SdkOriginalName)) -eq $sdkOriginalHash) 'checked original SDK backup preserved'
 }else{Check ((Get-HuHash (Join-Path $Folder 'pros.sdk.x64.dll')) -eq $sdkOriginalHash) 'unselected banner filtering leaves original SDK'}
}
$selections=@('Translation','HideAds','Translation,HideAds')
foreach($from in $selections){foreach($to in $selections){
 $f=New-ComponentsFixture ('components-'+$from.Replace(',','-')+'-to-'+$to.Replace(',','-'))
 $originalMtime=(Get-Item -LiteralPath (Join-Path $f 'content.vfx')).LastWriteTimeUtc.Ticks
 Check ((Apply-Components $f $from) -eq 'INSTALLED') ('initial component install '+$from)
 $initial=Read-HuState $f;Check-Components $f $from
 if($from -eq 'HideAds'){Check ((Get-Item -LiteralPath (Join-Path $f 'content.vfx')).LastWriteTimeUtc.Ticks -eq $originalMtime) 'ads-only does not rewrite original index'}
 $expected=if($from -eq $to){'UNCHANGED'}else{'INSTALLED'}
 Check ((Apply-Components $f $to) -eq $expected) ('same-version component switch '+$from+' -> '+$to)
 Check-Components $f $to;$current=Read-HuState $f
 Check ($initial.OriginalName -eq $current.OriginalName -and $initial.OriginalHash -eq $current.OriginalHash) 'component switch retains original index backup'
 Check ((Remove-Fixture $f $pkg) -eq 'REMOVED') 'component set removal succeeds'
 Check ((Get-HuHash (Join-Path $f 'content.vfx')) -eq (Get-HuBytesHash $fixtureIndex) -and (Get-HuHash (Join-Path $f 'pros.sdk.x64.dll')) -eq $sdkOriginalHash) 'component removal restores exact original index and SDK'
 Check ((Get-HuState $f $pkg 'None') -eq 'READY_INSTALL') 'removed components leave a clean state'
}}
foreach($selection in $selections){
 $f=New-ComponentsFixture ('component-upgrade-'+$selection.Replace(',','-'));$previousPkg=$pkg|ConvertTo-Json -Depth 8|ConvertFrom-Json;$previousPkg.Version='0.1.4'
 Apply-Components $f $selection $previousPkg|Out-Null
 Check ((Invoke-HuOperation $f $pkg $payload 'Install') -eq 'INSTALLED') 'upgrade without a new choice preserves component selection'
 Check-Components $f $selection
}
$f=New-ComponentsFixture 'legacy-single-component';Apply-Components $f 'Translation'|Out-Null;$s=Read-HuState $f;$s.PSObject.Properties.Remove('Components');$s.Version='0.1.4';Write-HuJson (Join-Path (Join-Path $f $HuBackup) 'state.json') $s
Check ((Format-HuComponents @(Get-HuInstalledComponents (Read-HuState $f))) -eq 'Translation') 'pre-components state is recognized as translation only'
Check ((Apply-Components $f 'HideAds') -eq 'INSTALLED') 'legacy translation switches to ads-only';Check-Components $f 'HideAds'
$f=New-ComponentsFixture 'sdk-steam-update';Apply-Components $f 'Translation,HideAds'|Out-Null;$s=Read-HuState $f
$updatedSdk=[byte[]]($sdkBytes+[byte[]]@(1,2,3,4));[IO.File]::WriteAllBytes((Join-Path $f 'pros.sdk.x64.dll'),$updatedSdk)
Check ((Get-HuState $f $pkg) -eq 'READY_REBASE') 'Steam-replaced native SDK recognized'
Check ((Apply-Components $f 'Translation,HideAds') -eq 'INSTALLED') 'Steam-replaced SDK filtering reapplied'
$n=Read-HuState $f;Check ($n.OriginalName -eq $s.OriginalName -and $n.SdkOriginalName -ne $s.SdkOriginalName) 'SDK-only update preserves index backup and creates new SDK backup'
Check ([IO.File]::Exists((Join-Path (Join-Path $f $HuBackup) $s.SdkOriginalName))) 'previous SDK backup retained'
Remove-Fixture $f $pkg|Out-Null
Check ((Get-HuHash (Join-Path $f 'pros.sdk.x64.dll')) -eq (Get-HuBytesHash $updatedSdk)) 'removal restores current SDK version, not the older backup'
$f=New-ComponentsFixture 'native-update-direct-removal';Apply-Components $f 'HideAds'|Out-Null;[IO.File]::WriteAllBytes((Join-Path $f 'pros.sdk.x64.dll'),$updatedSdk)
Check ((Invoke-HuOperation $f $pkg $payload 'Remove') -eq 'REMOVED') 'removal after Steam SDK replacement succeeds'
Check ((Get-HuHash (Join-Path $f 'pros.sdk.x64.dll')) -eq (Get-HuBytesHash $updatedSdk)) 'direct removal retains Steam-restored SDK'
$f=New-ComponentsFixture 'sdk-unsupported';[IO.File]::WriteAllText((Join-Path $f 'pros.sdk.x64.dll'),'unsupported fixture SDK')
Check ((Apply-Components $f 'Translation') -eq 'INSTALLED') 'translation independent of unsupported SDK'
Rejected {Apply-Components $f 'Translation,HideAds'} 'BANNER_UNSUPPORTED' 'unsupported SDK banner filtering rejected'
$f=New-ComponentsFixture 'sdk-foreign-filter';[IO.File]::WriteAllBytes((Join-Path $f 'pros.sdk.x64.dll'),[LastLightHu.BannerFilter]::Apply($sdkBytes))
Rejected {Apply-Components $f 'HideAds'} 'FILE_CONFLICT' 'unowned already-filtered SDK rejected'
$f=New-ComponentsFixture 'sdk-backup-corrupt';Apply-Components $f 'HideAds'|Out-Null;$s=Read-HuState $f;[IO.File]::AppendAllText((Join-Path (Join-Path $f $HuBackup) $s.SdkOriginalName),'corrupt')
Rejected {Apply-Components $f 'Translation'} 'BACKUP_CONFLICT' 'corrupt SDK backup blocks restoration'
$f=New-ComponentsFixture 'sdk-external-mutation';Apply-Components $f 'HideAds'|Out-Null;[IO.File]::AppendAllText((Join-Path $f 'pros.sdk.x64.dll'),'foreign')
Rejected {Apply-Components $f 'Translation'} 'FILE_CONFLICT' 'foreign mutation of owned SDK retained'
$f=New-ComponentsFixture 'invalid-selection';Rejected {Apply-Components $f 'None'} 'NO_COMPONENTS' 'empty install selection rejected'
Rejected {Apply-Components $f 'Translation,Translation'} 'BAD_COMPONENTS' 'duplicate components rejected';Rejected {Apply-Components $f 'unknown'} 'BAD_COMPONENTS' 'unknown components rejected'
# An unrelated localization may coexist with SDK-only filtering.
$f=New-ComponentsFixture 'foreign-localization-ads-only';$foreign=[LastLightHu.ResourceIndex]::new($fixtureIndex);$contents=[byte[][]]::new(1);$contents[0]=$config;$fo=$foreign.Overlay('foreign.vfs0',[string[]]@('content/config.bin'),$contents)
[IO.File]::WriteAllBytes((Join-Path $f 'content.vfx'),$fo[0]);[IO.File]::WriteAllBytes((Join-Path $f 'foreign.vfs0'),$fo[1]);$foreignHash=Get-HuHash (Join-Path $f 'content.vfx')
Check ((Apply-Components $f 'HideAds') -eq 'INSTALLED') 'ads-only coexists with foreign localization'
Check ((Get-HuHash (Join-Path $f 'content.vfx')) -eq $foreignHash) 'ads-only retains foreign resource index'
Rejected {Apply-Components $f 'Translation,HideAds'} 'FILE_CONFLICT' 'enabling conflicting translation rejected'
Remove-Fixture $f $pkg|Out-Null;Check ((Get-HuHash (Join-Path $f 'content.vfx')) -eq $foreignHash) 'ads removal retains foreign localization'
# Transaction failures after earlier file writes restore every managed target.
foreach($failedName in @('pros.sdk.x64.dll','state.json')){
 $f=New-ComponentsFixture ('component-rollback-'+$failedName);$script:componentFailPath=if($failedName -eq 'state.json'){Join-Path (Join-Path $f $HuBackup) $failedName}else{Join-Path $f $failedName};$script:componentFailOnce=$true;$saved=${function:Write-HuAtomic}
 function Write-HuAtomic([string]$Path,[byte[]]$Bytes){if($script:componentFailOnce -and $Path -eq $script:componentFailPath){$script:componentFailOnce=$false;throw 'COPY_FAILED'};& $saved $Path $Bytes}
 try{Rejected {Apply-Components $f 'Translation,HideAds'} 'COPY_FAILED' 'component write failure reported'}finally{Set-Item function:Write-HuAtomic $saved}
 Check ((Get-HuHash (Join-Path $f 'content.vfx')) -eq (Get-HuBytesHash $fixtureIndex) -and (Get-HuHash (Join-Path $f 'pros.sdk.x64.dll')) -eq $sdkOriginalHash) 'failed multi-file install restores index and SDK'
 Check (-not [IO.File]::Exists((Join-Path $f $HuArchive)) -and (Get-HuState $f $pkg 'None') -eq 'READY_INSTALL') 'failed component install restores clean state'
}
$f=New-ComponentsFixture 'component-removal-rollback';Apply-Components $f 'Translation,HideAds'|Out-Null;$beforeState=Read-HuState $f;$stateHash=Get-HuHash (Join-Path (Join-Path $f $HuBackup) 'state.json');$script:componentFailPath=Join-Path (Join-Path $f $HuBackup) 'state.json';$script:componentFailOnce=$true;$saved=${function:Write-HuAtomic}
function Write-HuAtomic([string]$Path,[byte[]]$Bytes){if($script:componentFailOnce -and $Path -eq $script:componentFailPath){$script:componentFailOnce=$false;throw 'COPY_FAILED'};& $saved $Path $Bytes}
try{Rejected {Apply-Components $f 'Translation'} 'COPY_FAILED' 'failure while disabling banner filtering reported'}finally{Set-Item function:Write-HuAtomic $saved}
Check ((Get-HuHash (Join-Path $f 'pros.sdk.x64.dll')) -eq $beforeState.SdkHash -and (Get-HuHash (Join-Path (Join-Path $f $HuBackup) 'state.json')) -eq $stateHash) 'failed disable restores filtered SDK and old choices'
Check ((Get-HuHash $liveIndex) -eq $liveHash) 'original fixture input unchanged'
 [pscustomobject]@{Passed=$checks.Count;GameDirectoryModified=$false;SdkFromVerifiedBackup=$sdk.VerifiedBackup}
}finally{
 if(Get-Variable testRoot -ErrorAction SilentlyContinue){Clear-Fixtures}
}
