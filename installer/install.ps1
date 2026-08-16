#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a built SkyrimTwitchExpansion into a Skyrim Data folder (or an
    MO2 mod profile directory) and stages the TwitchBridge companion app
    alongside it.

.PARAMETER SkyrimDataPath
    Target Data\ folder — either the game's own Data\ directory, or an MO2
    mod folder (e.g. ...\mods\SkyrimTwitchExpansion) if you manage it as a
    normal mod.

.PARAMETER BridgeInstallPath
    Where to drop the published TwitchBridge app. Defaults to a
    "TwitchBridge" folder next to SkyrimDataPath's parent, since the bridge
    is a standalone process, not part of the Skyrim Data\ tree.

.EXAMPLE
    ./install.ps1 -SkyrimDataPath "D:\Games\MO2\mods\SkyrimTwitchExpansion"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SkyrimDataPath,

    [string]$BridgeInstallPath,

    [string]$Configuration = "RelWithDebInfo"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $BridgeInstallPath) {
    $BridgeInstallPath = Join-Path (Split-Path -Parent $SkyrimDataPath) "TwitchBridge"
}

Write-Host "== SkyrimTwitchExpansion installer ==" -ForegroundColor Cyan
Write-Host "Data target:   $SkyrimDataPath"
Write-Host "Bridge target: $BridgeInstallPath"

# --- 1. SKSE plugin + Papyrus payload (Data\ tree) --------------------------

$PluginDll = Join-Path $RepoRoot "SKSEPlugin\build\$Configuration\SkyrimTwitchExpansion.dll"
if (-not (Test-Path $PluginDll)) {
    throw "Plugin DLL not found at '$PluginDll'. Build SKSEPlugin first (see SKSEPlugin/README or docs/IMPLEMENTATION_PLAN.md)."
}

New-Item -ItemType Directory -Force -Path (Join-Path $SkyrimDataPath "SKSE\Plugins") | Out-Null
Copy-Item $PluginDll (Join-Path $SkyrimDataPath "SKSE\Plugins\SkyrimTwitchExpansion.dll") -Force
Copy-Item (Join-Path $RepoRoot "Data\SKSE\Plugins\SkyrimTwitchExpansion.ini") (Join-Path $SkyrimDataPath "SKSE\Plugins\SkyrimTwitchExpansion.ini") -Force

Copy-Item -Recurse -Force (Join-Path $RepoRoot "Data\Scripts") (Join-Path $SkyrimDataPath "Scripts")
Copy-Item -Recurse -Force (Join-Path $RepoRoot "Data\MCM") (Join-Path $SkyrimDataPath "MCM")

Write-Host "Copied SKSE plugin, Papyrus scripts, and MCM config." -ForegroundColor Green

# --- 2. TwitchBridge companion app -------------------------------------------

$BridgePublishDir = Join-Path $RepoRoot "TwitchBridge\TwitchBridge.App\bin\$Configuration\net8.0\win-x64\publish"
if (-not (Test-Path $BridgePublishDir)) {
    Write-Warning "TwitchBridge publish output not found at '$BridgePublishDir'."
    Write-Warning "Run: dotnet publish TwitchBridge/TwitchBridge.App -c $Configuration -r win-x64 --self-contained false"
} else {
    New-Item -ItemType Directory -Force -Path $BridgeInstallPath | Out-Null
    Copy-Item -Recurse -Force "$BridgePublishDir\*" $BridgeInstallPath
    Write-Host "Copied TwitchBridge companion app to $BridgeInstallPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Cyan
Write-Host "  1. Edit '$BridgeInstallPath\appsettings.json' with your Twitch channel/bot credentials."
Write-Host "  2. Launch Skyrim once, then run TwitchBridge.App.exe from '$BridgeInstallPath'."
Write-Host "  3. Open the MCM menu in-game (ChatVsDragonborn) to tune prices/timers."
