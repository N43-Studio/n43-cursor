> **Recommended Model**: Tier 3 - Fast (Gemini 3 Flash)

<!-- **Why**: Procedural command execution and result reporting -->

# Validate

Run comprehensive validation of the project.

## Discovery

First, check `project-context.mdc` for project-specific validation commands. If not defined, look for validation scripts in `package.json` at the project root and in subdirectories (frontend/, backend/, etc.).

## Default Validation Commands

If no project-specific commands are defined, run these standard commands:

### 1. Linting

```bash
# Root level:
pnpm lint

# Or per directory if monorepo:
cd frontend && pnpm lint
cd backend && pnpm lint
```

**Expected:** No linting errors

### 2. Type Checking

```bash
# Root level:
pnpm typecheck

# Or per directory if monorepo:
cd frontend && pnpm typecheck
cd backend && pnpm typecheck
```

**Expected:** No type errors

### 3. Unit Tests

```bash
# Root level:
pnpm test

# Or per directory if monorepo:
cd frontend && pnpm test
cd backend && pnpm test
```

**Expected:** All tests pass

### 4. Test Coverage (if available)

```bash
pnpm test:coverage
```

**Expected:** Coverage meets project threshold

### 5. Build

```bash
# Root level:
pnpm build

# Or per directory if monorepo:
cd frontend && pnpm build
cd backend && pnpm build
```

**Expected:** Build completes successfully

### 6. Format Check (optional)

```bash
pnpm format:check
```

**Expected:** All files properly formatted

### 7. Docker Build (optional)

If Docker configuration exists:

```bash
docker compose -f docker/docker-compose.yml build
```

**Expected:** Containers build successfully

## Summary Report

After all validations complete, provide a summary report:

### Validation Results

| Check         | Status | Notes              |
| ------------- | ------ | ------------------ |
| Linting       | ✅/❌  |                    |
| Type Checking | ✅/❌  |                    |
| Unit Tests    | ✅/❌  | X passed, Y failed |
| Coverage      | ✅/❌  | X%                 |
| Build         | ✅/❌  |                    |
| Docker        | ✅/❌  | (if run)           |

### Errors & Warnings

<List any errors or warnings encountered>

### Recommendations

<Suggestions for fixing any issues>

### Overall Health

**Status**: PASS / FAIL

<Brief assessment of project health>

## Notes

- If a command is not available (e.g., no test script), note it and continue
- If a step fails, continue with remaining steps to get full picture
- Focus on actionable issues that block deployment
- Distinguish between blocking errors and non-blocking warnings
