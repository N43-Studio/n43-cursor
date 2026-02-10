---
name: testing-logging
description: Provides testing strategies and logging patterns for Node.js/TypeScript and React applications, covering structured logging with pino, unit/integration testing with Vitest, and React component testing with Testing Library. Use when writing tests, setting up logging, or establishing testing patterns.
---

# Testing & Logging Best Practices

## Quick Start

### Structured Logging (pino)

```typescript
import pino from "pino"

export const logger = pino({
  level: process.env.LOG_LEVEL || "info",
  transport:
    process.env.NODE_ENV === "development"
      ? { target: "pino-pretty" }
      : undefined,
})

// Usage
logger.info({ port: 3000, env: "production" }, "Server started")
logger.error({ error, context: "riskyOperation" }, "Operation failed")
```

### Log Levels

| Level   | When to Use                        |
| ------- | ---------------------------------- |
| `error` | Errors needing immediate attention |
| `warn`  | Potential issues, deprecated usage |
| `info`  | High-level application flow        |
| `debug` | Detailed diagnostic information    |

### Testing Pyramid

| Layer             | Percentage | What to Test                               |
| ----------------- | ---------- | ------------------------------------------ |
| Unit (70%)        | ms         | Pure functions, validators, business logic |
| Integration (20%) | seconds    | API endpoints, database ops, service layer |
| E2E (10%)         | minutes    | Critical user journeys only                |

### Unit Tests (Vitest)

```typescript
import { describe, expect, it } from "vitest"

describe("formatDate", () => {
  it("formats ISO date to readable string", () => {
    expect(formatDate("2025-01-22T10:00:00Z")).toBe("January 22, 2025")
  })
})
```

### React Component Tests

```tsx
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"

it("calls onClick when clicked", async () => {
  const onClick = vi.fn()
  render(<Button onClick={onClick}>Click</Button>)
  await userEvent.click(screen.getByRole("button"))
  expect(onClick).toHaveBeenCalledOnce()
})
```

### Query Priority (prefer top)

1. `getByRole` — Accessible name (best)
2. `getByLabelText` — Form labels
3. `getByText` — Text content
4. `getByTestId` — Last resort

### Test Commands

```bash
pnpm test              # All tests
pnpm test:watch        # Watch mode
pnpm test:coverage     # With coverage
```

## Additional Resources

- For complete patterns including mocking, integration tests, providers, and coverage config, see [reference.md](reference.md)
