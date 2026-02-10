# Testing & Logging Best Practices Reference

A concise reference guide for testing strategies and logging patterns in Node.js/TypeScript and React applications.

---

## Table of Contents

**Part 1: Logging**

1. [Logging Principles](#1-logging-principles)
2. [Structured Logging](#2-structured-logging)
3. [Express Middleware](#3-express-middleware)

**Part 2: Testing Strategy**

4. [Testing Pyramid](#4-testing-pyramid)
5. [Unit Testing (Node.js)](#5-unit-testing-nodejs)
6. [Integration Testing (Express)](#6-integration-testing-express)
7. [React Component Testing](#7-react-component-testing)
8. [Test Organization](#8-test-organization)

---

# Part 1: Logging

## 1. Logging Principles

### Log Levels

| Level   | When to Use                          |
| ------- | ------------------------------------ |
| `error` | Errors that need immediate attention |
| `warn`  | Potential issues, deprecated usage   |
| `info`  | High-level application flow          |
| `debug` | Detailed diagnostic information      |

### What to Log

- **DO log**: Request start/end, business events, errors, performance metrics
- **DON'T log**: Sensitive data (passwords, tokens), high-frequency debug in production

---

## 2. Structured Logging

### Basic Setup with pino

```typescript
// src/utils/logger.ts
import pino from "pino"

export const logger = pino({
  level: process.env.LOG_LEVEL || "info",
  transport:
    process.env.NODE_ENV === "development"
      ? { target: "pino-pretty" }
      : undefined,
})
```

### Usage

```typescript
import { logger } from "./utils/logger"

// Simple message
logger.info("Server started")

// With context
logger.info({ port: 3000, env: "production" }, "Server started")

// Error logging
try {
  await riskyOperation()
} catch (error) {
  logger.error({ error, context: "riskyOperation" }, "Operation failed")
}
```

---

## 3. Express Middleware

### Request Logging

```typescript
// src/middleware/logger.ts
import { NextFunction, Request, Response } from "express"
import { v4 as uuid } from "uuid"

import { logger } from "../utils/logger"

export function requestLogger(req: Request, res: Response, next: NextFunction) {
  const requestId = (req.headers["x-request-id"] as string) || uuid()
  const startTime = Date.now()

  // Attach to request for use in handlers
  req.requestId = requestId

  res.on("finish", () => {
    const duration = Date.now() - startTime
    logger.info(
      {
        requestId,
        method: req.method,
        path: req.path,
        statusCode: res.statusCode,
        duration,
      },
      "Request completed",
    )
  })

  next()
}
```

### Error Logging

```typescript
// src/middleware/errorHandler.ts
import { NextFunction, Request, Response } from "express"

import { logger } from "../utils/logger"

export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction,
) {
  logger.error(
    {
      error: err.message,
      stack: err.stack,
      requestId: req.requestId,
      path: req.path,
    },
    "Unhandled error",
  )

  res.status(500).json({ error: "Internal server error" })
}
```

---

# Part 2: Testing Strategy

## 4. Testing Pyramid

### Distribution

| Layer       | Percentage | Speed   | Scope                 |
| ----------- | ---------- | ------- | --------------------- |
| Unit        | 70%        | ms      | Single function/class |
| Integration | 20%        | seconds | Multiple components   |
| E2E         | 10%        | minutes | Full system           |

### What Belongs Where

**Unit Tests:**

- Pure functions (utilities, transformations)
- Validators
- Business logic with mocked dependencies

**Integration Tests:**

- API endpoints
- Database operations
- Service layer with real dependencies

**E2E Tests:**

- Critical user journeys only
- Full frontend + backend interaction

---

## 5. Unit Testing (Node.js)

### Structure with Vitest

```typescript
// src/utils/__tests__/formatDate.test.ts
import { describe, expect, it } from "vitest"

import { calculateDuration, formatDate } from "../formatDate"

describe("formatDate", () => {
  it("formats ISO date to readable string", () => {
    const result = formatDate("2025-01-22T10:00:00Z")
    expect(result).toBe("January 22, 2025")
  })

  it("returns empty string for invalid date", () => {
    const result = formatDate("invalid")
    expect(result).toBe("")
  })
})

describe("calculateDuration", () => {
  it("returns duration in milliseconds", () => {
    const start = new Date("2025-01-22T10:00:00Z")
    const end = new Date("2025-01-22T10:05:00Z")
    expect(calculateDuration(start, end)).toBe(300000)
  })
})
```

### Mocking

```typescript
import { beforeEach, describe, expect, it, vi } from "vitest"

import { DataService } from "../services/dataService"

describe("DataService", () => {
  const mockRepository = {
    findById: vi.fn(),
    save: vi.fn(),
  }

  beforeEach(() => {
    vi.clearAllMocks()
  })

  it("returns data from repository", async () => {
    mockRepository.findById.mockResolvedValue({ id: 1, name: "Test" })

    const service = new DataService(mockRepository)
    const result = await service.getData(1)

    expect(mockRepository.findById).toHaveBeenCalledWith(1)
    expect(result.name).toBe("Test")
  })
})
```

---

## 6. Integration Testing (Express)

### Test Setup

```typescript
// tests/setup.ts
import { afterAll, beforeAll } from "vitest"

import { app } from "../src/server"

let server: any

beforeAll(() => {
  server = app.listen(0) // Random port for testing
})

afterAll(() => {
  server.close()
})

export { server }
```

### API Tests with Supertest

```typescript
// tests/integration/api.test.ts
import request from "supertest"
import { describe, expect, it } from "vitest"

import { app } from "../../src/server"

describe("GET /api/health", () => {
  it("returns healthy status", async () => {
    const response = await request(app).get("/api/health")

    expect(response.status).toBe(200)
    expect(response.body).toEqual({ status: "healthy" })
  })
})

describe("POST /api/data", () => {
  it("creates new data entry", async () => {
    const response = await request(app)
      .post("/api/data")
      .send({ name: "Test", value: 123 })
      .set("Content-Type", "application/json")

    expect(response.status).toBe(201)
    expect(response.body).toHaveProperty("id")
    expect(response.body.name).toBe("Test")
  })

  it("returns 400 for invalid data", async () => {
    const response = await request(app)
      .post("/api/data")
      .send({}) // Missing required fields
      .set("Content-Type", "application/json")

    expect(response.status).toBe(400)
  })
})
```

---

## 7. React Component Testing

### Setup with Vitest

```typescript
// src/test/setup.ts
import "@testing-library/jest-dom"

// vite.config.ts
export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
  },
})
```

### Component Tests

```typescript
// src/components/__tests__/Button.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Button } from '../Button';

describe('Button', () => {
  it('renders children', () => {
    render(<Button>Click me</Button>);
    expect(screen.getByText('Click me')).toBeInTheDocument();
  });

  it('calls onClick when clicked', async () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Click</Button>);

    await userEvent.click(screen.getByRole('button'));

    expect(onClick).toHaveBeenCalledOnce();
  });

  it('is disabled when disabled prop is true', () => {
    render(<Button disabled>Click</Button>);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
```

### Testing with Providers

```typescript
// src/test/utils.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter } from 'react-router-dom';
import { render } from '@testing-library/react';

export function renderWithProviders(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
    },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        {ui}
      </BrowserRouter>
    </QueryClientProvider>
  );
}
```

### Query Priority (Use in Order)

1. `getByRole` - Accessible name (best)
2. `getByLabelText` - Form labels
3. `getByText` - Text content
4. `getByTestId` - Last resort

```typescript
// Preferred
screen.getByRole("button", { name: /submit/i })
screen.getByLabelText("Email")

// Avoid unless necessary
screen.getByTestId("submit-button")
```

---

## 8. Test Organization

### Directory Structure

```
backend/
├── src/
│   ├── utils/
│   │   ├── formatDate.ts
│   │   └── __tests__/
│   │       └── formatDate.test.ts
│   └── routes/
│       └── health.ts
└── tests/
    ├── setup.ts
    └── integration/
        └── api.test.ts

frontend/
└── src/
    ├── components/
    │   ├── Button.tsx
    │   └── __tests__/
    │       └── Button.test.tsx
    └── test/
        ├── setup.ts
        └── utils.tsx
```

### Running Tests

```bash
# Backend
cd backend && pnpm test              # All tests
cd backend && pnpm test:watch        # Watch mode
cd backend && pnpm test:coverage     # With coverage

# Frontend
cd frontend && pnpm test             # All tests
cd frontend && pnpm test:watch       # Watch mode
cd frontend && pnpm test:coverage    # With coverage
```

### Coverage Configuration

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
      exclude: ["**/*.test.ts", "**/test/**"],
      thresholds: {
        statements: 80,
        branches: 80,
        functions: 80,
        lines: 80,
      },
    },
  },
})
```

---

## Quick Reference

### Test Commands

```bash
# All tests
pnpm test

# Watch mode
pnpm test:watch

# Coverage
pnpm test:coverage

# Single file
pnpm test src/utils/__tests__/formatDate.test.ts

# Pattern matching
pnpm test -t "formatDate"
```

### Assertion Cheatsheet

```typescript
// Vitest/Jest
expect(result).toBe(expected)
expect(result).toEqual({ key: "value" })
expect(result).toBeTruthy()
expect(result).toContain("text")
expect(mockFn).toHaveBeenCalledWith(arg)
expect(() => fn()).toThrow()
```

```typescript
// React Testing Library
expect(element).toBeInTheDocument()
expect(element).toBeVisible()
expect(element).toHaveTextContent("text")
expect(element).toBeDisabled()
expect(element).toHaveClass("active")
```

---

## Resources

- [Vitest Documentation](https://vitest.dev/)
- [Testing Library](https://testing-library.com/)
- [pino Logger](https://github.com/pinojs/pino)
- [Supertest](https://github.com/visionmedia/supertest)
