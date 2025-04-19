<#
.SYNOPSIS
Builds an Ergogen project and converts generated .jscad files to .stl format.

.DESCRIPTION
This script automates the process of building an Ergogen project using either the installed `ergogen` CLI or a specified path to a Node.js-based CLI. 
It supports optional cleaning and debugging flags. After building, it looks for `.jscad` files in the output and converts them to `.stl` files using `@jscad/cli`.

.PARAMETER cliPath
Optional path to the Node.js CLI script (e.g., `src/cli.js`). If provided, the script runs using `node` with this file. If not, it attempts to use the globally installed `ergogen` command.

.PARAMETER projectDir
Specifies the root directory of the Ergogen project to build. Defaults to the grandparent of the script’s location (../../). Alias: -p

.PARAMETER outDir
Directory where build output will be placed. Defaults to `output` inside the project directory. Alias: -o

.PARAMETER debug
Adds the `--debug` flag to the Ergogen build command for verbose output. Alias: -d

.PARAMETER clean
Adds the `--clean` flag to remove any existing output before building.

.EXAMPLE
.\build.ps1 -p "C:\Keyboards\MyKeyboard" -o "C:\Keyboards\MyKeyboard\out" -debug -clean

.EXAMPLE
.\build.ps1 -cliPath "C:\Tools\ergogen\source\cli.js"

.NOTES
- Requires `ergogen` or a valid CLI path to be available.
- Automatically installs `@jscad/cli@1.10` globally if not found.
- Uses PowerShell jobs to convert `.jscad` files to `.stl` in parallel.

#>

param (
    [string]$cliPath,

    [Alias("p")]
    [string]$projectDir = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..")),

    [Alias("o")]
    [string]$outDir = "$projectDir\output",

    [Alias("d")]
    [switch]$debug,

    [switch]$clean
)

# Validate that the project path exists
if (-not (Test-Path $projectDir)) {
    Write-Error "❌ Project path not found: $projectDir"
    exit 1
}

# Build Ergogen arguments
$args = @()
if ($cliPath) { $args += $cliPath}
if ($outDir) { $args += "-o"; $args += $outDir }
if ($debug)  { $args += "--debug" }
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

# Suppress Node.js warnings
$env:NODE_NO_WARNINGS = "1"

# Build the project
Write-Host "`n🔨 Starting build process: $cmd $($args -join ' ')" -ForegroundColor Cyan

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

# STL generation
Write-Host "✅ Build successful. Proceeding with STL conversion..." -ForegroundColor Green

# Define directories based on the provided or default project path
$casesDir = Join-Path $outDir "cases"
$stlDir = Join-Path $casesDir "stl"

# Ensure the STL directory exists
if (-not (Test-Path -Path $stlDir)) {
    Write-Host "📁 Creating STL directory at $stlDir..."
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
Write-Host "`n🌀 Processing .jscad files in parallel..."

Get-ChildItem $casesDir -Filter "*.jscad" | ForEach-Object {
    $input  = $_.FullName
    $output = Join-Path $stlDir "$($_.BaseName).stl"
    $name   = $_.Name

    Write-Host "🛠️  Queuing: $name ➜ $($_.BaseName).stl"

    $job = Start-Job -ScriptBlock {
        & npx @jscad/cli@1 $using:input -o $using:output -of stla 2>&1
    }

    $jobList += [PSCustomObject]@{
        Job  = $job
        Name = $name
    }
}

Write-Host "⏳ Waiting for conversions to finish..."

$failedJobs = @()

foreach ($entry in $jobList) {
    $job = $entry.Job
    $name = $entry.Name

    Wait-Job $job | Out-Null
    $output = Receive-Job $job
    Remove-Job $job

    if ($output -match "Error|Exception|Failed|self intersecting") {
        Write-Host "`n❌ $name failed to convert" -ForegroundColor Red
        Write-Host "   ↳ Details:" -ForegroundColor DarkRed
        Write-Host ("   " + ($output -join "`n   "))
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
