@echo off
set "FIELDVIZ_DESKTOP_BUILD_FILE=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$lines = [IO.File]::ReadAllLines($env:FIELDVIZ_DESKTOP_BUILD_FILE, [Text.Encoding]::UTF8); $marker = '::# <FIELDVIZ_DESKTOP_' + 'POWERSHELL>'; $start = [Array]::IndexOf($lines, $marker) + 1; $body = ($lines[$start..($lines.Length - 1)] | ForEach-Object { $_.Substring(2) }) -join [Environment]::NewLine; & ([scriptblock]::Create($body)) @args" %*
exit /b %errorlevel%

::# <FIELDVIZ_DESKTOP_POWERSHELL>
::param([string]$Requested, [string]$Version, [string]$Directory)
::
::$ErrorActionPreference = "Stop"
::$utf8 = [Text.UTF8Encoding]::new($false)
::$OutputEncoding = [Console]::OutputEncoding = $utf8
::$root = Split-Path -Parent $env:FIELDVIZ_DESKTOP_BUILD_FILE
::$publisher = Join-Path $root "scripts\publish.ps1"
::$publisherTest = Join-Path $root "tests\test_publish.ps1"
::$scriptName = ".\build.cmd"
::$menu = @(
::    @{ Command = "preflight"; Description = "检查 GitHub 发布环境"; Invocation = "scripts\publish.ps1 preflight" }
::    @{ Command = "test";      Description = "运行发布脚本自检";     Invocation = "tests\test_publish.ps1" }
::    @{ Command = "validate";  Description = "校验指定版本发布产物"; Invocation = "scripts\publish.ps1 validate VERSION DIRECTORY" }
::    @{ Command = "release";   Description = "独立发布指定版本";     Invocation = "scripts\publish.ps1 release VERSION [DIRECTORY]" }
::    @{ Command = "publish";   Description = "发布指定目录产物";     Invocation = "scripts\publish.ps1 publish VERSION DIRECTORY" }
::    @{ Command = "exit";      Description = "退出";                 Invocation = "" }
::)
::
::function Show-Help {
::    Write-Host "用法:"
::    Write-Host "  $scriptName                              打开三列交互菜单"
::    Write-Host "  $scriptName preflight                    检查 GitHub 发布环境"
::    Write-Host "  $scriptName test                         运行发布脚本自检"
::    Write-Host "  $scriptName validate VERSION DIRECTORY   校验发布产物"
::    Write-Host "  $scriptName release VERSION [DIRECTORY]  独立发布版本"
::    Write-Host "  $scriptName publish VERSION DIRECTORY    发布指定目录产物"
::    Write-Host "  $scriptName help                         查看帮助"
::}
::
::function Get-DisplayWidth([string]$Text) {
::    $width = 0
::    foreach ($character in $Text.ToCharArray()) {
::        $width += if ([int]$character -le 127) { 1 } else { 2 }
::    }
::    return $width
::}
::
::function Pad-DisplayWidth([string]$Text, [int]$Width) {
::    return $Text + (" " * [Math]::Max(0, $Width - (Get-DisplayWidth $Text)))
::}
::
::function Select-BuildCommand {
::    if (-not (Get-Command fzf.exe -ErrorAction SilentlyContinue)) {
::        throw "未找到 fzf, 请先安装并确保 fzf.exe 已加入 PATH"
::    }
::    $rows = $menu | ForEach-Object {
::        "$(Pad-DisplayWidth $_.Command 12)  $(Pad-DisplayWidth $_.Description 24)  $($_.Invocation)"
::    }
::    $selected = $rows | & fzf.exe --height=80% --layout=reverse --border --cycle `
::        --header="命令          说明                      实际执行" `
::        --prompt="fieldviz desktop > " --pointer=">" --marker="*" --no-multi
::    if ($LASTEXITCODE -eq 130 -or -not $selected) { return "exit" }
::    if ($LASTEXITCODE -ne 0) { throw "fzf 执行失败, 退出码 $LASTEXITCODE" }
::    return ($selected -split '\s+', 2)[0]
::}
::
::function Read-ReleaseVersion {
::    if ($Version) { $result = $Version.Trim() } else { $result = (Read-Host "请输入发布版本号 (X.Y.Z)").Trim() }
::    if ($result -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
::        throw "无效版本号: $result, 期望格式为 X.Y.Z"
::    }
::    if (-not $Version) {
::        $confirmation = (Read-Host "请再次输入发布版本号").Trim()
::        if ($confirmation -ne $result) { throw "两次输入的版本号不一致" }
::    }
::    return $result
::}
::
::function Read-ReleaseDirectory([bool]$Required) {
::    if ($Directory) { return $Directory }
::    if (-not $Required) { return $null }
::    $result = (Read-Host "请输入发布产物目录").Trim()
::    if (-not $result) { throw "发布产物目录不能为空" }
::    return $result
::}
::
::function Invoke-PowerShellFile([string]$File, [string[]]$Arguments) {
::    Write-Host "`n> powershell.exe -File $File $($Arguments -join ' ')`n"
::    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $File @Arguments
::    if ($LASTEXITCODE -ne 0) { throw "命令执行失败, 退出码 $LASTEXITCODE" }
::}
::
::try {
::    Set-Location $root
::    if ($Requested -in @("--help", "-h", "help")) { Show-Help; exit 0 }
::    $command = if (-not $Requested -or $Requested -eq "menu") { Select-BuildCommand } else { $Requested.ToLowerInvariant() }
::    if ($command -eq "exit") { exit 0 }
::
::    switch ($command) {
::        "preflight" { Invoke-PowerShellFile $publisher @("preflight") }
::        "test" { Invoke-PowerShellFile $publisherTest @() }
::        "validate" {
::            $releaseVersion = Read-ReleaseVersion
::            $releaseDirectory = Read-ReleaseDirectory $true
::            Invoke-PowerShellFile $publisher @("validate", $releaseVersion, $releaseDirectory)
::        }
::        "release" {
::            $releaseVersion = Read-ReleaseVersion
::            $arguments = @("release", $releaseVersion)
::            $releaseDirectory = Read-ReleaseDirectory $false
::            if ($releaseDirectory) { $arguments += $releaseDirectory }
::            Invoke-PowerShellFile $publisher $arguments
::        }
::        "publish" {
::            $releaseVersion = Read-ReleaseVersion
::            $releaseDirectory = Read-ReleaseDirectory $true
::            Invoke-PowerShellFile $publisher @("publish", $releaseVersion, $releaseDirectory)
::        }
::        default { throw "未知操作: $command, 请使用 $scriptName help 查看选项" }
::    }
::    Write-Host "`n操作完成。"
::    exit 0
::} catch {
::    Write-Host "`n操作失败: $($_.Exception.Message)" -ForegroundColor Red
::    exit 1
::}
