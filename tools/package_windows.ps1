param(
  [Parameter(Mandatory = $true)][string]$Executable,
  [Parameter(Mandatory = $true)][string]$Output
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$executablePath = Join-Path $root $Executable
$sourceDirectory = Split-Path -Parent $executablePath
$outputPath = Join-Path $root $Output
$staging = Join-Path $env:TEMP ("swanium-crystal-" + [Guid]::NewGuid().ToString("N"))
try {
  New-Item -ItemType Directory -Force $staging | Out-Null
  Copy-Item $executablePath $staging
  Get-ChildItem $sourceDirectory -Filter "*.dll" | Copy-Item -Destination $staging
  Copy-Item (Join-Path $root "README.md") $staging
  Copy-Item (Join-Path $root "LICENSE") $staging
  New-Item -ItemType Directory -Force (Split-Path -Parent $outputPath) | Out-Null
  if (Test-Path $outputPath) { Remove-Item -LiteralPath $outputPath }
  Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $outputPath -CompressionLevel Optimal
} finally {
  if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
Write-Output "Packaged $outputPath"
