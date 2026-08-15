#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$PublicOnly,
    [switch]$Headless,
    [switch]$AllClis,
    [string[]]$Cli,
    [string]$PrivateSkillsRoot,
    [string]$PrivateMcpsConfig
)

$ErrorActionPreference = "Stop"
$SupportedClis = @("codex", "claude", "opencode", "gemini", "copilot")
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$UserHome = if ($env:AGENT_SETUP_HOME) {
    [IO.Path]::GetFullPath($env:AGENT_SETUP_HOME)
} else {
    [Environment]::GetFolderPath("UserProfile")
}
$CanonicalInstructions = Join-Path $RepoRoot "AGENTS.MD"
$PublicSkillsRoot = Join-Path $RepoRoot "skills"
if (-not $PrivateSkillsRoot) {
    $PrivateSkillsRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot "../manager/skills"))
}
$SharedSkillsRoot = Join-Path $UserHome ".agents\skills"
$ClaudeSkillsRoot = Join-Path $UserHome ".claude\skills"
$LegacyCodexRoot = Join-Path $UserHome ".codex\skills"
$McpSyncScript = Join-Path $RepoRoot "scripts\sync-agent-mcps.mjs"
$MaintenanceSyncScript = Join-Path $RepoRoot "scripts\sync-agent-maintenance.mjs"
$AbxInstallScript = Join-Path $RepoRoot "scripts\install\abx.ps1"
if (-not $PrivateMcpsConfig) {
    $PrivateMcpsConfig = [IO.Path]::GetFullPath((Join-Path $RepoRoot "../manager/configs/mcps.json"))
}
$script:Failures = 0

function Write-Failure([string]$Message) {
    [Console]::Error.WriteLine($Message)
    $script:Failures++
}

function Get-ExistingItem([string]$Path) {
    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Get-LinkTarget([string]$Path) {
    $Item = Get-ExistingItem $Path
    if (-not $Item -or -not ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        return $null
    }
    $Target = $Item.Target
    if ($Target -is [array]) {
        $Target = $Target[0]
    }
    if (-not $Target) {
        return $null
    }
    if (-not [IO.Path]::IsPathRooted($Target)) {
        $Target = Join-Path $Item.DirectoryName $Target
    }
    return [IO.Path]::GetFullPath($Target)
}

function Remove-Link([string]$Path) {
    $Item = Get-ExistingItem $Path
    if (-not $Item -or -not ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to remove a non-link: $Path"
    }
    if ($Item.PSIsContainer) {
        [IO.Directory]::Delete($Path)
    } else {
        [IO.File]::Delete($Path)
    }
}

function Ensure-ParentDirectory([string]$Path) {
    $Parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }
}

function Get-SkillSources {
    $Roots = @($PublicSkillsRoot)
    if (-not $PublicOnly -and (Test-Path -LiteralPath $PrivateSkillsRoot -PathType Container)) {
        $Roots += $PrivateSkillsRoot
    }

    $Sources = @{}
    foreach ($Root in $Roots) {
        foreach ($Directory in Get-ChildItem -LiteralPath $Root -Directory) {
            $SkillFile = Join-Path $Directory.FullName "SKILL.md"
            if (-not (Test-Path -LiteralPath $SkillFile -PathType Leaf)) {
                continue
            }
            $Body = [IO.File]::ReadAllText($SkillFile)
            $NameMatch = [regex]::Match($Body, '(?m)^name:\s*["'']?([^"''\r\n]+)["'']?\s*$')
            $DescriptionMatch = [regex]::Match($Body, '(?m)^description:\s*\S')
            if (-not $NameMatch.Success -or -not $DescriptionMatch.Success -or
                $NameMatch.Groups[1].Value.Trim() -ne $Directory.Name) {
                throw "Invalid skill metadata: $SkillFile"
            }
            if ($Sources.ContainsKey($Directory.Name)) {
                throw "Duplicate skill name across sources: $($Directory.Name)"
            }
            $Sources[$Directory.Name] = $Directory.FullName
        }
    }
    return $Sources
}

