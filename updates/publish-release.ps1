<#
.SYNOPSIS
  Create/update a GitHub Release and upload NSIS/MSI/.sig/latest.json assets.

.PARAMETER Tag
  Release tag (ex. v0.5.0)

.PARAMETER BundleRoot
  Path to src-tauri/target/release/bundle (Desktop app build output)

.EXAMPLE
  $env:GITHUB_TOKEN = "ghp_..."
  .\updates\publish-release.ps1 -Tag v0.5.0 -BundleRoot "..\Desktop\src-tauri\target\release\bundle"
#>
param(
  [Parameter(Mandatory = $true)][string]$Tag,
  [Parameter(Mandatory = $true)][string]$BundleRoot,
  [string]$Repo = "as199/atpro-ss",
  [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$token = $env:GITHUB_TOKEN
if (-not $token) { $token = $env:GH_TOKEN }
if (-not $token) {
  throw "Set GITHUB_TOKEN (or GH_TOKEN) with repo scope."
}

if (-not $Version) {
  $Version = $Tag -replace '^v', ''
}

$headers = @{
  Authorization          = "Bearer $token"
  Accept                 = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
  "User-Agent"           = "atpro-ss-release"
}

$nsisDir = Join-Path $BundleRoot "nsis"
$msiDir = Join-Path $BundleRoot "msi"
$setup = Get-ChildItem $nsisDir -Filter "*${Version}*setup.exe" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike "*.sig" } | Select-Object -First 1
$setupSig = Get-ChildItem $nsisDir -Filter "*${Version}*setup.exe.sig" -ErrorAction SilentlyContinue | Select-Object -First 1
$msi = Get-ChildItem $msiDir -Filter "*${Version}*.msi" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike "*.sig" } | Select-Object -First 1
$msiSig = Get-ChildItem $msiDir -Filter "*${Version}*.msi.sig" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $setup) { throw "NSIS setup.exe for $Version not found under $nsisDir" }
if (-not $setupSig) { throw "NSIS .sig for $Version not found under $nsisDir" }
if (-not $msi) { throw "MSI for $Version not found under $msiDir" }

Write-Host "Assets:"
Write-Host "  NSIS: $($setup.FullName)"
Write-Host "  SIG:  $($setupSig.FullName)"
Write-Host "  MSI:  $($msi.FullName)"
if ($msiSig) { Write-Host "  MSI SIG: $($msiSig.FullName)" }

$sigText = (Get-Content $setupSig.FullName -Raw).Trim()
$setupUrl = "https://github.com/$Repo/releases/download/$Tag/$($setup.Name)"
$notes = @"
ATPRO-SS $Version

- Installateur NSIS (recommande) : installation machine + Helper
- Installateur MSI : sans installation automatique du Helper
- Auto-update signe Ed25519 (Settings -> Updates)
"@

$latestObj = [ordered]@{
  version  = $Version
  notes    = "ATPRO-SS $Version"
  pub_date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  platforms = [ordered]@{
    "windows-x86_64" = [ordered]@{
      signature = $sigText
      url       = $setupUrl
    }
  }
}
$latestPath = Join-Path $PSScriptRoot "latest.json"
$jsonText = ($latestObj | ConvertTo-Json -Depth 6) + "`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($latestPath, $jsonText, $utf8NoBom)
Write-Host "Wrote $latestPath (UTF-8 no BOM)"

# Resolve or create release
$release = $null
try {
  $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
  Write-Host "Existing release id=$($release.id)"
} catch {
  Write-Host "Creating release $Tag..."
  $body = @{
    tag_name         = $Tag
    name             = $Version
    body             = $notes
    draft            = $false
    prerelease       = $false
    generate_release_notes = $false
  } | ConvertTo-Json
  $release = Invoke-RestMethod -Method Post -Headers ($headers + @{ "Content-Type" = "application/json" }) `
    -Uri "https://api.github.com/repos/$Repo/releases" -Body $body
  Write-Host "Created release id=$($release.id)"
}

function Upload-Asset([string]$Path) {
  $name = [IO.Path]::GetFileName($Path)
  $existing = @($release.assets | Where-Object { $_.name -eq $name })
  foreach ($a in $existing) {
    Write-Host "Deleting existing asset $name (id=$($a.id))..."
    $delUrl = "https://api.github.com/repos/$Repo/releases/assets/$($a.id)"
    try {
      Invoke-RestMethod -Method Delete -Headers $headers -Uri $delUrl | Out-Null
    } catch {
      Write-Host "Warn delete $name : $($_.Exception.Message)"
    }
  }
  # refresh release for upload_url after deletes
  $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/$($release.id)"
  $uploadUrl = $release.upload_url -replace '\{\?name,label\}', "?name=$([uri]::EscapeDataString($name))"
  $bytes = [IO.File]::ReadAllBytes($Path)
  Write-Host "Uploading $name ($($bytes.Length) bytes)..."
  Invoke-RestMethod -Method Post -Headers ($headers + @{ "Content-Type" = "application/octet-stream" }) `
    -Uri $uploadUrl -Body $bytes | Out-Null
  Write-Host "OK $name"
  return $release
}

$release = Upload-Asset $setup.FullName
$release = Upload-Asset $setupSig.FullName
$release = Upload-Asset $msi.FullName
if ($msiSig) { $release = Upload-Asset $msiSig.FullName }
$release = Upload-Asset $latestPath

Write-Host ""
Write-Host "Release URL: $($release.html_url)"
Write-Host "Primary: https://github.com/$Repo/releases/latest/download/latest.json"
Write-Host "Fallback: https://raw.githubusercontent.com/$Repo/master/updates/latest.json"
