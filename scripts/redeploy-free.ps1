param(
  [string]$PagesProject = 'pingy-messenger'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

Write-Host 'Starting Pingy free deployment pipeline...'

# Ensure docker network exists
if (-not (docker network inspect pingy-net 2>$null)) {
  docker network create pingy-net | Out-Null
}

# Start postgres
if (-not (docker ps -a --format '{{.Names}}' | Select-String '^pingy-postgres$')) {
  docker run -d --name pingy-postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=pingy -p 5432:5432 postgres:16-alpine | Out-Null
}

if (-not (docker ps --format '{{.Names}}' | Select-String '^pingy-postgres$')) {
  docker start pingy-postgres | Out-Null
}

cmd /c "docker network connect pingy-net pingy-postgres >nul 2>nul"

# Wait for postgres readiness
for ($i = 0; $i -lt 40; $i++) {
  docker exec pingy-postgres pg_isready -U postgres -d pingy >$null 2>&1
  if ($LASTEXITCODE -eq 0) { break }
  Start-Sleep -Seconds 1
}

# Apply schema
Get-Content .\backend\db\schema.sql | docker exec -i pingy-postgres psql -U postgres -d pingy >$null

# Build and run backend
$backendImage = 'pingy-backend-local'
docker build -t $backendImage -f .\backend\Dockerfile.local .\backend | Out-Null

docker rm -f pingy-backend >$null 2>&1

docker run -d --name pingy-backend --network pingy-net -p 4000:4000 `
  -e NODE_ENV=production `
  -e PORT=4000 `
  -e DATABASE_URL=postgres://postgres:postgres@pingy-postgres:5432/pingy `
  -e DB_SSL=false `
  -e ACCESS_TOKEN_SECRET=pingy-local-access-secret-change-this-please-1234567890 `
  -e REFRESH_TOKEN_SECRET=pingy-local-refresh-secret-change-this-please-1234567890 `
  -e ACCESS_TOKEN_TTL=15m `
  -e REFRESH_TOKEN_DAYS=14 `
  -e CORS_ORIGIN=* `
  -e API_RATE_LIMIT_WINDOW_MS=60000 `
  -e API_RATE_LIMIT_MAX=120 `
  -e AUTH_RATE_LIMIT_MAX=20 `
  -e MAX_FILE_SIZE_MB=25 `
  $backendImage | Out-Null

# Start tunnel
docker rm -f pingy-tunnel >$null 2>&1
docker run -d --name pingy-tunnel cloudflare/cloudflared:latest tunnel --no-autoupdate --url http://host.docker.internal:4000 | Out-Null

$tunnelUrl = ''
for ($i = 0; $i -lt 45; $i++) {
  $prevErr = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $logs = (docker logs pingy-tunnel 2>&1 | Out-String)
  $ErrorActionPreference = $prevErr
  $match = $logs | Select-String -Pattern 'https://[-a-z0-9]+\.trycloudflare\.com' | Select-Object -Last 1
  if ($match) {
    $tunnelUrl = $match.Matches[0].Value
    break
  }
  Start-Sleep -Seconds 1
}

if (-not $tunnelUrl) {
  throw 'Could not get Cloudflare tunnel URL from container logs.'
}

# Build and deploy frontend with tunnel URL
Push-Location .\frontend
$env:VITE_API_URL = "$tunnelUrl/api"
$env:VITE_SOCKET_URL = $tunnelUrl
npm.cmd run build | Out-Host
npm.cmd exec wrangler -- pages deploy dist --project-name $PagesProject --branch main | Out-Host
Pop-Location

# Ensure auto-restart

docker update --restart unless-stopped pingy-postgres pingy-backend pingy-tunnel >$null

Write-Host "Done. Backend tunnel: $tunnelUrl"
Write-Host 'Frontend: https://pingy-messenger.pages.dev'
