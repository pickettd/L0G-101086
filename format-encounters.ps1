# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2018 Jacob Keller. All rights reserved.

# Terminate on all errors...
$ErrorActionPreference = "Stop"

# Load the shared module
Import-Module -Force -DisableNameChecking (Join-Path -Path $PSScriptRoot -ChildPath l0g-101086.psm1)

# See l0g-101086.psm1 for descriptions of each configuration field
$RequiredParameters = @(
    "extra_upload_data"
    "last_format_file"
    "format_encounters_log"
    "arcdps_logs"
    "guilds"
)

# Load the configuration from the default file
$config = Load-Configuration "l0g-101086-config.json" 2 $RequiredParameters
if (-not $config) {
    exit
}

if (-not $config.debug_mode) {
    Set-Logfile $config.format_encounters_log
}

# Require a gw2raidar token for obtaining permalinks if gw2raidar uploading is enabled
if ((-not $config.gw2raidar_token) -and ($config.upload_gw2raidar -ne "no")) {
    Read-Host -Prompt "Uploading to gw2raidar requires a gw2raidar authentication token. Press enter to exit"
    exit
}

# Check that the ancillary data folder has already been created
if (-not (X-Test-Path $config.extra_upload_data)) {
    Read-Host -Prompt "The $($config.extra_upload_data) can't be found. Try running upload-logs.ps1 first? Press enter to exit"
    exit
}

if (-not $config.discord_json_data) {
    Read-Host -Prompt "The discord JSON data directory must be configured. Press enter to exit"
    exit
} elseif (-not (X-Test-Path $config.discord_json_data)) {
    try {
        New-Item -ItemType directory -Path $config.discord_json_data
    } catch {
        Write-Exception $_
        Read-Host -Prompt "Unable to create $($config.discord_json_data). Press enter to exit"
        exit
    }
}

if (-not $config.last_format_file) {
    Read-Host -Prompt "A file to store last format time must be configured. Press enter to exit"
    exit
} elseif (-not (X-Test-Path (Split-Path $config.last_format_file))) {
    Read-Host -Prompt "The path for the last_format_file appears invalid. Press enter to exit"
    exit
}

Log-Output "~~~"
Log-Output "Formatting encounters for discord at $(Get-Date)..."
Log-Output "~~~"

# Load the last format time
if (X-Test-Path $config.last_format_file) {
    $last_format_time = Get-Content -Raw -Path $config.last_format_file | ConvertFrom-Json | Select-Object -ExpandProperty "DateTime" | Get-Date
}

$next_format_time = Get-Date

# If we have a last format time, we want to limit our scan to all files since
# the last time that we formatted.
#
# Search the extras directory for all evtc directories with a time newer than the last format time.
if (Test-Path $config.last_format_file) {
    $last_upload_time = Get-Content -Raw -Path $config.last_format_file | ConvertFrom-Json | Select-Object -ExpandProperty "DateTime" | Get-Date
    $dirs = @(Get-ChildItem -Directory -Include @("*.evtc") -LiteralPath $config.extra_upload_data | Where-Object { $_.CreationTime -gt $last_format_time} | Sort-Object -Property CreationTime | ForEach-Object {$_.Name})
} else {
    $dirs = @(Get-ChildItem -Directory -Include @("*.evtc") -LiteralPath $config.extra_upload_data | Sort-Object -Property CreationTime | ForEach-Object {$_.Name})
}

if ($dirs) {
    # Load each of the evtc directories as a boss hash table
    $bosses = @()
    foreach($d in $dirs) {
        $bosses += @(Load-From-EVTC $config $d)
    }

    # We only want to publish successful encounters
    $bosses = $bosses.where({$_.success})

    # Lookup and save gw2raidar links
    if ($config.upload_gw2raidar -ne "no") {
        Save-Gw2-Raidar-Links $config $bosses
    }

    Format-And-Publish-All $config $bosses
}

# Update the format time
$next_format_time | Select-Object -Property DateTime| ConvertTo-Json | Out-File -Force $config.last_format_file
