param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = "Stop"
$archivePath = Join-Path $env:RUNNER_TEMP "uuremote-ffmpeg-8.1.1-shared.zip"
$extractPath = Join-Path $env:RUNNER_TEMP "uuremote-ffmpeg-8.1.1-shared"
$sourceUrl = "https://github.com/GyanD/codexffmpeg/releases/download/8.1.1/ffmpeg-8.1.1-full_build-shared.zip"
$expectedHash = "4296b396bdfd5fbc3dfc75ab4c8703354a56963232d65c4182993543df2d2f45"
if (!(Test-Path $archivePath)) {
    Invoke-WebRequest -Uri $sourceUrl -OutFile $archivePath -MaximumRetryCount 3
}
if ((Get-Item $archivePath).Length -ne 101083228) { throw "Unexpected pinned FFmpeg archive size" }
$hash = (Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $expectedHash) { throw "Pinned FFmpeg archive SHA-256 mismatch" }
if (!(Test-Path $extractPath)) { Expand-Archive -Path $archivePath -DestinationPath $extractPath }
$codec = Get-ChildItem -Path $extractPath -Recurse -Filter "avcodec-62.dll" | Select-Object -First 1
if (!$codec) { throw "FFmpeg 8 ABI avcodec-62.dll missing" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Copy-Item (Join-Path $codec.Directory.FullName "*.dll") $OutputDirectory -Force
Get-ChildItem $extractPath -Recurse -File | Where-Object { $_.Name -match "LICENSE|COPYING|README" } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $OutputDirectory $_.Name) -Force }
@{ source = $sourceUrl; sha256 = $hash; bytes = 101083228; codec_abi = 62;
   note = "Independent FFmpeg transport path; not a recovered official media pipeline" } |
    ConvertTo-Json | Set-Content (Join-Path $OutputDirectory "provenance.json")
