param(
  [string]$PagesProject = 'pingy-messenger',
  [int]$BackendPort = 4000
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$backendDir = Join-Path $rootDir 'backend'
$frontendDir = Join-Path $rootDir 'frontend'
$runtimeDir = Join-Path $rootDir '.runtime'

New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

$backendPidFile = Join-Path $runtimeDir 'backend.pid'
$backendStdout = Join-Path $runtimeDir 'backend.stdout.log'
$backendStderr = Join-Path $runtimeDir 'backend.stderr.log'
$tunnelPidFile = Join-Path $runtimeDir 'tunnel.pid'
$tunnelStdout = Join-Path $runtimeDir 'tunnel.stdout.log'
$tunnelStderr = Join-Path $runtimeDir 'tunnel.stderr.log'
$latestTunnelFile = Join-Path $runtimeDir 'latest-tunnel-url.txt'

function Stop-TrackedProcess {
  param(
    [string]$PidFile
  )

  if (-not (Test-Path $PidFile)) {
    return
  }

  $rawPid = (Get-Content $PidFile -Raw).Trim()

  if ($rawPid -match '^\d+$') {
    $existing = Get-Process -Id ([int]$rawPid) -ErrorAction SilentlyContinue

    if ($existing) {
      Stop-Process -Id $existing.Id -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 1
    }
  }

  Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

function Stop-OrphanPingyProcesses {
  param(
    [int]$Port
  )

  $targets = Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq 'node.exe' -and $_.CommandLine -like '*src/server.js*' -and $_.CommandLine -like '*Web\\Pingy\\backend*') -or
    ($_.Name -eq 'cloudflared.exe' -and $_.CommandLine -like '*trycloudflare*' -and $_.CommandLine -like "*127.0.0.1:$Port*")
  }

  foreach ($target in $targets) {
    Stop-Process -Id $target.ProcessId -Force -ErrorAction SilentlyContinue
  }
}

function Stop-PotentialDockerConflicts {
  $docker = Get-Command docker -ErrorAction SilentlyContinue

  if (-not $docker) {
    return
  }

  foreach ($containerName in @('pingy-backend', 'pingy-tunnel')) {
    docker stop $containerName >$null 2>&1
  }
}

function Ensure-Command {
  param(
    [string]$Name
  )

  $command = Get-Command $Name -ErrorAction SilentlyContinue

  if (-not $command) {
    throw "Required command not found: $Name"
  }
}

Ensure-Command -Name 'node'
Ensure-Command -Name 'npm.cmd'
Ensure-Command -Name 'cloudflared'

Write-Host 'Stopping old Pingy processes (if any)...'
Stop-TrackedProcess -PidFile $backendPidFile
Stop-TrackedProcess -PidFile $tunnelPidFile
Stop-OrphanPingyProcesses -Port $BackendPort
Stop-PotentialDockerConflicts

if (Test-Path $backendStdout) { Remove-Item $backendStdout -Force -ErrorAction SilentlyContinue }
if (Test-Path $backendStderr) { Remove-Item $backendStderr -Force -ErrorAction SilentlyContinue }
if (Test-Path $tunnelStdout) { Remove-Item $tunnelStdout -Force -ErrorAction SilentlyContinue }
if (Test-Path $tunnelStderr) { Remove-Item $tunnelStderr -Force -ErrorAction SilentlyContinue }

Write-Host 'Installing backend dependencies...'
Push-Location $backendDir
npm.cmd install | Out-Host
Pop-Location

