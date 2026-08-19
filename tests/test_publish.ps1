$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Temporary = Join-Path ([IO.Path]::GetTempPath()) "fieldviz-publish-test-$([guid]::NewGuid())"
$Version = "1.2.3"

try {
    $null = New-Item -ItemType Directory -Path $Temporary
    $InstallerName = "FieldViz_${Version}_x64_Setup.exe"
    $InstallerPath = Join-Path $Temporary $InstallerName
    [IO.File]::WriteAllBytes($InstallerPath, [byte[]](1, 2, 3, 4))
    $InstallerHash = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $Manifest = @{
        version = $Version
        platforms = @{
            "windows-x86_64" = @{
                url = "https://github.com/AnatoForge/fieldviz_desktop/releases/download/v$Version/$InstallerName"
                sha256 = $InstallerHash
                size = 4
            }
        }
    } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $Temporary "latest.json"), $Manifest, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $Temporary "latest.json.sig"), "signature", [Text.Encoding]::ASCII)

    $Assets = @{}
    foreach ($Name in @($InstallerName, "latest.json", "latest.json.sig")) {
        $Path = Join-Path $Temporary $Name
        $Assets[$Name] = @{
            sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
            size = (Get-Item -LiteralPath $Path).Length
        }
    }
    $State = @{
        version = $Version
        sourceTag = "v$Version"
        sourceCommit = "test"
        assets = $Assets
    } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $Temporary "release-state.json"), $State, [Text.Encoding]::UTF8)

    & (Join-Path $Root "build.cmd") validate $Version $Temporary
    if ($LASTEXITCODE -ne 0) { throw "Valid release assets failed validation." }

    [IO.File]::WriteAllText((Join-Path $Temporary "latest.json.sig"), "modified", [Text.Encoding]::ASCII)
    & (Join-Path $Root "build.cmd") validate $Version $Temporary
    if ($LASTEXITCODE -eq 0) { throw "Modified release assets unexpectedly passed validation." }

    Write-Host "PowerShell publisher tests passed" -ForegroundColor Green
    exit 0
} finally {
    if (Test-Path -LiteralPath $Temporary) {
        [IO.Directory]::Delete($Temporary, $true)
    }
}
