param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8787,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

try {
    Set-Location -LiteralPath (Join-Path $repoRoot 'server')
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
        throw 'Node.js / npm is missing. Install Node.js, then try again.'
    }
    if (-not (Test-Path -LiteralPath 'node_modules/.bin/wrangler.cmd')) {
        Write-Host 'Installing server dependencies...'
        & npm.cmd ci
        if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    }

    if (-not $SkipBuild) {
        if (-not $env:GODOT) {
            $godotCommand = Get-Command godot.exe -ErrorAction SilentlyContinue
            if ($godotCommand) {
                $env:GODOT = $godotCommand.Source
            } else {
                $godotFiles = Get-ChildItem -Path "$env:USERPROFILE/Downloads/Godot*/*_console.exe" -File -ErrorAction SilentlyContinue
                $godotFile = $godotFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($godotFile) { $env:GODOT = $godotFile.FullName }
            }
        }
        if (-not $env:GODOT) { throw 'Godot is missing. Set the GODOT environment variable to its executable path.' }
        $env:GODOT = $env:GODOT.Replace('\', '/')
        Write-Host 'Building web client...'
        & (Join-Path $PSScriptRoot 'build-web.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'Web build failed. Check Godot and its Web export templates.' }
    }

    Write-Host "Starting server: http://127.0.0.1:$Port/insure-quest/"
    Write-Host 'Press Ctrl+C to stop the server.'
    & ./node_modules/.bin/wrangler.cmd dev --env local --port $Port --ip 127.0.0.1 --persist-to ../.wrangler-webtest
    if ($LASTEXITCODE -ne 0) { throw 'Wrangler exited with an error.' }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

