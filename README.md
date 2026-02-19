# Pingy (Production v1.1)

Realtime 1-to-1 web messenger built with:
- Backend: Node.js, Express, Socket.io, PostgreSQL, JWT, bcrypt, Multer, S3-compatible upload
- Frontend: React (Vite), Tailwind CSS, Socket.io client

## Structure

```text
backend/
  db/
  src/
    controllers/
    middleware/
    models/
    routes/
    schemas/
    services/
    sockets/
    storage/
frontend/
  src/
    components/
    context/store/
    hooks/
    layouts/
    services/
```

## Backend Setup

1. Copy `backend/.env.example` to `backend/.env` and fill values.
2. Create PostgreSQL database (example: `pingy`).
3. Run schema:

```powershell
psql "postgres://postgres:postgres@localhost:5432/pingy" -f backend/db/schema.sql
```

4. Start backend:

```powershell
cd backend
npm.cmd install
npm.cmd run dev
```

## Frontend Setup

1. Copy `frontend/.env.example` to `frontend/.env`.
2. Start frontend:

```powershell
cd frontend
npm.cmd install
npm.cmd run dev
```

Frontend runs at `http://localhost:5173` and backend at `http://localhost:4000`.

## Free Deploy (Option 3, No Docker)

This mode runs backend with embedded PostgreSQL on your machine, exposes it with Cloudflare Tunnel, then deploys frontend to Cloudflare Pages.

```powershell
.\scripts\redeploy-free-option3.ps1
```

Requirements:
- `node`, `npm`, `cloudflared`
- Cloudflare Pages authenticated in `wrangler`

## Free Cloud Deploy (Limited Usage, No Laptop Dependency)

This mode uses cloud hosting for backend (Railway free tier style) and Cloudflare Pages for frontend.

```powershell
.\scripts\deploy-cloud-limited.ps1
```

If Railway is not authenticated yet, run once in an interactive terminal:

```powershell
railway login
```

And link backend folder once:

```powershell
cd backend
railway init
cd ..
```

You can also provide an already deployed backend URL:

```powershell
.\scripts\deploy-cloud-limited.ps1 -BackendUrl "https://your-backend.up.railway.app"
```

Notes:
- This is cloud-based, so app stays online when laptop is closed.
- Free tiers usually have limits (sleep/quota) depending on provider.
- The script deploys frontend to `https://pingy-messenger.pages.dev`.

## Core Implemented Features

- Register, login, access + refresh token flow
- Protected REST and WebSocket auth
- Realtime direct messaging with DB-first persistence
- End-to-end encrypted text messages (ECDH + AES-256-GCM, client-side encryption)
- Media upload (image, video, pdf, docx) with MIME + size validation
- Voice messaging (record, duration, upload, inline player)
- Presence tracking (online/offline + last seen)
- Delivered + seen indicators
- Typing indicator with timeout behavior
- Block / unblock users (messaging + presence restrictions)
- Conversation delete (`scope=self` and `scope=both` soft-delete)
- Settings API (profile, privacy, chat preferences, blocked users)
- Per-conversation wallpaper settings
- Expiring signed media URLs (`/uploads` signed links + `/api/media/access` for remote media)
- Rate limiting, sanitization, and structured error handling

## Storage

- Uses S3-compatible storage when S3 env vars are configured.
- Falls back to local storage (`backend/uploads`) for local development.

## Important Notes

- `message.type` supports: `text`, `image`, `video`, `file`, `voice`
- WebSocket events are handled separately under `backend/src/sockets`
- Conversation and message ordering are enforced server-side by persisted timestamps
- Schema updates in `backend/db/schema.sql` are additive (`CREATE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS`) and do not drop user data.
