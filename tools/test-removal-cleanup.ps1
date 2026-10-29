# Full removal, foreign files and locked backups; never writes to an installed game.
param([string]$GameDir)
$ErrorActionPreference='Stop'
try{
 . (Join-Path $PSScriptRoot 'test-support.ps1') -GameDir $GameDir
 function Apply-CleanupFixture([string]$Dir,[string]$Selection){Assert-Fixture $Dir;return Invoke-HuOperation $Dir $pkg $payload 'Apply' $Selection}
 $game=New-Fixture 'complete';[IO.File]::WriteAllBytes((Join-Path $game 'pros.sdk.x64.dll'),$sdkBytes)
 Apply-CleanupFixture $game 'Translation,HideAds'|Out-Null
 $backup=Join-Path $game $HuBackup
 Apply-CleanupFixture $game 'Translation'|Out-Null
 Check ([IO.Directory]::Exists($backup) -and @(Get-ChildItem -LiteralPath $backup -Filter 'sdk-original-*.dll').Count -gt 0) 'partial modification preserves required backups'
 Apply-CleanupFixture $game 'Translation,HideAds'|Out-Null
 Check (@(Get-ChildItem -LiteralPath $backup -Filter 'history-*.json').Count -gt 0) 'repeated modification exercises history cleanup'
 Check ((Remove-Fixture $game $pkg) -eq 'REMOVED') 'full removal succeeds'
 Check (-not [IO.Directory]::Exists($backup)) 'full removal deletes all own backups and directory'
 Check ((Get-HuHash (Join-Path $game 'content.vfx')) -eq (Get-HuBytesHash $fixtureIndex) -and (Get-HuHash (Join-Path $game 'pros.sdk.x64.dll')) -eq $sdkOriginalHash) 'exact original index and SDK restored'
 $game=New-Fixture 'foreign-file';[IO.File]::WriteAllBytes((Join-Path $game 'pros.sdk.x64.dll'),$sdkBytes)
 Apply-CleanupFixture $game 'HideAds'|Out-Null;$backup=Join-Path $game $HuBackup
 [IO.File]::WriteAllText((Join-Path $backup 'user-note.txt'),'preserve')
 Remove-Fixture $game $pkg|Out-Null
 Check (@(Get-ChildItem -LiteralPath $backup).Count -eq 1 -and [IO.File]::ReadAllText((Join-Path $backup 'user-note.txt')) -eq 'preserve') 'foreign file preserved, own backups removed'
 $game=New-Fixture 'locked-original';[IO.File]::WriteAllBytes((Join-Path $game 'pros.sdk.x64.dll'),$sdkBytes)
 Apply-CleanupFixture $game 'Translation,HideAds'|Out-Null;$backup=Join-Path $game $HuBackup
 $s=Read-HuState $game;$saved=Join-Path $backup $s.OriginalName
 $held=[IO.File]::Open($saved,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{Rejected {Remove-Fixture $game $pkg} 'CLEANUP_FAILED' 'locked backup reports cleanup failure'}finally{$held.Dispose()}
 Check ((Get-HuHash (Join-Path $game 'content.vfx')) -eq (Get-HuBytesHash $fixtureIndex) -and (Get-HuHash (Join-Path $game 'pros.sdk.x64.dll')) -eq $sdkOriginalHash -and [IO.File]::Exists($saved)) 'locked-backup error preserves restored originals and backup'
 [pscustomobject]@{Passed=$checks.Count;GameDirectoryModified=$false}
}finally{
 if(Get-Variable testRoot -ErrorAction SilentlyContinue){Clear-Fixtures}
}
