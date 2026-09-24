# Blog Platform

A lightweight personal blog platform built with Vue 3 + Vite (frontend) and Node.js + Express (backend).

## Tech Stack

### Frontend
- **Vue 3** - Progressive JavaScript framework
- **Vite** - Next generation frontend tooling
- **Vue Router** - Official router for Vue.js
- **Pinia** - State management library
- **Element Plus** - Vue 3 UI component library
- **Axios** - HTTP client
- **Marked** - Markdown parser

### Backend
- **Node.js** - JavaScript runtime
- **Express** - Web application framework
- **better-sqlite3** - Fast SQLite3 library
- **jsonwebtoken** - JWT implementation
- **cors** - Cross-Origin Resource Sharing

## Project Structure

```
blog-platform/
├── frontend/          # Vue 3 + Vite frontend
│   ├── src/
│   │   ├── api/       # API client
│   │   ├── components/# Reusable components
│   │   ├── router/    # Vue Router configuration
│   │   ├── stores/    # Pinia stores
│   │   └── views/     # Page components
│   └── ...
├── backend/           # Node.js + Express backend
│   ├── db/            # Database initialization and seeds
│   ├── routes/        # API routes
│   ├── middleware/    # Express middleware
│   └── data/          # SQLite database file
└── README.md
```

## Getting Started

### Prerequisites

- Node.js 18+ 
- npm or yarn

### Installation

1. **Clone or navigate to the project directory**

```bash
cd blog-platform
```

2. **Install backend dependencies**

```bash
cd backend
npm install
```

3. **Install frontend dependencies**

```bash
cd ../frontend
npm install
```

### Initialize the database with seed data

```bash
cd ../backend
npm run seed
```

`npm run seed` is **idempotent**: running it repeatedly never creates duplicate
articles (existing articles are matched by title and skipped, user-created
articles are preserved). To wipe and rebuild the article list, use:

```bash
npm run seed -- --reset
```

### Lifecycle scripts (recommended)

`scripts/` orchestrates the whole startup-to-shutdown flow. Every stage prints
an explicit `[OK]` / `[FAIL:<stage>]` result; a failed startup exits non-zero
and cleans up anything it already started:

| Stage | What is checked / done |
|-------|------------------------|
| `config` | `PORT` / `FRONTEND_PORT` are integers in 1–65535 |
| `port-check` | both ports are free; a *managed* service that is already running is reported, a stale pidfile is reaped, a foreign listener is refused (never killed) |
| `dependencies` | Node 18+, backend packages (native `better-sqlite3` actually loaded), frontend packages + rollup/esbuild native binaries |
| `storage` | `backend/data/` exists and is writable |
| `database` | schema created in `backend/data/blog.db` |
| `seed` | idempotent article import (see flags below) |
| `build` | `vite build` (production only) |
| `backend` / `frontend` | services start and pass an HTTP health check |
| `cleanup` | on stop or failure, process groups are terminated and ports verified free |

```bash
# Development (backend: npm run dev / node --watch, frontend: vite)
scripts/dev.sh                 # init DB + seed + start both
scripts/dev.sh --no-seed       # skip seed import
scripts/dev.sh --reset-seed    # wipe articles, then seed

# Production (vite build, backend: npm start, frontend: vite preview)
scripts/prod.sh
scripts/prod.sh --no-build     # reuse existing frontend/dist
scripts/prod.sh --no-seed

# Inspect / stop
scripts/status.sh
scripts/stop.sh                # graceful, idempotent; verifies ports are freed
scripts/stop.sh --purge        # also remove .run/ logs and pidfiles
```

Environment variables: `PORT` (backend, default `3001`) and `FRONTEND_PORT`
(default `5173`). Runtime artifacts (pids, logs) live in `.run/`.

### Running the Application

The individual npm commands still work exactly as before.

1. **Start the backend server (port 3001)**

```bash
cd backend
npm run dev
```

The API server will start at `http://localhost:3001`. Startup is staged
(config → dependencies → storage/database → listen); a failure prints the
stage, e.g. `[server][FAIL:storage] ...`, and exits non-zero. SIGINT/SIGTERM
close the HTTP server and database cleanly.

2. **Start the frontend development server (port 5173)**

Open a new terminal:

```bash
cd frontend
npm run dev
```

The frontend will be available at `http://localhost:5173`

## Features

- **Article Management**: Create, read, update, and delete blog articles
- **Markdown Support**: Write articles in Markdown with live preview
- **Tag System**: Organize articles with tags and filter by tags
- **Pagination**: Navigate through articles with pagination (10 per page)
- **Admin Panel**: Protected admin area for managing articles
- **JWT Authentication**: Secure admin login with JSON Web Tokens

## API Endpoints

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | `/api/auth/login` | Admin login | No |
| GET | `/api/articles` | List articles (with pagination and tag filter) | No |
| GET | `/api/articles/:id` | Get single article | No |
| POST | `/api/articles` | Create new article | Yes |
| PUT | `/api/articles/:id` | Update article | Yes |
| DELETE | `/api/articles/:id` | Delete article | Yes |
| GET | `/api/tags` | Get all unique tags | No |

## Admin Credentials

- **Username**: admin
- **Password**: admin123

## Configuration

### Backend

- Server port: `3001` (configurable via `PORT` environment variable)
- JWT secret: `blog-platform-secret-key` (hardcoded in middleware/auth.js)
- Database file: `backend/data/blog.db` (created on startup; directory is checked for write access first)
- Schema only: `node db/init.js`; seed data: `npm run seed` (add `-- --reset` to rebuild articles)

### Frontend

- Dev server port: `5173` (configurable via `FRONTEND_PORT`)
- API proxy: `/api` requests are proxied to `http://localhost:$PORT` (default `http://localhost:3001`) in both `vite` dev and `vite preview`

## Build for Production

### Backend

The backend runs directly with Node.js:

```bash
cd backend
npm start
```

### Frontend

Build the frontend for production:

```bash
cd frontend
npm run build
```

The built files will be in `frontend/dist/`

## License

MIT
