# Deployment Best Practices Reference

A concise reference guide for deploying Node.js/Express + React applications.

---

## Table of Contents

1. [Local Development](#1-local-development)
2. [Production Builds](#2-production-builds)
3. [Docker](#3-docker)
4. [Environment Configuration](#4-environment-configuration)
5. [Health Checks](#5-health-checks)
6. [Cloud Platforms](#6-cloud-platforms)
7. [Security](#7-security)

---

## 1. Local Development

### Running Frontend and Backend

**Two Terminal Approach:**

```bash
# Terminal 1: Backend
cd backend
pnpm install
pnpm dev  # Runs on port 3001

# Terminal 2: Frontend
cd frontend
pnpm install
pnpm dev  # Runs on port 5173 (Vite)
```

### Vite Proxy Configuration

Avoid CORS issues by proxying API requests through Vite:

```typescript
// frontend/vite.config.ts
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": {
        target: "http://localhost:3001",
        changeOrigin: true,
      },
    },
  },
})
```

Now frontend code can use relative paths:

```typescript
fetch("/api/health") // Proxied to http://localhost:3001/api/health
```

### Environment Variables

```bash
# backend/.env
PORT=3001
NODE_ENV=development
DATABASE_URL=postgresql://localhost:5432/mydb
CORS_ORIGINS=http://localhost:5173

# frontend/.env
VITE_API_URL=/api
```

---

## 2. Production Builds

### Frontend Build (Vite)

```bash
cd frontend
pnpm build  # Creates dist/ folder
```

**Output:**

```
dist/
├── index.html
├── assets/
│   ├── index-abc123.js
│   └── index-def456.css
```

### Backend Build (TypeScript)

```bash
cd backend
pnpm build  # Compiles to dist/
```

### Serving in Production

**Option 1: Express serves static files**

```typescript
// backend/src/server.ts
import path from "path"
import express from "express"

const app = express()

// API routes
app.use("/api", apiRoutes)

// Serve React static files
const frontendPath = path.join(__dirname, "../../frontend/dist")
app.use(express.static(frontendPath))

// Handle client-side routing
app.get("*", (req, res) => {
  if (!req.path.startsWith("/api")) {
    res.sendFile(path.join(frontendPath, "index.html"))
  }
})
```

---

## 3. Docker

### Backend Dockerfile

```dockerfile
# docker/backend/Dockerfile
FROM node:20-slim AS builder

WORKDIR /app

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Install dependencies
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Build
COPY . .
RUN pnpm build

# Production image
FROM node:20-slim

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-lock.yaml ./

RUN pnpm install --prod --frozen-lockfile

# Non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser
USER appuser

EXPOSE 3001

CMD ["node", "dist/server.js"]
```

### Frontend Dockerfile

```dockerfile
# docker/frontend/Dockerfile
FROM node:20-slim AS builder

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### Docker Compose

```yaml
# docker/docker-compose.yml
version: "3.8"

services:
  backend:
    build:
      context: ../backend
      dockerfile: ../docker/backend/Dockerfile
    ports:
      - "3001:3001"
    environment:
      - NODE_ENV=production
      - PORT=3001
    restart: unless-stopped

  frontend:
    build:
      context: ../frontend
      dockerfile: ../docker/frontend/Dockerfile
    ports:
      - "80:80"
    depends_on:
      - backend
    restart: unless-stopped
```

### Docker Commands

```bash
# Build and run
docker-compose -f docker/docker-compose.yml up --build

# Run in background
docker-compose -f docker/docker-compose.yml up -d

# View logs
docker-compose -f docker/docker-compose.yml logs -f

# Stop
docker-compose -f docker/docker-compose.yml down

# Rebuild single service
docker-compose -f docker/docker-compose.yml up --build backend
```

### .dockerignore

```
node_modules
.git
.env
*.log
coverage
dist
.next
```

---

## 4. Environment Configuration

### 12-Factor App Principles

| Factor          | Application                   |
| --------------- | ----------------------------- |
| Config          | Environment variables         |
| Dependencies    | package.json / pnpm-lock.yaml |
| Processes       | Stateless app                 |
| Port binding    | App binds to PORT env var     |
| Logs            | Stream to stdout              |
| Dev/prod parity | Use Docker                    |

### Configuration Pattern

```typescript
// backend/src/config.ts
export const config = {
  port: parseInt(process.env.PORT || "3001", 10),
  nodeEnv: process.env.NODE_ENV || "development",
  corsOrigins: process.env.CORS_ORIGINS?.split(",") || [
    "http://localhost:5173",
  ],
  databaseUrl: process.env.DATABASE_URL || "",

  isDevelopment: process.env.NODE_ENV === "development",
  isProduction: process.env.NODE_ENV === "production",
}
```

---

## 5. Health Checks

### Basic Health Endpoint

```typescript
// backend/src/routes/health.ts
import { Router } from "express"

const router = Router()

router.get("/health", (req, res) => {
  res.json({ status: "healthy", timestamp: new Date().toISOString() })
})

router.get("/health/ready", async (req, res) => {
  try {
    // Check database connection
    await db.query("SELECT 1")
    res.json({ status: "ready" })
  } catch (error) {
    res.status(503).json({ status: "not ready", error: "Database unavailable" })
  }
})

export default router
```

### Docker Health Check

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3001/api/health || exit 1
```

---

## 6. Cloud Platforms

### Platform Comparison

| Platform             | Pricing     | Best For             |
| -------------------- | ----------- | -------------------- |
| **Google Cloud Run** | Pay per use | Stateless containers |
| **Railway**          | Usage-based | Fast deploys         |
| **Render**           | $7+/mo      | Managed services     |
| **Fly.io**           | $2+/mo      | Global distribution  |
| **DigitalOcean**     | $4+/mo      | VPS control          |

### Google Cloud Run Deployment

```bash
# Build and push image
gcloud builds submit --tag gcr.io/PROJECT_ID/backend

# Deploy
gcloud run deploy backend \
  --image gcr.io/PROJECT_ID/backend \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

### cloudbuild.yaml

```yaml
steps:
  - name: "gcr.io/cloud-builders/docker"
    args:
      [
        "build",
        "-t",
        "gcr.io/$PROJECT_ID/backend",
        "-f",
        "docker/backend/Dockerfile",
        "backend",
      ]
  - name: "gcr.io/cloud-builders/docker"
    args: ["push", "gcr.io/$PROJECT_ID/backend"]
  - name: "gcr.io/google.com/cloudsdktool/cloud-sdk"
    args:
      - "run"
      - "deploy"
      - "backend"
      - "--image=gcr.io/$PROJECT_ID/backend"
      - "--region=us-central1"
      - "--platform=managed"
```

---

## 7. Security

### CORS Configuration

```typescript
import cors from "cors"

app.use(
  cors({
    origin: config.corsOrigins,
    credentials: true,
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  }),
)
```

### Security Headers

```typescript
import helmet from "helmet"

app.use(helmet())
```

### Environment Security

```bash
# Never commit .env files
echo ".env" >> .gitignore
echo ".env.*" >> .gitignore

# Set restrictive permissions
chmod 600 .env
```

### Docker Security

```dockerfile
# Run as non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser
USER appuser

# Use specific versions
FROM node:20.10.0-slim

# Don't store secrets in image
# Use runtime environment variables
```

---

## Quick Reference

### Essential Commands

```bash
# Development
pnpm dev

# Production build
pnpm build

# Docker
docker-compose -f docker/docker-compose.yml up --build
docker-compose -f docker/docker-compose.yml logs -f

# Deployment
gcloud run deploy
```

### Port Reference

| Service         | Default Port |
| --------------- | ------------ |
| Vite dev server | 5173         |
| Express/Node    | 3001         |
| Nginx HTTP      | 80           |
| Nginx HTTPS     | 443          |
| PostgreSQL      | 5432         |

---

## Resources

- [Docker Documentation](https://docs.docker.com/)
- [Google Cloud Run](https://cloud.google.com/run/docs)
- [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices)
- [12-Factor App](https://12factor.net/)
