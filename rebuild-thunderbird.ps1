[CmdletBinding()]
param(
    [string]$GeckoRoot,
    [string]$MozillaBuildRoot = 'C:\mozilla-build',
    [string]$GeckoChangeset = 'f2f75ecf8eb443871319273e7e39fb7f01b2581e',
    [switch]$SkipBootstrap,
    [switch]$SkipGeckoUpdate,
    [switch]$SkipVendor,
    [switch]$SkipClobber,
    [switch]$SkipPackage,
    [switch]$DryRun
)

if ([string]::IsNullOrWhiteSpace($GeckoRoot)) {
    $GeckoRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'mozilla-unified'
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CommRoot = $PSScriptRoot
$CommMount = Join-Path $GeckoRoot 'comm'
$StartShell = Join-Path $MozillaBuildRoot 'start-shell.bat'
$MozconfigPath = Join-Path $GeckoRoot 'mozconfig'
$ObjDir = Join-Path $GeckoRoot 'obj-thunderbird'
$ThunderbirdExe = Join-Path $ObjDir 'dist\bin\thunderbird.exe'
$ApplicationIni = Join-Path $ObjDir 'dist\bin\application.ini'
$PackagePattern = Join-Path $ObjDir 'dist\thunderbird-*.en-US.win64.zip'
$MozconfigLines = @(
    'ac_add_options --enable-project=comm/mail',
    'mk_add_options MOZ_OBJDIR=@TOPSRCDIR@/obj-thunderbird'
)

function Write-Step {
    param([string]$Message)

    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-NormalizedPath {
    param([string]$Path)

    (Resolve-Path $Path).ProviderPath.TrimEnd('\')
}

function Invoke-MozillaBuildCommand {
    param([string]$Command)

    Write-Step "MozillaBuild command: $Command"

    if ($DryRun) {
        return
    }

    $env:USE_MINTTY = '0'
    & $StartShell -where $GeckoRoot -c $Command
    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed with exit code {0}: {1}" -f $LASTEXITCODE, $Command)
    }
}

function Ensure-CommMount {
    $expectedCommRoot = Get-NormalizedPath $CommRoot

    if (-not (Test-Path $CommMount)) {
        Write-Step "Creating comm junction: $CommMount -> $expectedCommRoot"
        if (-not $DryRun) {
            New-Item -ItemType Junction -Path $CommMount -Target $CommRoot | Out-Null
        }
        return
    }

    $commItem = Get-Item $CommMount
    $actualTargets = @($commItem.Target)

    if ($actualTargets.Count -eq 0) {
        throw "Existing comm path is not a junction with a target: $CommMount"
    }

    $actualCommRoot = Get-NormalizedPath $actualTargets[0]
    if ($actualCommRoot -ne $expectedCommRoot) {
        throw "Existing comm junction points to '$actualCommRoot' instead of '$expectedCommRoot'."
    }

    Write-Step "comm junction already points to this repository"
}

function Ensure-Mozconfig {
    $desiredMozconfig = (($MozconfigLines -join [Environment]::NewLine) + [Environment]::NewLine)

    if ((Test-Path $MozconfigPath) -and ((Get-Content $MozconfigPath -Raw) -eq $desiredMozconfig)) {
        Write-Step 'mozconfig already matches the Thunderbird build configuration'
        return
    }

    Write-Step "Writing Thunderbird mozconfig to $MozconfigPath"
    if (-not $DryRun) {
        [System.IO.File]::WriteAllText($MozconfigPath, $desiredMozconfig, [System.Text.Encoding]::ASCII)
    }
}

Write-Step 'Validating local paths'

if (-not (Test-Path $StartShell)) {
    throw "MozillaBuild shell not found: $StartShell"
}

if (-not (Test-Path $GeckoRoot)) {
    throw "Gecko root not found: $GeckoRoot"
}

if (-not (Test-Path (Join-Path $GeckoRoot 'mach'))) {
    throw "mach was not found in Gecko root: $GeckoRoot"
}

Ensure-CommMount
Ensure-Mozconfig

if (-not $SkipBootstrap) {
    Invoke-MozillaBuildCommand './mach --no-interactive bootstrap --application-choice browser'
}

if (-not $SkipGeckoUpdate) {
    Invoke-MozillaBuildCommand "hg update -C $GeckoChangeset"
}

if (-not $SkipVendor) {
    Invoke-MozillaBuildCommand './mach tb-rust vendor'
}

if (-not $SkipClobber) {
    Invoke-MozillaBuildCommand './mach clobber'
}

Invoke-MozillaBuildCommand './mach build'

if (-not $SkipPackage) {
    Invoke-MozillaBuildCommand './mach package'
}

if ($DryRun) {
    Write-Step 'Dry run completed without making changes'
    return
}

Write-Step 'Verifying build outputs'

if (-not (Test-Path $ThunderbirdExe)) {
    throw "Thunderbird executable not found after build: $ThunderbirdExe"
}

Write-Host "Built executable: $ThunderbirdExe" -ForegroundColor Green

if (Test-Path $ApplicationIni) {
    Get-Content $ApplicationIni |
        Where-Object { $_ -match '^(Name|Version)=' } |
        ForEach-Object { Write-Host $_ -ForegroundColor Green }
}

if (-not $SkipPackage) {
    $package = Get-ChildItem $PackagePattern | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $package) {
        throw "Expected Thunderbird package was not found under $ObjDir\dist"
    }

    Write-Host "Package: $($package.FullName)" -ForegroundColor Green
}

Write-Step 'Thunderbird rebuild script completed successfully'