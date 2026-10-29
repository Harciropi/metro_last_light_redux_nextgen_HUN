# Isolated lifecycle checks. Temporary files are removed on success and failure.
param([string]$GameDir,[switch]$FixtureLibrary,[switch]$FailAfterSetup)
$ErrorActionPreference='Stop'
try {
 . (Join-Path $PSScriptRoot 'test-support.ps1') -GameDir $GameDir
 if($FailAfterSetup){New-Fixture 'intentional-failure'|Out-Null;throw 'Intentional fixture failure'}
$liveIndex=Join-Path $projectRoot '.private\source\original\content.vfx'
$liveHash=Get-HuHash $liveIndex
$clean=New-Fixture 'clean';$originalHash=Get-HuHash (Join-Path $clean 'content.vfx')
Check ((Get-HuState $clean $pkg) -eq 'READY_INSTALL') 'clean detection without build hash pin'
Check ((Install-Fixture $clean $pkg) -eq 'INSTALLED') 'clean install'
Check ((Get-HuState $clean $pkg) -eq 'READY_REMOVE') 'same version offers removal'
$installed=Read-HuState $clean;$backupPath=Join-Path (Join-Path $clean $HuBackup) $installed.OriginalName
Check ((Get-HuHash $backupPath) -eq $originalHash) 'actual original backup checksum verified'
$ownIndex=[LastLightHu.ResourceIndex]::new([IO.File]::ReadAllBytes((Join-Path $clean 'content.vfx')))
$language=$ownIndex.Extract($clean,'content/localization/stable_us.lng')
$h=[Security.Cryptography.SHA256]::Create();try{$languageHash=[BitConverter]::ToString($h.ComputeHash($language)).Replace('-','')}finally{$h.Dispose()}
Check ($languageHash -eq (Get-HuHash (Join-Path $payload 'stable_us.lng'))) 'installed language bytes verified'
$patchedConfig=$ownIndex.Extract($clean,'content/config.bin')
$expectedConfig=[IO.File]::ReadAllBytes((Join-Path $projectRoot '.private\test-input\expected-config.bin'))
$h=[Security.Cryptography.SHA256]::Create();try{Check ([Convert]::ToBase64String($h.ComputeHash($patchedConfig)) -eq [Convert]::ToBase64String($h.ComputeHash($expectedConfig))) 'installed config equals verified font patch'}finally{$h.Dispose()}
Check ((Remove-Fixture $clean $pkg) -eq 'REMOVED') 'same-version removal'
Check ((Get-HuHash (Join-Path $clean 'content.vfx')) -eq $originalHash) 'removal restores exact actual original'
Check (-not [IO.Directory]::Exists((Join-Path $clean $HuBackup))) 'successful full removal deletes installer backups and directory'
Check (-not [IO.File]::Exists((Join-Path $clean $HuArchive))) 'removal deletes only own archive'
Check ([IO.File]::ReadAllText((Join-Path $clean 'user-sentinel.txt')) -eq 'preserve user data') 'unrelated user file preserved'
Check ((Get-HuState $clean $pkg) -eq 'READY_INSTALL') 'removed state permits reinstall'
$upgrade=New-Fixture 'upgrade'
$oldPkg=$pkg|ConvertTo-Json -Depth 8|ConvertFrom-Json;$oldPkg.Version='0.0.9'
Check ((Install-Fixture $upgrade $oldPkg) -eq 'INSTALLED') 'earlier-version fixture installation'
$oldState=Read-HuState $upgrade
Check ((Get-HuState $upgrade $pkg) -eq 'READY_UPGRADE') 'earlier version offers upgrade'
Check ((Install-Fixture $upgrade $pkg) -eq 'INSTALLED') 'upgrade succeeds'
$newState=Read-HuState $upgrade
Check ($newState.OriginalName -eq $oldState.OriginalName -and $newState.OriginalHash -eq $oldState.OriginalHash) 'upgrade preserves original backup file and hash'
Check ((Remove-Fixture $upgrade $pkg) -eq 'REMOVED') 'upgraded version removes successfully'
Check ((Get-HuHash (Join-Path $upgrade 'content.vfx')) -eq $originalHash) 'upgraded removal restores actual original'
$rebase=New-Fixture 'steam-update';Install-Fixture $rebase $pkg|Out-Null;$firstState=Read-HuState $rebase
$extra=[byte[]]@(239,190,173,222,4,0,0,0,1,2,3,4)
$newConfig=[byte[]]($config+$extra);[IO.File]::WriteAllBytes((Join-Path $rebase $sourceArchive),$newConfig)
$newOriginal=[byte[]]$fixtureIndex.Clone();$ms=[IO.MemoryStream]::new($newOriginal,$true);$bw=[IO.BinaryWriter]::new($ms)
$ms.Position=$configEntry.Record+8;$bw.Write([uint32]$newConfig.Length);$bw.Write([uint32]$newConfig.Length);$bw.Dispose();$ms.Dispose()
[IO.File]::WriteAllBytes((Join-Path $rebase 'content.vfx'),$newOriginal);$newOriginalHash=Get-HuHash (Join-Path $rebase 'content.vfx')
Check ((Get-HuState $rebase $pkg) -eq 'READY_REBASE') 'Steam-updated index detected'
Check ((Install-Fixture $rebase $pkg) -eq 'INSTALLED') 'Steam-updated index gets fresh overlay'
$rebased=Read-HuState $rebase
Check ($rebased.OriginalName -ne $firstState.OriginalName -and $rebased.OriginalHash -eq $newOriginalHash) 'updated game gets separate verified baseline'
Check ([IO.File]::Exists((Join-Path (Join-Path $rebase $HuBackup) $firstState.OriginalName))) 'prior baseline retained after Steam update'
$ri=[LastLightHu.ResourceIndex]::new([IO.File]::ReadAllBytes((Join-Path $rebase 'content.vfx')));$rc=$ri.Extract($rebase,'content/config.bin')
Check ([Convert]::ToBase64String($rc[($rc.Length-12)..($rc.Length-1)]) -eq [Convert]::ToBase64String($extra)) 'unknown future config chunk retained through installation'
Remove-Fixture $rebase $pkg|Out-Null
Check ((Get-HuHash (Join-Path $rebase 'content.vfx')) -eq $newOriginalHash) 'removal restores updated original rather than package baseline'
$conflict=New-Fixture 'foreign';[IO.File]::WriteAllText((Join-Path $conflict $HuArchive),'foreign')
Rejected {Get-HuState $conflict $pkg} 'FILE_CONFLICT' 'foreign own-name archive rejected'
Check ([IO.File]::ReadAllText((Join-Path $conflict $HuArchive)) -eq 'foreign') 'foreign file retained'
$backupBad=New-Fixture 'backup-corrupt';Install-Fixture $backupBad $pkg|Out-Null;$bs=Read-HuState $backupBad
[IO.File]::AppendAllText((Join-Path (Join-Path $backupBad $HuBackup) $bs.OriginalName),'corruption')
Rejected {Get-HuState $backupBad $pkg} 'BACKUP_CONFLICT' 'corrupt backup refused'
$missing=New-Fixture 'backup-missing';Install-Fixture $missing $pkg|Out-Null;$bs=Read-HuState $missing
$removeBackup=Join-Path (Join-Path $missing $HuBackup) $bs.OriginalName;Assert-Fixture $removeBackup;[IO.File]::Delete($removeBackup)
Rejected {Get-HuState $missing $pkg} 'BACKUP_CONFLICT' 'missing backup refused without packaged fallback'
$newer=New-Fixture 'newer';Install-Fixture $newer $pkg|Out-Null;$state=Read-HuState $newer;$state.Version='9.0.0'
Write-HuJson (Join-Path (Join-Path $newer $HuBackup) 'state.json') $state
Rejected {Get-HuState $newer $pkg} 'NEWER_INSTALLED' 'downgrade refused'
[IO.File]::WriteAllBytes((Join-Path $newer 'content.vfx'),$fixtureIndex)
Rejected {Get-HuState $newer $pkg} 'NEWER_INSTALLED' 'downgrade still refused after Steam update'
$otherMod=New-Fixture 'other-localization'
$foreignBase=[LastLightHu.ResourceIndex]::new($fixtureIndex);$foreignContents=[byte[][]]::new(1);$foreignContents[0]=$config
$foreign=$foreignBase.Overlay('another_translation.vfs0',[string[]]@('content/config.bin'),$foreignContents)
[IO.File]::WriteAllBytes((Join-Path $otherMod 'content.vfx'),$foreign[0]);[IO.File]::WriteAllBytes((Join-Path $otherMod 'another_translation.vfs0'),$foreign[1])
$foreignHash=Get-HuHash (Join-Path $otherMod 'content.vfx')
Rejected {Get-HuState $otherMod $pkg} 'FILE_CONFLICT' 'another mod controlling a target resource refused'
Check ((Get-HuHash (Join-Path $otherMod 'content.vfx')) -eq $foreignHash) 'other localization index retained'
$unsafeState=New-Fixture 'unsafe-backup-path';Install-Fixture $unsafeState $pkg|Out-Null;$state=Read-HuState $unsafeState;$state.OriginalName='..\outside.vfx'
Write-HuJson (Join-Path (Join-Path $unsafeState $HuBackup) 'state.json') $state
Rejected {Get-HuState $unsafeState $pkg} 'STATE_CONFLICT' 'backup path traversal in state rejected'
$wrong=New-Fixture 'wrong-app';$manifest=Join-Path ([IO.Directory]::GetParent([IO.Directory]::GetParent($wrong).FullName).FullName) 'appmanifest_287390.acf'
[IO.File]::WriteAllText($manifest,'"AppState" { "appid" "286690" "StateFlags" "4" "installdir" "LastLightFixture" }')
Rejected {Get-HuState $wrong $pkg} 'NOT_STEAM' 'wrong Steam application rejected'
$legacy=New-Fixture 'legacy';[IO.File]::Delete((Join-Path $legacy 'amd_fidelityfx_dx12.dll'))
Rejected {Get-HuState $legacy $pkg} 'WRONG_VERSION' 'legacy graphics layout rejected'
$badPayload=Join-Path $testRoot 'bad-payload';[IO.Directory]::CreateDirectory($badPayload)|Out-Null
Copy-Item -LiteralPath (Join-Path $payload 'package.json') -Destination (Join-Path $badPayload 'package.json')
Rejected {Read-HuPackage $badPayload} 'BAD_PACKAGE' 'missing payload assets rejected'
[IO.File]::AppendAllText((Join-Path $badPayload 'package.json'),'corruption')
Rejected {Read-HuPackage $badPayload} 'BAD_PACKAGE' 'modified manifest rejected'
$assetBad=Join-Path $testRoot 'corrupt-asset';[IO.Directory]::CreateDirectory($assetBad)|Out-Null
foreach($sourceFile in Get-ChildItem -File -LiteralPath $payload){Copy-Item -LiteralPath $sourceFile.FullName -Destination (Join-Path $assetBad $sourceFile.Name)}
[IO.File]::AppendAllText((Join-Path $assetBad 'Resources.cs'),'corrupt')
Rejected {Read-HuPackage $assetBad} 'BAD_PACKAGE' 'corrupt individual payload asset rejected'
$rollback=New-Fixture 'rollback';$script:rollbackTarget=Join-Path $rollback 'content.vfx';$script:failOnce=$true
$savedAtomic=${function:Write-HuAtomic}
function Write-HuAtomic([string]$Path,[byte[]]$Bytes){if($script:failOnce -and $Path -eq $script:rollbackTarget){$script:failOnce=$false;throw 'COPY_FAILED'};& $savedAtomic $Path $Bytes}
try{Rejected {Install-Fixture $rollback $pkg} 'COPY_FAILED' 'write failure reported'}finally{Set-Item -Path function:Write-HuAtomic -Value $savedAtomic}
Check ((Get-HuHash (Join-Path $rollback 'content.vfx')) -eq $originalHash) 'failed install restores exact index'
Check (-not [IO.File]::Exists((Join-Path $rollback $HuArchive))) 'failed install rolls back new archive'
Check ((Get-HuState $rollback $pkg) -eq 'READY_INSTALL') 'rollback leaves clean detectable state'
$late=New-Fixture 'late-failure';$script:lateTarget=Join-Path (Join-Path $late $HuBackup) 'state.json';$script:failOnce=$true
function Write-HuAtomic([string]$Path,[byte[]]$Bytes){if($script:failOnce -and $Path -eq $script:lateTarget){$script:failOnce=$false;throw 'COPY_FAILED'};& $savedAtomic $Path $Bytes}
try{Rejected {Install-Fixture $late $pkg} 'COPY_FAILED' 'late failure after both game files were written reported'}finally{Set-Item -Path function:Write-HuAtomic -Value $savedAtomic}
Check ((Get-HuHash (Join-Path $late 'content.vfx')) -eq $originalHash) 'late failure restores changed index byte exactly'
Check (-not [IO.File]::Exists((Join-Path $late $HuArchive)) -and (Get-HuState $late $pkg) -eq 'READY_INSTALL') 'late failure removes new archive and restores clean state'
$pending=New-Fixture 'interrupted';[IO.Directory]::CreateDirectory((Join-Path $pending $HuBackup))|Out-Null
Write-HuJson (Join-Path (Join-Path $pending $HuBackup) 'pending.json') @{Product=$HuProduct}
Rejected {Get-HuState $pending $pkg} 'RECOVERY_NEEDED' 'interrupted operation refuses further writes'
Check ((Get-HuHash $liveIndex) -eq $liveHash) 'original fixture input unchanged'
 [pscustomobject]@{Passed=$checks.Count;GameDirectoryModified=$false}
}finally{
 if(-not $FixtureLibrary -and (Get-Variable testRoot -ErrorAction SilentlyContinue)){Clear-Fixtures}
}
