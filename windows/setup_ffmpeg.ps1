# setup_ffmpeg.ps1
# Run this script on a new Windows machine to download and place ffmpeg.exe & ffprobe.exe
# Usage: powershell -ExecutionPolicy Bypass -File .\windows\setup_ffmpeg.ps1

$ErrorActionPreference = "Stop"

$url = "https://github.com/GyanD/codexffmpeg/releases/download/9.0.1/ffmpeg-9.0.1-essentials_build.zip"
$tempDir = "$env:TEMP\ffmpeg_setup_chunks"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$totalBytes = 111253802
$numChunks = 8
$chunkSize = [Math]::Ceiling($totalBytes / $numChunks)

Write-Host "Downloading FFmpeg essentials in 8 parallel streams..." -ForegroundColor Cyan

$jobs = @()
for ($i = 0; $i -lt $numChunks; $i++) {
    $start = $i * $chunkSize
    $end = [Math]::Min(($i + 1) * $chunkSize - 1, $totalBytes - 1)
    $outFile = "$tempDir\chunk_$i.bin"
    $script = {
        param($u, $s, $e, $o)
        & curl.exe -s -L -r "$s-$e" -o $o $u
    }
    $jobs += Start-Job -ScriptBlock $script -ArgumentList $url, $start, $end, $outFile
}

$jobs | Wait-Job | Out-Null
$jobs | Receive-Job
$jobs | Remove-Job

Write-Host "Reassembling archive..." -ForegroundColor Cyan
$finalZip = "$tempDir\ffmpeg.zip"
$chunkFiles = 0..($numChunks - 1) | ForEach-Object { "$tempDir\chunk_$_.bin" }

$outStream = [System.IO.File]::Create($finalZip)
foreach ($chunk in $chunkFiles) {
    $inBytes = [System.IO.File]::ReadAllBytes($chunk)
    $outStream.Write($inBytes, 0, $inBytes.Length)
    Remove-Item $chunk -Force
}
$outStream.Close()

Write-Host "Extracting ffmpeg.exe and ffprobe.exe..." -ForegroundColor Cyan
$extractDir = "$tempDir\extracted"
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
tar.exe -xf $finalZip -C $extractDir

$ffmpeg = (Get-ChildItem -Path $extractDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1).FullName
$ffprobe = (Get-ChildItem -Path $extractDir -Recurse -Filter "ffprobe.exe" | Select-Object -First 1).FullName

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

$targetDirs = @(
    "$projectRoot\windows\ffmpeg\bin",
    "$projectRoot\build\windows\x64\runner\Release\ffmpeg\bin",
    "$projectRoot\build\windows\x64\runner\Debug\ffmpeg\bin"
)

foreach ($d in $targetDirs) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Copy-Item $ffmpeg -Destination $d -Force
    Copy-Item $ffprobe -Destination $d -Force
    Write-Host "Placed binaries in: $d" -ForegroundColor Green
}

Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Setup complete! FFmpeg and FFprobe are ready." -ForegroundColor Green
