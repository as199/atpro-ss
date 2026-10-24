<#
.SYNOPSIS
  Upload updates/latest.json as a GitHub Release asset (and optionally the .sig).

.PARAMETER Tag
  Release tag (ex. v0.1.0). Default: v0.1.0

.EXAMPLE
  $env:GITHUB_TOKEN = "ghp_..."
  .\updates\publish-latest-json.ps1 -Tag v0.1.0
#>
param(
  [string]$Tag = "v0.1.0",
  [string]$Repo = "as199/atpro-ss"
)

$ErrorActionPreference = "Stop"
$token = $env:GITHUB_TOKEN
if (-not $token) { $token = $env:GH_TOKEN }
if (-not $token) {
  throw "Set GITHUB_TOKEN (or GH_TOKEN) with repo scope to upload release assets."
}

$here = $PSScriptRoot
$latest = Join-Path $here "latest.json"
if (-not (Test-Path $latest)) { throw "Missing $latest" }

$headers = @{
  Authorization = "Bearer $token"
  Accept        = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
  "User-Agent"  = "atpro-ss-updater"
}

$release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
Write-Host "Release id=$($release.id) tag=$($release.tag_name)"

function Upload-Asset([string]$Path) {
  $name = [IO.Path]::GetFileName($Path)
  $existing = @($release.assets | Where-Object { $_.name -eq $name })
  foreach ($a in $existing) {
    Write-Host "Deleting existing asset $name ($($a.id))..."
    Invoke-RestMethod -Method Delete -Headers $headers -Uri $a.url
  }
  $uploadUrl = $release.upload_url -replace '\{\?name,label\}', "?name=$name"
  $bytes = [IO.File]::ReadAllBytes($Path)
  Write-Host "Uploading $name ($($bytes.Length) bytes)..."
  Invoke-RestMethod -Method Post -Headers ($headers + @{ "Content-Type" = "application/octet-stream" }) -Uri $uploadUrl -Body $bytes | Out-Null
  Write-Host "OK $name"
}

Upload-Asset $latest
$sig = Get-ChildItem $here -Filter "*.sig" | Select-Object -First 1
if ($sig) { Upload-Asset $sig.FullName }

Write-Host ""
Write-Host "Primary URL:"
Write-Host "  https://github.com/$Repo/releases/latest/download/latest.json"
Write-Host "Fallback URL:"
Write-Host "  https://raw.githubusercontent.com/$Repo/master/updates/latest.json"
