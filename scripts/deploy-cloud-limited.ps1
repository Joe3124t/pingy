param(
  [string]$PagesProject = 'pingy-messenger',
  [string]$CorsOrigin = '',
  [string]$BackendUrl = '',
  [string]$BackendServiceName = 'pingy-backend'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$backendDir = Join-Path $rootDir 'backend'
$frontendDir = Join-Path $rootDir 'frontend'
$runtimeDir = Join-Path $rootDir '.runtime'
New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

function Ensure-Command {
  param([string]$Name)
  $command = Get-Command $Name -ErrorAction SilentlyContinue

  if (-not $command) {
    throw "Required command not found: $Name"
  }
}

function Invoke-Wrangler {
  param(
    [string[]]$Arguments
  )

  & npm.cmd exec wrangler -- @Arguments

  if ($LASTEXITCODE -ne 0) {
    throw "Wrangler command failed: wrangler $($Arguments -join ' ')"
  }
}

function Invoke-Railway {
  param(
    [string[]]$Arguments
  )

  & railway.cmd @Arguments

  if ($LASTEXITCODE -ne 0) {
    throw "Railway command failed: railway $($Arguments -join ' ')"
  }
}

function New-RandomHex {
  param([int]$Bytes = 48)
  $buffer = New-Object byte[] $Bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buffer)
  return ($buffer | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Test-RailwayAuth {
  try {
    railway.cmd whoami >$null 2>&1
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Normalize-Url {
  param([string]$InputUrl)

  $value = ([string]$InputUrl).Trim()

  if (-not $value) {
    return ''
  }

  if ($value -notmatch '^https?://') {
    $value = "https://$value"
  }

  return $value.TrimEnd('/')
}

function Resolve-RailwayBackendUrl {
  param([string]$ServiceName)

  $raw = railway.cmd domain --service $ServiceName --json 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "Railway command failed: railway domain --service $ServiceName --json`n$raw"
  }

  try {
    $parsed = $raw | ConvertFrom-Json

    if ($parsed -is [array]) {
      foreach ($entry in $parsed) {
        $candidate = Normalize-Url -InputUrl $entry.domain
        if ($candidate) {
          return $candidate
        }
      }
    }

    $single = Normalize-Url -InputUrl $parsed.domain
    if ($single) {
      return $single
    }
  } catch {
    # Fallback to regex match below.
  }

  $match = [regex]::Match($raw, '([a-z0-9-]+\.up\.railway\.app)', 'IgnoreCase')
  if ($match.Success) {
    return "https://$($match.Groups[1].Value.ToLower())"
  }

  throw "Could not resolve Railway public domain. Raw output: $raw"
}

function Assert-RailwayContextLinked {
  $raw = railway.cmd status --json 2>&1 | Out-String

  if ($LASTEXITCODE -ne 0) {
    throw @"
Railway project/service is not linked to the backend directory.
Open backend folder and run once:
  cd backend
  railway init
Then rerun this script.
Raw Railway output:
$raw
"@
  }
}

function Get-RailwayVariables {
  $raw = railway.cmd variable list --json 2>&1 | Out-String

  if ($LASTEXITCODE -ne 0) {
    throw "Railway command failed: railway variable list --json`n$raw"
  }

  try {
    return ($raw | ConvertFrom-Json)
  } catch {
    throw "Could not parse Railway variables JSON.`n$raw"
  }
}

function Ensure-RailwayBackendService {
  param([string]$ServiceName)

  railway.cmd service link $ServiceName >$null 2>&1
  if ($LASTEXITCODE -eq 0) {
    return
  }

  Invoke-Railway -Arguments @('add', '--service', $ServiceName, '--json') | Out-Host
  Invoke-Railway -Arguments @('service', 'link', $ServiceName) | Out-Host
}

function Ensure-RailwayPostgres {
  $variables = Get-RailwayVariables

  if ($variables.PSObject.Properties.Name -contains 'DATABASE_URL' -and [string]::IsNullOrWhiteSpace([string]$variables.DATABASE_URL) -eq $false) {
    return
  }

  Invoke-Railway -Arguments @('add', '--database', 'postgres', '--json') | Out-Host
}

function Get-RailwayVariableValue {
  param(
    [object]$Variables,
    [string]$Name
  )

  if (-not $Variables) {
    return ''
  }

  $property = $Variables.PSObject.Properties[$Name]

  if (-not $property) {
    return ''
  }

  $value = [string]$property.Value

  if ([string]::IsNullOrWhiteSpace($value)) {
    return ''
  }

  return $value.Trim()
}

Ensure-Command -Name 'node'
Ensure-Command -Name 'npm.cmd'
Ensure-Command -Name 'railway.cmd'

if (-not $CorsOrigin) {
  $CorsOrigin = "https://$PagesProject.pages.dev"
}

$BackendUrl = Normalize-Url -InputUrl $BackendUrl

if (-not $BackendUrl) {
  if (-not (Test-RailwayAuth)) {
    throw @"
Railway authentication is required.
Run this once in an interactive terminal, then run this script again:
  railway login
"@
  }

  Write-Host 'Deploying backend to Railway...'
  Push-Location $backendDir

  Assert-RailwayContextLinked
  Ensure-RailwayBackendService -ServiceName $BackendServiceName
  Ensure-RailwayPostgres

  npm.cmd install | Out-Host

  $railwayVariables = Get-RailwayVariables
  $accessSecret = Get-RailwayVariableValue -Variables $railwayVariables -Name 'ACCESS_TOKEN_SECRET'
  if (-not $accessSecret) {
    $accessSecret = New-RandomHex -Bytes 48
  }

  $refreshSecret = Get-RailwayVariableValue -Variables $railwayVariables -Name 'REFRESH_TOKEN_SECRET'
  if (-not $refreshSecret) {
    $refreshSecret = New-RandomHex -Bytes 48
  }

  $mediaSecret = Get-RailwayVariableValue -Variables $railwayVariables -Name 'MEDIA_ACCESS_SECRET'
  if (-not $mediaSecret) {
    $mediaSecret = New-RandomHex -Bytes 48
  }

  $passwordResetSecret = Get-RailwayVariableValue -Variables $railwayVariables -Name 'PASSWORD_RESET_SECRET'
  if (-not $passwordResetSecret) {
    $passwordResetSecret = New-RandomHex -Bytes 48
  }

  $webPushPublicKey = Get-RailwayVariableValue -Variables $railwayVariables -Name 'WEB_PUSH_PUBLIC_KEY'
  $webPushPrivateKey = Get-RailwayVariableValue -Variables $railwayVariables -Name 'WEB_PUSH_PRIVATE_KEY'
  $webPushSubject = Get-RailwayVariableValue -Variables $railwayVariables -Name 'WEB_PUSH_SUBJECT'

  if (-not $webPushPublicKey -or -not $webPushPrivateKey) {
    $vapidRaw = node -e "const webpush=require('web-push');process.stdout.write(JSON.stringify(webpush.generateVAPIDKeys()))"
    $vapid = $vapidRaw | ConvertFrom-Json

    if (-not $webPushPublicKey) {
      $webPushPublicKey = [string]$vapid.publicKey
    }

    if (-not $webPushPrivateKey) {
      $webPushPrivateKey = [string]$vapid.privateKey
    }
  }

  if (-not $webPushSubject) {
    $webPushSubject = 'mailto:pingy.notifications@pingy.local'
  }

  Invoke-Railway -Arguments @(
    'variable',
    'set',
    "NODE_ENV=production",
    "DB_AUTO_SCHEMA=true",
    "USE_EMBEDDED_POSTGRES=false",
    "DB_SSL=false",
    'DATABASE_URL=${{Postgres.DATABASE_URL}}',
    "CORS_ORIGIN=$CorsOrigin",
    "ACCESS_TOKEN_SECRET=$accessSecret",
    "REFRESH_TOKEN_SECRET=$refreshSecret",
    "PASSWORD_RESET_SECRET=$passwordResetSecret",
    "PASSWORD_RESET_CODE_TTL_MINUTES=10",
    "PASSWORD_RESET_MAX_ATTEMPTS=5",
    "PASSWORD_RESET_REQUEST_COOLDOWN_SECONDS=45",
    "MEDIA_ACCESS_SECRET=$mediaSecret",
    "WEB_PUSH_PUBLIC_KEY=$webPushPublicKey",
    "WEB_PUSH_PRIVATE_KEY=$webPushPrivateKey",
    "WEB_PUSH_SUBJECT=$webPushSubject",
    "ACCESS_TOKEN_TTL=15m",
    "REFRESH_TOKEN_DAYS=14",
    "API_RATE_LIMIT_WINDOW_MS=60000",
    "API_RATE_LIMIT_MAX=200",
    "AUTH_RATE_LIMIT_MAX=40",
    "MAX_FILE_SIZE_MB=25",
    '--skip-deploys'
  ) | Out-Host

  Invoke-Railway -Arguments @('up', '-d') | Out-Host
  $BackendUrl = Resolve-RailwayBackendUrl -ServiceName $BackendServiceName

  Pop-Location
}

Write-Host "Backend URL: $BackendUrl"
Write-Host 'Checking backend health...'

$healthOk = $false
for ($i = 0; $i -lt 60; $i++) {
  try {
    $health = Invoke-RestMethod -Uri "$BackendUrl/api/health" -Method Get -TimeoutSec 8
    if ($health.status -eq 'ok') {
      $healthOk = $true
      break
    }
  } catch {
    Start-Sleep -Seconds 2
  }
}

if (-not $healthOk) {
  throw "Backend health check failed at $BackendUrl/api/health"
}

Write-Host 'Building frontend...'
Push-Location $frontendDir

$env:VITE_API_URL = "$BackendUrl/api"
$env:VITE_SOCKET_URL = $BackendUrl

npm.cmd run build | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw 'Frontend build failed.'
}

Invoke-Wrangler -Arguments @(
  'pages',
  'deploy',
  'dist',
  '--project-name',
  $PagesProject,
  '--branch',
  'main'
) | Out-Host

Pop-Location

Set-Content -Path (Join-Path $runtimeDir 'latest-cloud-backend-url.txt') -Value $BackendUrl

Write-Host ''
Write-Host 'Done.'
Write-Host "Frontend: https://$PagesProject.pages.dev"
Write-Host "Backend: $BackendUrl"
