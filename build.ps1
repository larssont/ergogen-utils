<#
.SYNOPSIS
Builds an Ergogen project and converts generated .jscad files to .stl format. Optionally, backs up project data before building.

.DESCRIPTION
This script automates the process of building an Ergogen project using either the installed `ergogen` CLI or a specified path to a Node.js-based CLI. It supports optional flags for cleaning, debugging, and backing up project data. After building, the script searches for `.jscad` files in the output directory and converts them to `.stl` files using the `@jscad/cli` package.

.PARAMETER cliPath
Path to the Node.js CLI script (e.g., `src/cli.js`). If provided, the script will run using `node` with this file. If not provided, it attempts to use the globally installed `ergogen` command.

.PARAMETER projectDir
Specifies the root directory of the Ergogen project to build. Defaults to the grandparent directory of the script’s location (../../). Alias: -p

.PARAMETER outDir
Directory where build output will be placed. Defaults to `output` inside the project directory. Alias: -o

.PARAMETER dev
Adds the `--debug` flag to the Ergogen build command. Alias: -d

.PARAMETER clean
Adds the `--clean` flag to remove any existing output before building.

.PARAMETER backup
Creates a backup of the project’s output and YAML files as a `.zip` file, saved in the default `backups` folder inside the project directory. Alias: -b

.PARAMETER backupDir
Specifies an optional directory for the backup. If provided, it triggers the backup process, and the `.zip` file will be saved in this directory.

.EXAMPLE
.\build.ps1 -p "C:\Keyboards\MyKeyboard" -o "C:\Keyboards\MyKeyboard\out" -dev -clean

.EXAMPLE
.\build.ps1 -cliPath "C:\Tools\ergogen\source\cli.js"

.EXAMPLE
.\build.ps1 -p "C:\Keyboards\MyKeyboard" -backupDir "C:\Keyboards\MyKeyboard\backups"

.NOTES
- Most parameters are optional. The script will default to sensible defaults if parameters are not provided:
  - `cliPath` defaults to using the globally installed `ergogen` command.
  - `projectDir` defaults to the grandparent directory of the script’s location.
  - `outDir` defaults to an `output` folder inside the project directory.
  - `backupDir` defaults to a `backups` folder inside the project directory if `backup` is specified but no directory is provided.
- Requires `ergogen` or a valid CLI path to be available.
- Automatically installs `@jscad/cli@1.10` globally if not found.
- Uses PowerShell jobs to convert `.jscad` files to `.stl` in parallel.
#>


[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$cliPath,

    [Parameter()]
    [Alias("p")]
    [string]$projectDir = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..")).Path,

    [Parameter()]
    [Alias("o")]
    [string]$outDir,

    [Parameter()]
    [string]$clean

    [Parameter()]
    [Alias("d")]
    [switch]$dev,

    [Parameter()]
    [Alias("b")]
    [switch]$backup,

    [Parameter()]
    [string]$backupDir
)

function Write-Indented {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$msg,

        [Parameter(Position = 1)]
        [int]$level = 1,

        [Parameter(Position = 2)]
        [string]$color = "White"
    )

    $indentation = " " * ($level * 4)  # 4 spaces per level of indentation

    Write-Host $indentation$msg -ForegroundColor $color
}

# Create an in-memory module so $ScriptBlock doesn't run in new scope
$null = New-Module {
    function Invoke-WithoutProgress {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)] [scriptblock] $ScriptBlock
        )

        # Save current progress preference and hide the progress
        $prevProgressPreference = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'

        try {
            # Run the script block in the scope of the caller of this module function
            . $ScriptBlock
        }
        finally {
            # Restore the original behavior
            $global:ProgressPreference = $prevProgressPreference
        }
    }
}

$doBackup = $backup -or $backupDir
# Set backupDir to projectDir\backups if not provided
$backupDir = if ($backupDir) { $backupDir } else { Join-Path $projectDir "backups" }

# Set outDir if not provided
if (-not $outDir) {
    $outDir = Join-Path $projectDir "output"
}

# Validate that paths exist
if (-not (Test-Path $projectDir)) {
    Write-Error "❌ Project directory not found: $projectDir"
    exit 1
}
if (-not (Test-Path $outDir)) {
    Write-Error "❌ Output directory not found: $projectDir"
    exit 1
}

# Build Ergogen arguments
$args = @()
if ($cliPath) { $args += $cliPath}
if ($outDir) { $args += "-o"; $args += $outDir }
if ($dev)  { $args += "--debug" }
if ($clean)  { $args += "--clean" }
$args += $projectDir

# Select command (node or ergogen)
$cmd = if ($cliPath) { 
    if (-not (Test-Path $cliPath)) {
        Write-Error "❌ CLI path not found: $cliPath"
        exit 1
    }
    "node" 
} else { 
    if (-not (Get-Command ergogen -ErrorAction SilentlyContinue)) {
        Write-Error "❌ 'ergogen' command not found!"
        exit 1
    }
    "ergogen"
}

