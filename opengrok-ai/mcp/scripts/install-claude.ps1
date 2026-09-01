<#
.SYNOPSIS
  把 opengrok-mcp 注册到 Windows 上的 Claude Desktop。

.DESCRIPTION
  在 %APPDATA%\Claude\claude_desktop_config.json 里写入（或合并）一个
  `opengrok` 条目，让 Claude Desktop 可以 stdio 方式把它作为子进程启动。
  同一文件中已有的其它 MCP 服务条目会被保留。

.PARAMETER BaseUrl
  OpenGrok REST 根地址。

.PARAMETER Token
  Bearer 令牌。不传时会以隐藏方式提示输入。

.PARAMETER EnableWriteTools
  设为 $true 时把破坏性写工具也注册进去；默认 $false。

.PARAMETER Uninstall
  卸载：把 `opengrok` 条目从配置中移除，而不是新增。

.EXAMPLE
  .\scripts\install-claude.ps1 -Token dev-token-123

.EXAMPLE
  .\scripts\install-claude.ps1 -Uninstall
#>
param(
  [string]$BaseUrl = "http://localhost:8081/api/v1",
  [string]$Token = "",
  [switch]$EnableWriteTools,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$cfgDir  = Join-Path $env:APPDATA "Claude"
$cfgPath = Join-Path $cfgDir "claude_desktop_config.json"
$serverRel = "opengrok-ai\mcp\dist\index.js"
$serverAbs = Join-Path (Get-Location).Path $serverRel

# 以安全输入的方式读取 token，避免在控制台回显。
function Read-Token() {
  if ($Token) { return $Token }
  $secure = Read-Host "请输入 OPENGROK_TOKEN（隐藏输入）" -AsSecureString
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
}

if (-not (Test-Path $cfgDir)) {
  New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
}

# 读取已有配置，找不到或解析失败就重头来。
if (Test-Path $cfgPath) {
  try {
    $cfg = Get-Content -Raw $cfgPath | ConvertFrom-Json
  } catch {
    Write-Warning "现有 $cfgPath 不是合法 JSON —— 已备份后重新生成。"
    Copy-Item $cfgPath "$cfgPath.bak" -Force
    $cfg = [pscustomobject]@{ mcpServers = [pscustomobject]@{} }
  }
} else {
  $cfg = [pscustomobject]@{ mcpServers = [pscustomobject]@{} }
}

if (-not $cfg.mcpServers) {
  $cfg | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) -Force
}

if ($Uninstall) {
  $cfg.mcpServers.PSObject.Properties.Remove("opengrok")
  Write-Host "已从 $cfgPath 移除 'opengrok'。"
} else {
  if (-not (Test-Path $serverAbs)) {
    Write-Warning "找不到服务器入口：$serverAbs"
    Write-Warning "请先运行 'npm run build'。"
    return 1
  }

  $tok = Read-Token
  if (-not $tok) {
    Write-Error "必须提供 Token。"
    return 1
  }

  $entry = [pscustomobject]@{
    command = "node"
    args    = @(
      (($serverAbs -replace "\\","/"))
      , "--stdio"
    )
    env     = [pscustomobject]@{
      OPENGROK_BASE_URL   = $BaseUrl
      OPENGROK_AUTH_TYPE  = "bearer"
      OPENGROK_TOKEN      = $tok
      ENABLE_WRITE_TOOLS  = ($EnableWriteTools.IsPresent ? "true" : "false")
      LOG_LEVEL           = "info"
    }
  }

  if ($cfg.mcpServers.PSObject.Properties.Name -contains "opengrok") {
    Write-Host "正在更新 $cfgPath 中已有的 'opengrok' 条目。"
    $cfg.mcpServers.opengrok = $entry
  } else {
    $cfg.mcpServers | Add-Member -NotePropertyName opengrok -NotePropertyValue $entry -Force
    Write-Host "已在 $cfgPath 中新增 'opengrok' 条目。"
  }
}

# 格式化输出：depth 10 让嵌套 env 也能完整展示。
$json = $cfg | ConvertTo-Json -Depth 10
Set-Content -Path $cfgPath -Value $json -Encoding UTF8

Write-Host ""
Write-Host "完成。重启 Claude Desktop 后即可识别新服务。"
Write-Host "日志位置：$env:APPDATA\Claude\logs\mcp.log"