function Test-DirectoryTreesEqual([string]$Left, [string]$Right) {
    $LeftFiles = @(Get-ChildItem -LiteralPath $Left -File -Recurse | Sort-Object FullName)
    $RightFiles = @(Get-ChildItem -LiteralPath $Right -File -Recurse | Sort-Object FullName)
    if ($LeftFiles.Count -ne $RightFiles.Count) {
        return $false
    }
    for ($Index = 0; $Index -lt $LeftFiles.Count; $Index++) {
        $LeftRelative = $LeftFiles[$Index].FullName.Substring($Left.Length).TrimStart('\', '/')
        $RightRelative = $RightFiles[$Index].FullName.Substring($Right.Length).TrimStart('\', '/')
        if ($LeftRelative -ne $RightRelative) {
            return $false
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $LeftFiles[$Index].FullName).Hash -ne
            (Get-FileHash -Algorithm SHA256 -LiteralPath $RightFiles[$Index].FullName).Hash) {
            return $false
        }
    }
    return $true
}

function Sync-Skills([bool]$CheckOnly, [string[]]$Registries) {
    if ($Registries.Count -eq 0) {
        return
    }
    $Sources = Get-SkillSources
    $RegistryPaths = @{}
    if ($Registries -contains "shared") { $RegistryPaths["shared"] = $SharedSkillsRoot }
    if ($Registries -contains "claude") { $RegistryPaths["claude"] = $ClaudeSkillsRoot }

    if (-not $CheckOnly) {
        foreach ($RegistryRoot in $RegistryPaths.Values) {
            New-Item -ItemType Directory -Path $RegistryRoot -Force | Out-Null
        }
    }

    foreach ($SkillName in ($Sources.Keys | Sort-Object)) {
        $Source = [IO.Path]::GetFullPath($Sources[$SkillName])
        foreach ($RegistryRoot in $RegistryPaths.Values) {
            $Destination = Join-Path $RegistryRoot $SkillName
            $Existing = Get-ExistingItem $Destination
            $Target = Get-LinkTarget $Destination
            if ($Target -eq $Source -and (Test-Path -LiteralPath (Join-Path $Destination "SKILL.md") -PathType Leaf)) {
                continue
            }
            if ($CheckOnly) {
                Write-Failure "mismatch: $Destination -> $Source"
                continue
            }
            if ($Existing -and -not ($Existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Write-Failure "kept non-link: $Destination"
                continue
            }
            if ($Existing) {
                Remove-Link $Destination
            }
            Ensure-ParentDirectory $Destination
            $LinkType = if ($env:OS -eq "Windows_NT") { "Junction" } else { "SymbolicLink" }
            New-Item -ItemType $LinkType -Path $Destination -Target $Source | Out-Null
        }

        if ($Registries -contains "shared") {
            $Legacy = Join-Path $LegacyCodexRoot $SkillName
            $LegacyTarget = Get-LinkTarget $Legacy
            if ($LegacyTarget -and ($LegacyTarget -eq $Source -or $LegacyTarget -like "*\agent-scripts\skills\*")) {
                if ($CheckOnly) {
                    Write-Failure "legacy Codex skill link: $Legacy"
                } else {
                    Remove-Link $Legacy
                }
            }
        }
    }

    if ($Registries -contains "shared" -and (Test-Path -LiteralPath $LegacyCodexRoot -PathType Container)) {
        $PaseoDirectories = @(Get-ChildItem -LiteralPath $LegacyCodexRoot -Directory | Where-Object { $_.Name -eq "paseo" -or $_.Name -like "paseo-*" })
        foreach ($LegacyDirectory in $PaseoDirectories) {
            $NeutralDirectory = Join-Path $SharedSkillsRoot $LegacyDirectory.Name
            $LegacyTarget = Get-LinkTarget $LegacyDirectory.FullName
            if ($LegacyTarget -and (Test-Path -LiteralPath (Join-Path $NeutralDirectory "SKILL.md") -PathType Leaf)) {
                if ($CheckOnly) {
                    Write-Failure "legacy Codex Paseo link: $($LegacyDirectory.FullName)"
                } else {
                    Remove-Link $LegacyDirectory.FullName
                }
                continue
            }
            $LegacyMarker = Join-Path $LegacyDirectory.FullName ".paseo-managed-files.json"
            $NeutralMarker = Join-Path $NeutralDirectory ".paseo-managed-files.json"
            if (-not (Test-Path -LiteralPath $LegacyMarker -PathType Leaf) -or
                -not (Test-Path -LiteralPath $NeutralMarker -PathType Leaf)) {
                continue
            }
            if (-not (Test-DirectoryTreesEqual $LegacyDirectory.FullName $NeutralDirectory)) {
                Write-Failure "divergent Codex Paseo skill kept: $($LegacyDirectory.FullName)"
                continue
            }
            if ($CheckOnly) {
                Write-Failure "duplicate Codex Paseo skill: $($LegacyDirectory.FullName)"
            } else {
                Remove-Item -LiteralPath $LegacyDirectory.FullName -Recurse -Force
            }
        }
    }
    Write-Output "skills $($(if ($CheckOnly) { 'check' } else { 'sync' })) complete: count=$($Sources.Count) registries=$($Registries -join ',')"
}

function New-InstructionTarget([string]$Destination, [string]$PointerLine) {
    Ensure-ParentDirectory $Destination
    try {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $CanonicalInstructions -ErrorAction Stop | Out-Null
    } catch {
        $Utf8NoBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($Destination, "$PointerLine`r`n", $Utf8NoBom)
    }
}

function Sync-Instructions([bool]$CheckOnly, [string[]]$Clis) {
    $PointerLine = "READ $CanonicalInstructions BEFORE ANYTHING (skip if missing)."
    $Targets = [ordered]@{ home = (Join-Path $UserHome "AGENTS.md") }
    foreach ($CliName in $Clis) {
        switch ($CliName) {
            codex { $Targets["codex"] = Join-Path (Join-Path $UserHome ".codex") "AGENTS.md" }
            claude { $Targets["claude"] = Join-Path (Join-Path $UserHome ".claude") "CLAUDE.md" }
            opencode { $Targets["opencode"] = Join-Path (Join-Path (Join-Path $UserHome ".config") "opencode") "AGENTS.md" }
            gemini { $Targets["gemini"] = Join-Path (Join-Path $UserHome ".gemini") "GEMINI.md" }
            copilot { $Targets["copilot"] = Join-Path (Join-Path $UserHome ".github") "copilot-instructions.md" }
        }
    }

    foreach ($Destination in $Targets.Values) {
        $Existing = Get-ExistingItem $Destination
        $Target = Get-LinkTarget $Destination
        if ($Target -eq $CanonicalInstructions -and (Test-Path -LiteralPath $Destination -PathType Leaf)) {
            continue
        }
        if ($Existing -and -not ($Existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $Lines = @([IO.File]::ReadAllLines($Destination))
            if ($Lines.Count -gt 0 -and $Lines[0] -eq $PointerLine) {
                continue
            }
            if ($CheckOnly) {
                Write-Failure "missing pointer: $Destination"
                continue
            }
            $Body = [IO.File]::ReadAllText($Destination)
            $Utf8NoBom = New-Object Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($Destination, "$PointerLine`r`n`r`n$Body", $Utf8NoBom)
            continue
        }
        if ($CheckOnly) {
            Write-Failure "missing or mismatched instruction target: $Destination"
            continue
        }
        if ($Existing) {
            Remove-Link $Destination
        }
        New-InstructionTarget $Destination $PointerLine
    }
    $ConfiguredClis = @("home") + @($Clis)
    Write-Output "instructions $($(if ($CheckOnly) { 'check' } else { 'sync' })) complete: clis=$($ConfiguredClis -join ',')"
}

function Sync-Mcps([bool]$CheckOnly, [string[]]$Clis) {
    if ($Clis.Count -eq 0) {
        return
    }
    $Node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $Node) {
        Write-Output "MCP sync skipped: node missing"
        return
    }
    $Arguments = @($McpSyncScript)
    if ($CheckOnly) { $Arguments += "--check" }
    if ($PublicOnly) { $Arguments += "--public-only" }
    foreach ($CliName in $Clis) {
        $Arguments += @("--cli", $CliName)
    }
    $PreviousHome = $env:AGENT_SETUP_HOME
    $PreviousPrivateConfig = $env:PRIVATE_MCPS_CONFIG
    try {
        $env:AGENT_SETUP_HOME = $UserHome
        $env:PRIVATE_MCPS_CONFIG = $PrivateMcpsConfig
        & $Node.Source @Arguments
        if ($LASTEXITCODE -ne 0) {
            $script:Failures++
        }
    } finally {
        $env:AGENT_SETUP_HOME = $PreviousHome
        $env:PRIVATE_MCPS_CONFIG = $PreviousPrivateConfig
    }
}

function Sync-Maintenance([bool]$CheckOnly, [string[]]$RequestedClis) {
    $Node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $Node) {
        Write-Output "Maintenance state/hooks skipped: node missing"
        return
    }
    $Arguments = @($MaintenanceSyncScript)
    if ($CheckOnly) { $Arguments += "--check" }
    if ($PublicOnly) { $Arguments += "--public-only" }
    if ($Headless) { $Arguments += "--headless" }
    if ($AllClis) {
        $Arguments += "--all-clis"
    } else {
        foreach ($CliName in $RequestedClis) {
            $Arguments += @("--cli", $CliName)
        }
    }
    & $Node.Source @Arguments
    if ($LASTEXITCODE -ne 0) {
        $script:Failures++
    }
}

$RequestedClis = @()
foreach ($CliValue in @($Cli)) {
    foreach ($CliName in @($CliValue -split ',')) {
        $CliName = $CliName.Trim().ToLowerInvariant()
        if (-not $CliName) { continue }
        if ($SupportedClis -notcontains $CliName) {
            [Console]::Error.WriteLine("error: unsupported CLI: $CliName")
            exit 2
        }
        if ($RequestedClis -notcontains $CliName) {
            $RequestedClis += $CliName
        }
    }
}

if ($AllClis -and $RequestedClis.Count -gt 0) {
    [Console]::Error.WriteLine("error: -AllClis and -Cli cannot be used together")
    exit 2
}

if ($AllClis) {
    $SelectedClis = $SupportedClis
} elseif ($RequestedClis.Count -gt 0) {
    $SelectedClis = $RequestedClis
} else {
    $SelectedClis = @($SupportedClis | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue })
}