if ($doBackup) {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $backupFile = Join-Path $backupDir "$timestamp.zip"
    $tempBackup = Join-Path $env:TEMP "ergogen-backup-$timestamp"

    Write-Host "📦 Backing up project to $backupFile" -ForegroundColor Cyan

    # Create directory if needed
    if (-not (Test-Path $backupDir)) {
        Write-Indented "📁 Creating backup directory at $backupDir..."
        New-Item -ItemType Directory -Path $backupDir | Out-Null
    }

    # Create a temporary backup directory
    New-Item -ItemType Directory -Path $tempBackup | Out-Null

    try {
        # Copy output directory to temporary backup folder
        Write-Indented "📨 Copying output directory..."
        Copy-Item -Path $outDir -Destination (Join-Path $tempBackup "output") -Recurse -Force

        # Backup all YAML files in projectDir to the root of the backup
        $yamlFiles = Get-ChildItem -Path $projectDir -Filter "*.yaml" -File
        if ($yamlFiles.Count -gt 0) {
            Write-Indented "📨 Copying YAML files..."
            foreach ($file in $yamlFiles) {
                Copy-Item -Path $file.FullName -Destination $tempBackup -Force
            }
        }

        Write-Indented "🗜️  Compressing backup..."
        Invoke-WithoutProgress {
            Compress-Archive -Path (Join-Path $tempBackup "*") -DestinationPath $backupFile -Force 
        }
        
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "❌ Backup failed." -ForegroundColor Red
        exit 1
    } finally {
        Remove-Item -Path $tempBackup -Recurse -Force
    }

    Write-Host "✅ Backup complete."
}

# Suppress Node.js warnings
$env:NODE_NO_WARNINGS = "1"

# Build the project
Write-Host "`n🚀 Starting build process: $cmd $($args -join ' ')" -ForegroundColor Cyan

try {
    $lastLine = ""

    # Execute the command and capture the output
    & $cmd @args 2>&1 | ForEach-Object {
        Write-Host $_
        if ($_ -match "\S") { $lastLine = $_ }
    }

    # Check if build succeeded
    if ($lastLine -notmatch "^Done\.") {
        Write-Host "❌ Build failed." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "❌ Failed to run: $cmd $args" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Build successful." -ForegroundColor Green

# Define directories based on the output directory
$casesDir = Join-Path $outDir "cases"
$stlDir = Join-Path $casesDir "stl"

Write-Host "`n💾 Converting .jscad files to STLs" -ForegroundColor Cyan

# Ensure the STL directory exists
if (-not (Test-Path -Path $stlDir)) {
    Write-Host "    📁 Creating STL directory at $stlDir..."
    New-Item -ItemType Directory -Path $stlDir | Out-Null
}

# Check if jscad is installed
$jscad = '@jscad/cli@1.10'

npm ls -g $jscad --depth=0 > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️ $jscad not found. Installing now..."
    try {
        npm install -g $jscad --progress
        Write-Host "✅ Successfully installed $jscad."
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Error "❌ Installation of $jscad failed."
        exit 1
    }
}

# Store jobs along with their part names
$jobList = @()

# Convert .jscad files to .stl in parallel
Write-Indented "🌀 Processing .jscad files in parallel"

Get-ChildItem $casesDir -Filter "*.jscad" | ForEach-Object {
    $input  = $_.FullName
    $output = Join-Path $stlDir "$($_.BaseName).stl"
    $name   = $_.Name

    Write-Indented "🛠️  Queuing: $name ➜ $($_.BaseName).stl" 2

    $job = Start-Job -ScriptBlock {
        & npx @jscad/cli@1 $using:input -o $using:output -of stla 2>&1
    }

    $jobList += [PSCustomObject]@{
        Job  = $job
        Name = $name
    }
}

Write-Indented "⏳ Waiting for conversions to finish..." 2

$failedJobs = @()

foreach ($entry in $jobList) {
    $job = $entry.Job
    $name = $entry.Name

    Wait-Job $job | Out-Null
    $output = Receive-Job $job
    Remove-Job $job

    # Check for any failure keywords in the output
    if ($output -match "Error|Exception|Failed|self intersecting") {
        Write-Host "`n❌ $name failed to convert" -ForegroundColor Red
        Write-Indented "↳ Details:" 1 Red
        $output | ForEach-Object { Write-Indented $_ 2 Magenta }
        $failedJobs += $name
    }
}

if ($failedJobs.Count -gt 0) {
    Write-Host "`n🚨 Failed conversions:" -ForegroundColor Red
    foreach ($f in $failedJobs) {
        Write-Host " - $f"
    }
    exit 1
}

Write-Host "`n🎉 All files converted successfully!" -ForegroundColor Green