Write-Host 'Starting backend with embedded PostgreSQL...'
$backendDirEscaped = $backendDir.Replace("'", "''")
$backendScript = @"
Set-Location '$backendDirEscaped'
`$env:NODE_ENV='production'
`$env:PORT='$BackendPort'
`$env:USE_EMBEDDED_POSTGRES='true'
`$env:EMBEDDED_DB_DIR='.embedded-postgres'
`$env:EMBEDDED_DB_PORT='5433'
`$env:EMBEDDED_DB_USER='postgres'
`$env:EMBEDDED_DB_PASSWORD='postgres'
`$env:EMBEDDED_DB_NAME='pingy'
`$env:DB_AUTO_SCHEMA='true'
`$env:DB_SSL='false'
`$env:ACCESS_TOKEN_SECRET='pingy-option3-access-secret-change-this-1234567890'
`$env:REFRESH_TOKEN_SECRET='pingy-option3-refresh-secret-change-this-1234567890'
`$env:ACCESS_TOKEN_TTL='15m'
`$env:REFRESH_TOKEN_DAYS='14'
`$env:CORS_ORIGIN='*'
`$env:API_RATE_LIMIT_WINDOW_MS='60000'
`$env:API_RATE_LIMIT_MAX='200'
`$env:AUTH_RATE_LIMIT_MAX='40'
`$env:MAX_FILE_SIZE_MB='25'
node src/server.js
"@

$backendProc = Start-Process `
  -FilePath 'powershell.exe' `
  -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $backendScript `
  -PassThru `
  -WindowStyle Hidden `
  -RedirectStandardOutput $backendStdout `
  -RedirectStandardError $backendStderr

Set-Content -Path $backendPidFile -Value $backendProc.Id

$healthUrl = "http://127.0.0.1:$BackendPort/api/health"
$healthy = $false
for ($i = 0; $i -lt 90; $i++) {
  try {
    $health = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 3
    if ($health.status -eq 'ok') {
      $healthy = $true
      break
    }
  } catch {
    Start-Sleep -Milliseconds 750
  }
}

if (-not $healthy) {
  $backendErrors = if (Test-Path $backendStderr) { Get-Content $backendStderr -Raw } else { '' }
  throw "Backend failed to start. Check log: $backendStderr`n$backendErrors"
}

Write-Host 'Starting Cloudflare tunnel...'
$tunnelProc = Start-Process `
  -FilePath 'cloudflared' `
  -ArgumentList 'tunnel', '--no-autoupdate', '--url', "http://127.0.0.1:$BackendPort" `
  -PassThru `
  -WindowStyle Hidden `
  -RedirectStandardOutput $tunnelStdout `
  -RedirectStandardError $tunnelStderr

Set-Content -Path $tunnelPidFile -Value $tunnelProc.Id

$tunnelUrl = ''
for ($i = 0; $i -lt 120; $i++) {
  $stdout = if (Test-Path $tunnelStdout) { Get-Content $tunnelStdout -Raw } else { '' }
  $stderr = if (Test-Path $tunnelStderr) { Get-Content $tunnelStderr -Raw } else { '' }
  $combined = "$stdout`n$stderr"
  $match = [regex]::Match($combined, 'https://[-a-z0-9]+\.trycloudflare\.com')

  if ($match.Success) {
    $tunnelUrl = $match.Value
    break
  }

  Start-Sleep -Seconds 1
}

if (-not $tunnelUrl) {
  throw "Could not detect Cloudflare tunnel URL. Check logs: $tunnelStdout / $tunnelStderr"
}

Set-Content -Path $latestTunnelFile -Value $tunnelUrl

Write-Host "Tunnel URL: $tunnelUrl"
Write-Host 'Building and deploying frontend to Cloudflare Pages...'

Push-Location $frontendDir
$env:VITE_API_URL = "$tunnelUrl/api"
$env:VITE_SOCKET_URL = $tunnelUrl
npm.cmd run build | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw 'Frontend build failed.'
}

npm.cmd exec wrangler -- pages deploy dist --project-name $PagesProject --branch main | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw 'Cloudflare Pages deploy failed.'
}

Pop-Location

Write-Host ''
Write-Host 'Done.'
Write-Host "Frontend: https://$PagesProject.pages.dev"
Write-Host "Backend tunnel: $tunnelUrl"
Write-Host "Backend PID: $($backendProc.Id)"
Write-Host "Tunnel PID: $($tunnelProc.Id)"
Write-Host "Logs: $runtimeDir"
