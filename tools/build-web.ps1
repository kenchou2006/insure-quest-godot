$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$stagePath = Join-Path $repoRoot '.web-build'
$webPath = Join-Path $repoRoot 'web'

# Restrict cleanup to the two generated output directories in this repository.
function Clear-BuildDirectory([string]$Target, [string]$ExpectedName) {
    $resolved = [IO.Path]::GetFullPath($Target)
    if ((Split-Path -Parent $resolved) -ne $repoRoot -or (Split-Path -Leaf $resolved) -ne $ExpectedName) {
        throw "Unexpected build output path: $resolved"
    }
    if (Test-Path -LiteralPath $resolved) {
        # Keep directory handles valid while Wrangler watches the output tree.
        Get-ChildItem -LiteralPath $resolved -Recurse -File -Force | Remove-Item -Force
    } else {
        New-Item -ItemType Directory -Path $resolved | Out-Null
    }
}

Push-Location (Join-Path $repoRoot 'server')
try {
    Clear-BuildDirectory $stagePath '.web-build'
    & $env:GODOT --headless --path (Join-Path $repoRoot 'client') --export-release Web (Join-Path $stagePath 'index.html')
    if ($LASTEXITCODE -ne 0) { throw 'Godot Web export failed. Check that Web export templates are installed.' }

    if (-not $env:IQ_BUILD) {
        $env:IQ_BUILD = 'local-' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    if (-not $env:IQ_BASE_PATH) { $env:IQ_BASE_PATH = '/insure-quest' }
    $assetName = $env:IQ_BASE_PATH.Trim('/')
    if ($assetName -notmatch '^[a-zA-Z0-9_-]+$') { throw 'IQ_BASE_PATH must contain one folder name, such as /insure-quest.' }

    & node tools/gen-maskable.mjs
    # Optional sharp-based icon generation can fail without blocking the build.
    & ./node_modules/.bin/esbuild.cmd src/local/local-room.ts --bundle --format=iife --platform=browser --target=es2022 --minify "--outfile=$stagePath/local-room.js"
    if ($LASTEXITCODE -ne 0) { throw 'Local game engine bundle failed.' }
    & node tools/pack-web.mjs $stagePath
    if ($LASTEXITCODE -ne 0) { throw 'Web compression and packaging failed.' }

    Clear-BuildDirectory $webPath 'web'
    $assetPath = Join-Path $webPath $assetName
    New-Item -ItemType Directory -Path $assetPath -Force | Out-Null
    Move-Item -LiteralPath (Join-Path $stagePath '_headers') -Destination (Join-Path $webPath '_headers')
    Get-ChildItem -LiteralPath $stagePath -Force | Copy-Item -Destination $assetPath -Recurse -Force
    Clear-BuildDirectory $stagePath '.web-build'
    Write-Host 'Web build complete.'
} finally {
    Pop-Location
}