$Registries = @()
if (@($SelectedClis | Where-Object { $_ -ne "claude" }).Count -gt 0) { $Registries += "shared" }
if ($SelectedClis -contains "claude") { $Registries += "claude" }

Write-Output "Agent setup: platform=windows mode=$($(if ($Check) { 'check' } else { 'sync' }))"
if ($SelectedClis.Count -gt 0) {
    Write-Output "CLIs: $($SelectedClis -join ',')"
} else {
    Write-Output "CLIs: none detected; configuring only $UserHome\AGENTS.md"
}
if (-not $PublicOnly -and (Test-Path -LiteralPath $PrivateSkillsRoot -PathType Container)) {
    Write-Output "Private skills: $PrivateSkillsRoot"
} else {
    Write-Output "Private skills: disabled or not found"
}

try {
    & $AbxInstallScript -Check:$Check -UserHome $UserHome
} catch {
    Write-Failure "abx: $($_.Exception.Message)"
}

Sync-Skills ([bool]$Check) $Registries
Sync-Instructions ([bool]$Check) $SelectedClis
Sync-Mcps ([bool]$Check) $SelectedClis
Sync-Maintenance ([bool]$Check) $RequestedClis
if (-not $Check -and $script:Failures -eq 0) {
    Sync-Skills $true $Registries
    Sync-Instructions $true $SelectedClis
    Sync-Mcps $true $SelectedClis
}

if ($script:Failures -gt 0) {
    [Console]::Error.WriteLine("agent setup failed: $script:Failures issue(s)")
    exit 1
}
Write-Output "Agent setup complete."
