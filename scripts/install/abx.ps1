#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Upgrade,
    [string]$UserHome
)

$ErrorActionPreference = "Stop"
if (-not $UserHome) {
    $UserHome = if ($env:AGENT_SETUP_HOME) {
        [IO.Path]::GetFullPath($env:AGENT_SETUP_HOME)
    } else {
        [Environment]::GetFolderPath("UserProfile")
    }
}

$BinDirectory = Join-Path $UserHome ".local\bin"
$SourceDirectory = if ($env:ABX_SOURCE_DIR) {
    [IO.Path]::GetFullPath($env:ABX_SOURCE_DIR)
} else {
    Join-Path $UserHome "Projects\abx"
}
$BrowserRoot = if ($env:PLAYWRIGHT_BROWSERS_PATH) {
    $env:PLAYWRIGHT_BROWSERS_PATH
} elseif ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA "ms-playwright"
} else {
    Join-Path $UserHome "AppData\Local\ms-playwright"
}

function Test-BrowserRuntime {
    if ($env:ABX_CHROMIUM_PATH -and (Test-Path -LiteralPath $env:ABX_CHROMIUM_PATH -PathType Leaf)) {
        return $true
    }
    if (-not (Test-Path -LiteralPath $BrowserRoot -PathType Container)) {
        return $false
    }
    return $null -ne (Get-ChildItem -LiteralPath $BrowserRoot -Directory -Filter "chromium*" -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-AbxCommand {
    return Get-Command abx -ErrorAction SilentlyContinue
}

function Require-Command([string]$Name) {
    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $Command) {
        throw "$Name is required to build standalone abx on Windows"
    }
    return $Command
}

function Install-AbxFromSource {
    $null = Require-Command "git"
    $null = Require-Command "bun"
    $null = Require-Command "node"

    if (Test-Path -LiteralPath (Join-Path $SourceDirectory ".git") -PathType Container) {
        if ($Upgrade) {
            $Status = & git -C $SourceDirectory status --porcelain
            if ($LASTEXITCODE -ne 0) { throw "git status failed for $SourceDirectory" }
            if (-not $Status) {
                Write-Output "==> updating standalone abx"
                & git -C $SourceDirectory pull --ff-only
                if ($LASTEXITCODE -ne 0) { throw "git pull failed for $SourceDirectory" }
            } else {
                [Console]::Error.WriteLine("warn: $SourceDirectory has local changes; building without pulling")
            }
        }
    } elseif (Test-Path -LiteralPath $SourceDirectory) {
        throw "abx source path exists but is not a git checkout: $SourceDirectory"
    } else {
        Write-Output "==> cloning standalone abx"
        $Parent = Split-Path -Parent $SourceDirectory
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
        & git clone https://github.com/edihasaj/abx.git $SourceDirectory
        if ($LASTEXITCODE -ne 0) { throw "git clone failed for standalone abx" }
    }

    Write-Output "==> building standalone abx"
    Push-Location $SourceDirectory
    $PreviousSkip = $env:PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD
    try {
        $env:PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1"
        & bun install --frozen-lockfile
        if ($LASTEXITCODE -ne 0) { throw "bun install failed for standalone abx" }
        & bun run build
        if ($LASTEXITCODE -ne 0) { throw "bun build failed for standalone abx" }
    } finally {
        $env:PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = $PreviousSkip
        Pop-Location
    }

    $Executable = Join-Path $SourceDirectory "dist\abx.exe"
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        $Executable = Join-Path $SourceDirectory "dist\abx"
    }
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        throw "abx build did not produce a Windows executable"
    }

    New-Item -ItemType Directory -Path $BinDirectory -Force | Out-Null
    $Launcher = Join-Path $BinDirectory "abx.cmd"
    if (Test-Path -LiteralPath $Launcher -PathType Leaf) {
        $ExistingLauncher = [IO.File]::ReadAllText($Launcher)
        if ($ExistingLauncher -notlike "*$SourceDirectory*") {
            throw "kept existing unmanaged abx launcher: $Launcher"
        }
    }
    $Utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Launcher, "@echo off`r`n`"$Executable`" %*`r`n", $Utf8NoBom)

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $PathEntries = @($UserPath -split ';' | Where-Object { $_ })
    if ($PathEntries -notcontains $BinDirectory) {
        [Environment]::SetEnvironmentVariable("Path", (($PathEntries + $BinDirectory) -join ';'), "User")
    }
    if (($env:Path -split ';') -notcontains $BinDirectory) {
        $env:Path = "$BinDirectory;$env:Path"
    }
}

$Abx = Get-AbxCommand
if ($Check) {
    if (-not $Abx) {
        throw "missing: standalone abx; rerun setup-windows.ps1 without -Check"
    }
    & $Abx.Source --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "abx --version failed" }
    if (-not (Test-BrowserRuntime)) {
        throw "missing: abx Chromium runtime; run 'abx install-browser'"
    }
    Write-Output "abx check complete: $(& $Abx.Source --version)"
    return
}

if ($Upgrade -or -not $Abx) {
    Install-AbxFromSource
    $Abx = Get-AbxCommand
}
if (-not $Abx) { throw "abx installation completed but abx is not on PATH" }

if (-not (Test-BrowserRuntime)) {
    Write-Output "==> installing Chromium for abx"
    & $Abx.Source install-browser
    if ($LASTEXITCODE -ne 0) { throw "abx install-browser failed" }
}
if (-not (Test-BrowserRuntime)) { throw "abx Chromium runtime is still missing" }
Write-Output "abx ready: $(& $Abx.Source --version)"
