param(
    [ValidateSet("preflight", "validate", "publish")]
    [string]$Command = "preflight",
    [string]$Version,
    [string]$Directory
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Repository = "AnatoForge/fieldviz_desktop"
$Branch = "master"
$Gh = $null

function Invoke-External([string]$FilePath, [string[]]$Arguments) {
    Write-Host "`n> $FilePath $($Arguments -join ' ')`n"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Invoke-CaptureAllowFailure([string]$FilePath, [string[]]$Arguments) {
    $PreviousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $Output = (& $FilePath @Arguments 2>&1) -join "`n"
        $ExitCode = $LASTEXITCODE
        return [ordered]@{
            exitCode = $ExitCode
            output = $Output.Trim()
        }
    } finally {
        $ErrorActionPreference = $PreviousPreference
    }
}

function Require-PublicRepository {
    $Status = (& git -C $Root status --porcelain) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Cannot read the public release repository status." }
    if ($Status) { throw "The public release repository must be clean." }
    $CurrentBranch = (& git -C $Root branch --show-current) -join ""
    if ($CurrentBranch -ne $Branch) { throw "Release must run on the $Branch branch." }
    $Remote = (& git -C $Root remote get-url origin) -join ""
    if ($Remote -notmatch [regex]::Escape($Repository)) {
        throw "origin is not $Repository."
    }
}

function Require-GitHubCli {
    $Command = Get-Command gh -ErrorAction SilentlyContinue
    if ($Command) {
        $script:Gh = $Command.Source
    } elseif (Test-Path -LiteralPath "$env:ProgramFiles\GitHub CLI\gh.exe") {
        $script:Gh = "$env:ProgramFiles\GitHub CLI\gh.exe"
    } else {
        throw "GitHub CLI is missing. Run: winget install --id GitHub.cli --exact"
    }
    & $script:Gh auth status --hostname github.com
    if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated. Run: .\build.cmd gh-login" }
}

function Require-Version([string]$Value) {
    if ($Value -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
        throw "Version must be X.Y.Z, received: $Value"
    }
}

function Get-ReleaseAssets([string]$ReleaseVersion, [string]$ReleaseDirectory) {
    Require-Version $ReleaseVersion
    if (-not $ReleaseDirectory) { throw "Release directory is required." }
    $ResolvedDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory -ErrorAction Stop).Path
    $StatePath = Join-Path $ResolvedDirectory "release-state.json"
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        throw "release-state.json is missing."
    }
    $State = Get-Content -Raw -Encoding UTF8 -LiteralPath $StatePath | ConvertFrom-Json
    if ($State.version -ne $ReleaseVersion -or $State.sourceTag -ne "v$ReleaseVersion") {
        throw "release-state.json does not match the requested version."
    }
    $InstallerName = "FieldViz_${ReleaseVersion}_x64_Setup.exe"
    $InstallerSignatureName = "$InstallerName.sig"
    $ExpectedNames = @($InstallerName, $InstallerSignatureName, "latest.json")
    $Properties = @($State.assets.PSObject.Properties)
    $ActualNames = @($Properties.Name | Sort-Object)
    if ((Compare-Object ($ExpectedNames | Sort-Object) $ActualNames)) {
        throw "Release assets must contain one versioned installer, its signature, and latest.json."
    }
    $Paths = @()
    foreach ($Name in $ExpectedNames) {
        $Path = Join-Path $ResolvedDirectory $Name
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Release asset is missing: $Name" }
        $Expected = $State.assets.$Name
        $File = Get-Item -LiteralPath $Path
        $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($File.Length -ne [long]$Expected.size -or $Hash -ne $Expected.sha256) {
            throw "Release asset verification failed: $Name"
        }
        $Paths += $Path
    }
    $Manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $ResolvedDirectory "latest.json") | ConvertFrom-Json
    $ExpectedPrefix = "https://github.com/$Repository/releases/download/v$ReleaseVersion/"
    $Target = $Manifest.platforms.'windows-x86_64'
    $InstallerRecord = $State.assets.$InstallerName
    $InstallerSignature = (Get-Content -Raw -Encoding ASCII -LiteralPath (Join-Path $ResolvedDirectory $InstallerSignatureName)).Trim()
    if (
        $Manifest.version -ne $ReleaseVersion -or
        -not $Target.url.StartsWith($ExpectedPrefix) -or
        $Target.sha256 -ne $InstallerRecord.sha256 -or
        [long]$Target.size -ne [long]$InstallerRecord.size -or
        $Target.signature -ne $InstallerSignature
    ) {
        throw "latest.json has an invalid version, URL, or installer digest."
    }
    return $Paths
}

function Publish-Release([string]$ReleaseVersion, [string[]]$Assets) {
    $Tag = "v$ReleaseVersion"
    $View = Invoke-CaptureAllowFailure $script:Gh @("release", "view", $Tag, "--repo", $Repository, "--json", "isDraft,assets")
    if ($View.exitCode -eq 0) {
        $Release = $View.output | ConvertFrom-Json
        if (-not $Release.isDraft) {
            $RemoteNames = @($Release.assets.name | Sort-Object)
            $LocalNames = @($Assets | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object)
            if (Compare-Object $LocalNames $RemoteNames) {
                throw "Published release $Tag has incomplete assets; refusing to overwrite it."
            }
            Write-Host "$Tag is already published." -ForegroundColor Green
            return
        }
        Invoke-External $script:Gh (@("release", "upload", $Tag) + $Assets + @("--clobber", "--repo", $Repository))
    } elseif ($View.output -match '(?im)^release not found\s*$') {
        Invoke-External $script:Gh (@("release", "create", $Tag) + $Assets + @(
            "--draft", "--target", $Branch, "--title", "FieldViz $Tag",
            "--notes", "FieldViz $ReleaseVersion", "--repo", $Repository
        ))
    } else {
        throw "Could not inspect release $Tag. $($View.output)"
    }
    Invoke-External $script:Gh @("release", "edit", $Tag, "--draft=false", "--latest", "--repo", $Repository)
    Write-Host "Published $Tag." -ForegroundColor Green
}

try {
    Set-Location $Root
    switch ($Command) {
        "preflight" {
            Require-PublicRepository
            Require-GitHubCli
            Write-Host "Public release environment check passed." -ForegroundColor Green
        }
        "validate" {
            $null = Get-ReleaseAssets $Version $Directory
            Write-Host "Release asset validation passed." -ForegroundColor Green
        }
        "publish" {
            Require-PublicRepository
            Require-GitHubCli
            $Assets = @(Get-ReleaseAssets $Version $Directory)
            Publish-Release $Version $Assets
        }
    }
    exit 0
} catch {
    Write-Host "`nFailed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
