#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Publish @jwikman/bc-code-intelligence-mcp to npmjs.org

.DESCRIPTION
    This script handles the complete publishing workflow:
    - Validates npm authentication
    - Runs tests and validation
    - Builds the package
    - Publishes to npmjs with public access (required for scoped packages)
    - Creates a git tag for the version
    - Pushes changes to remote

.PARAMETER VersionBump
    Optional version bump type: patch, minor, major, or specific version number
    If not specified, uses current version from package.json

.PARAMETER SkipTests
    Skip running tests (not recommended)

.PARAMETER DryRun
    Perform all steps except actual publishing

.EXAMPLE
    .\scripts\publish-to-npm.ps1
    Publish current version

.EXAMPLE
    .\scripts\publish-to-npm.ps1 -VersionBump patch
    Bump patch version and publish

.EXAMPLE
    .\scripts\publish-to-npm.ps1 -VersionBump 1.6.0
    Set specific version and publish

.EXAMPLE
    .\scripts\publish-to-npm.ps1 -DryRun
    Test the workflow without publishing
#>

param(
    [Parameter()]
    [string]$VersionBump,

    [Parameter()]
    [switch]$SkipTests,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Step {
    param([string]$Message)
    Write-Host "🔵 $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

# Get script directory and project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Publishing @jwikman/bc-code-intelligence-mcp" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check npm authentication
Write-Step "Checking npm authentication..."
try {
    $npmUser = npm whoami 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not logged in to npm. Please run: npm login"
        Write-Host ""
        Write-Host "After logging in, run this script again." -ForegroundColor Yellow
        exit 1
    }
    Write-Success "Logged in as: $npmUser"
} catch {
    Write-Error "Failed to check npm authentication: $_"
    exit 1
}

# Step 2: Verify package.json has correct scoped name
Write-Step "Verifying package name..."
$packageJson = Get-Content "package.json" -Raw | ConvertFrom-Json
if ($packageJson.name -ne "@jwikman/bc-code-intelligence-mcp") {
    Write-Error "package.json name must be '@jwikman/bc-code-intelligence-mcp'"
    exit 1
}
Write-Success "Package name verified: $($packageJson.name)"

# Step 3: Version bump if requested
if ($VersionBump) {
    Write-Step "Bumping version: $VersionBump"

    if ($VersionBump -match '^\d+\.\d+\.\d+$') {
        # Specific version number
        npm version $VersionBump --no-git-tag-version
    } elseif ($VersionBump -in @('patch', 'minor', 'major')) {
        # Semver bump
        npm version $VersionBump --no-git-tag-version
    } else {
        Write-Error "Invalid version bump: $VersionBump (use patch/minor/major or x.y.z)"
        exit 1
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Version bump failed"
        exit 1
    }

    # Reload package.json to get new version
    $packageJson = Get-Content "package.json" -Raw | ConvertFrom-Json
    Write-Success "Version set to: $($packageJson.version)"
}

$version = $packageJson.version
Write-Host ""
Write-Host "📦 Publishing version: $version" -ForegroundColor Magenta
Write-Host ""

# Step 4: Check for uncommitted changes
Write-Step "Checking git status..."
$gitStatus = git status --porcelain
if ($gitStatus -and -not $DryRun) {
    Write-Warning "You have uncommitted changes:"
    Write-Host $gitStatus
    Write-Host ""
    $response = Read-Host "Continue anyway? (y/N)"
    if ($response -ne 'y') {
        Write-Host "Aborted by user"
        exit 0
    }
}

# Step 5: Validate embedded knowledge submodule
Write-Step "Validating embedded knowledge..."
npm run validate:embedded-knowledge
if ($LASTEXITCODE -ne 0) {
    Write-Error "Embedded knowledge validation failed"
    Write-Host ""
    Write-Host "The embedded-knowledge submodule is not properly initialized." -ForegroundColor Yellow
    Write-Host "Run these commands to fix:" -ForegroundColor Yellow
    Write-Host "  git submodule init" -ForegroundColor White
    Write-Host "  git submodule update --remote" -ForegroundColor White
    Write-Host ""
    exit 1
}
Write-Success "Embedded knowledge validated"

# Step 6: Clean install dependencies
Write-Step "Installing dependencies..."
if (Test-Path "node_modules") {
    Remove-Item -Recurse -Force "node_modules"
}
npm install
if ($LASTEXITCODE -ne 0) {
    Write-Error "npm install failed"
    exit 1
}
Write-Success "Dependencies installed"

# Step 7: Run tests
if (-not $SkipTests) {
    Write-Step "Running tests and validation..."
    npm run test:all
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Tests failed. Fix errors before publishing."
        Write-Host "Use -SkipTests to bypass (not recommended)" -ForegroundColor Yellow
        exit 1
    }
    Write-Success "All tests passed"
} else {
    Write-Warning "Skipping tests (not recommended)"
}

# Step 8: Build
Write-Step "Building package..."
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit 1
}
Write-Success "Build completed"

# Step 9: Verify build artifacts
Write-Step "Verifying build artifacts..."
$requiredFiles = @(
    "dist/index.js",
    "dist/cli/bc-code-intel-cli.js",
    "embedded-knowledge"
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        Write-Error "Required file missing: $file"
        exit 1
    }
}
Write-Success "Build artifacts verified"

# Step 10: Publish (or dry-run)
if ($DryRun) {
    Write-Step "Dry run - simulating publish..."
    npm publish --dry-run --access public
    Write-Success "Dry run completed successfully"
    Write-Host ""
    Write-Host "This was a dry run. To actually publish, run without -DryRun" -ForegroundColor Yellow
} else {
    Write-Step "Publishing to npmjs.org..."
    Write-Host ""
    Write-Warning "This will publish @jwikman/bc-code-intelligence-mcp@$version to npmjs"
    $response = Read-Host "Proceed? (y/N)"
    if ($response -ne 'y') {
        Write-Host "Aborted by user"
        exit 0
    }

    # Publish with public access (required for scoped packages)
    npm publish --access public

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Publish failed"
        exit 1
    }

    Write-Success "Published successfully!"

    # Step 11: Create git tag
    Write-Step "Creating git tag: v$version"
    git tag -a "v$version" -m "Release v$version"

    # Step 12: Commit version change if we bumped
    if ($VersionBump) {
        Write-Step "Committing version change..."
        git add package.json package-lock.json
        git commit -m "chore: bump version to $version"
    }

    # Step 13: Push to remote
    Write-Step "Pushing to remote..."
    $response = Read-Host "Push commits and tags to remote? (y/N)"
    if ($response -eq 'y') {
        git push
        git push --tags
        Write-Success "Pushed to remote"
    } else {
        Write-Warning "Remember to push manually: git push && git push --tags"
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  ✨ Publication Complete! ✨" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "📦 Package: @jwikman/bc-code-intelligence-mcp@$version" -ForegroundColor Cyan
Write-Host "🔗 View on npm: https://www.npmjs.com/package/@jwikman/bc-code-intelligence-mcp" -ForegroundColor Cyan
Write-Host ""
Write-Host "To install:" -ForegroundColor Yellow
Write-Host "  npm install -g @jwikman/bc-code-intelligence-mcp" -ForegroundColor White
Write-Host ""

if (-not $DryRun) {
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Verify package on npmjs.org" -ForegroundColor White
    Write-Host "  2. Test installation: npm install -g @jwikman/bc-code-intelligence-mcp" -ForegroundColor White
    Write-Host "  3. Update documentation if needed" -ForegroundColor White
    Write-Host ""
}
