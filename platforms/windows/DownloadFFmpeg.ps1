param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = "Stop"
$archivePath = Join-Path $env:RUNNER_TEMP "uuremote-ffmpeg-7.0.2-shared.zip"
$extractPath = Join-Path $env:RUNNER_TEMP "uuremote-ffmpeg-7.0.2-shared"
$sourceUrl = "https://github.com/GyanD/codexffmpeg/releases/download/7.0.2/ffmpeg-7.0.2-full_build-shared.zip"
if (!(Test-Path $archivePath)) {
    Invoke-WebRequest -Uri $sourceUrl -OutFile $archivePath -MaximumRetryCount 3
}
if ((Get-Item $archivePath).Length -ne 68297746) { throw "Unexpected pinned FFmpeg archive size" }
if (!(Test-Path $extractPath)) { Expand-Archive -Path $archivePath -DestinationPath $extractPath }
$codec = Get-ChildItem -Path $extractPath -Recurse -Filter "avcodec-61.dll" | Select-Object -First 1
if (!$codec) { throw "FFmpeg 7 ABI avcodec-61.dll missing" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Copy-Item (Join-Path $codec.Directory.FullName "*.dll") $OutputDirectory -Force
Get-ChildItem $extractPath -Recurse -File | Where-Object { $_.Name -match "LICENSE|COPYING|README" } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $OutputDirectory $_.Name) -Force }
$hash = (Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
@{ source = $sourceUrl; sha256 = $hash; bytes = 68297746; codec_abi = 61;
   note = "Independent FFmpeg transport path; not a recovered official media pipeline" } |
    ConvertTo-Json | Set-Content (Join-Path $OutputDirectory "provenance.json")
