param([Parameter(Mandatory=$true)][string]$BuildVersion)
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$outputsRoot = Split-Path -Parent $sourceRoot
$portableFolder = Join-Path $outputsRoot ('Brass Tide v' + $BuildVersion)
$manifest = Get-Content -LiteralPath (Join-Path $portableFolder 'RELEASE.json') -Raw | ConvertFrom-Json
if ($manifest.version -ne $BuildVersion) { throw 'Wrong release identity' }
$targetExe = Join-Path $portableFolder 'Brass Tide.exe'
if ((Get-FileHash -LiteralPath $targetExe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.sha256.'Brass Tide.exe') { throw 'Executable hash mismatch' }
$linkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Brass Tide.lnk'
$shellLink = New-Object -ComObject WScript.Shell
$link = $shellLink.CreateShortcut($linkPath)
$link.TargetPath = $targetExe
$link.WorkingDirectory = $portableFolder
$link.IconLocation = (Join-Path $portableFolder 'Brass Tide.ico') + ',0'
$link.Description = 'Brass Tide v' + $BuildVersion
$link.Save()
$readback = $shellLink.CreateShortcut($linkPath)
if ($readback.TargetPath -ne $targetExe) { throw 'Launcher readback failed' }
$receipt = @{version=$BuildVersion;target=$targetExe;icon=$readback.IconLocation;launched=$false;ownerSaveCopied=$false}
# Clean archives are already verified. Never overwrite an existing destination voyage.
$destinationSaves = Join-Path $portableFolder 'saves'
if (-not (Test-Path -LiteralPath (Join-Path $destinationSaves 'voyage.json'))) {
 $candidates = @(Get-ChildItem -LiteralPath $outputsRoot -Directory | Where-Object { $_.Name -match '^Brass Tide v0\.\d{3}$' -and $_.FullName -ne $portableFolder } | ForEach-Object {
  $voyagePath = Join-Path $_.FullName 'saves\voyage.json'
  if (Test-Path -LiteralPath $voyagePath) { Get-Item -LiteralPath $voyagePath }
 } | Sort-Object LastWriteTimeUtc -Descending)
 if ($candidates.Count -gt 0) {
  $ownerVoyage = $candidates[0]
  $originalHash = (Get-FileHash -LiteralPath $ownerVoyage.FullName -Algorithm SHA256).Hash
  New-Item -ItemType Directory -Path $destinationSaves -Force | Out-Null
  foreach ($name in @('voyage.json','voyage.backup.json')) {
   $fromFile = Join-Path $ownerVoyage.DirectoryName $name
   $toFile = Join-Path $destinationSaves $name
   if ((Test-Path -LiteralPath $fromFile) -and -not (Test-Path -LiteralPath $toFile)) { Copy-Item -LiteralPath $fromFile -Destination $toFile }
  }
  if ((Get-FileHash -LiteralPath $ownerVoyage.FullName -Algorithm SHA256).Hash -ne $originalHash) { throw 'Original voyage changed during copy' }
  if ((Get-FileHash -LiteralPath (Join-Path $destinationSaves 'voyage.json') -Algorithm SHA256).Hash -ne $originalHash) { throw 'Copied voyage differs' }
  $receipt.ownerSaveCopied=$true
  $receipt.ownerSaveSource=$ownerVoyage.FullName
  $receipt.ownerSaveSHA256=$originalHash
  $previousSettings = Join-Path $ownerVoyage.Directory.Parent.FullName 'settings.json'
  $nextSettings = Join-Path $portableFolder 'settings.json'
  if ((Test-Path -LiteralPath $previousSettings) -and -not (Test-Path -LiteralPath $nextSettings)) { Copy-Item -LiteralPath $previousSettings -Destination $nextSettings }
 }
}
$receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputsRoot ('Brass Tide v' + $BuildVersion + ' LAUNCHER VERIFIED.json'))
Write-Output ('Desktop icon targets verified v' + $BuildVersion + '; no game was launched. Original voyages remain intact.')
