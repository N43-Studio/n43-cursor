---
name: deployment
description: Provides deployment best practices for Node.js/Express + React applications, covering Docker, environment configuration, health checks, and Google Cloud Run deployment. Use when building Docker images, configuring deployment pipelines, setting up environment variables, or deploying to cloud platforms.
---

# Deployment Best Practices

## Quick Start

### Docker Build Pattern

Both frontend and backend use multi-stage builds:

1. **Builder stage**: Install dependencies, compile TypeScript/build assets
2. **Production stage**: Copy only built artifacts, install prod dependencies, run as non-root user

### Environment Configuration

Follow 12-Factor App principles:

- All config via environment variables
- `PORT`, `NODE_ENV`, `CORS_ORIGINS`, `DATABASE_URL`
- Frontend uses `VITE_` prefix for client-side vars
- Never commit `.env` files

### Health Checks

Every backend must expose:

- `GET /api/health` — basic liveness check
- `GET /api/health/ready` — readiness with dependency checks

### Docker Compose

```bash
# Build and run
docker-compose -f docker/docker-compose.yml up --build

# Run in background
docker-compose -f docker/docker-compose.yml up -d

# View logs
docker-compose -f docker/docker-compose.yml logs -f
```

### Google Cloud Run

```bash
gcloud builds submit --tag gcr.io/PROJECT_ID/backend
gcloud run deploy backend \
  --image gcr.io/PROJECT_ID/backend \
  --platform managed \
  --region us-central1
```

### Security Essentials

- Run containers as non-root user
- Use `helmet()` for security headers
- Configure CORS with explicit origin whitelist
- Use specific Node.js image versions

### Port Reference

| Service         | Default Port |
| --------------- | ------------ |
| Vite dev server | 5173         |
| Express/Node    | 3001         |
| Nginx HTTP      | 80           |
| PostgreSQL      | 5432         |

## Additional Resources

- For complete deployment reference including Dockerfiles, CI/CD, and platform comparisons, see [reference.md](reference.md)
