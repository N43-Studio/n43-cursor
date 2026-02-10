# React Frontend Best Practices Reference

A concise reference guide for building modern React applications with TypeScript and Tailwind CSS.

---

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [Component Design](#2-component-design)
3. [State Management](#3-state-management)
4. [Data Fetching](#4-data-fetching)
5. [Forms & Validation](#5-forms--validation)
6. [Styling with Tailwind](#6-styling-with-tailwind)
7. [Performance](#7-performance)
8. [Hooks Patterns](#8-hooks-patterns)
9. [Routing](#9-routing)
10. [Error Handling](#10-error-handling)
11. [Testing](#11-testing)
12. [Accessibility](#12-accessibility)

---

## 1. Project Structure

### Feature-Based Structure (Recommended)

```
src/
├── features/
│   ├── dashboard/
│   │   ├── components/
│   │   │   ├── DashboardCard.tsx
│   │   │   └── DashboardLayout.tsx
│   │   ├── hooks/
│   │   │   └── useDashboardData.ts
│   │   ├── api/
│   │   │   └── dashboard.ts
│   │   └── index.ts           # Public exports
│   └── settings/
│       ├── components/
│       ├── hooks/
│       └── index.ts
├── components/                 # Shared/common components
│   ├── ui/
│   │   ├── Button.tsx
│   │   ├── Card.tsx
│   │   └── Modal.tsx
│   └── layout/
│       ├── Header.tsx
│       └── Layout.tsx
├── hooks/                      # Shared hooks
│   └── useLocalStorage.ts
├── lib/                        # Utilities
│   ├── api.ts                  # API client
│   └── utils.ts
├── pages/                      # Route pages
│   ├── Dashboard.tsx
│   └── Settings.tsx
├── App.tsx
└── main.tsx
```

### File Naming Conventions

| Type       | Convention              | Example               |
| ---------- | ----------------------- | --------------------- |
| Components | PascalCase              | `DashboardCard.tsx`   |
| Hooks      | camelCase, `use` prefix | `useDashboardData.ts` |
| Utilities  | camelCase               | `formatDate.ts`       |
| Constants  | SCREAMING_SNAKE_CASE    | `API_BASE_URL`        |

---

## 2. Component Design

### Functional Components with TypeScript

```tsx
// Simple component
interface DashboardCardProps {
  title: string
  value: number
  onSelect?: () => void
}

function DashboardCard({ title, value, onSelect }: DashboardCardProps) {
  return (
    <div className="rounded border p-4" onClick={onSelect}>
      <h3>{title}</h3>
      <span>{value}</span>
    </div>
  )
}

// With default props
function DashboardCard({
  title,
  value,
  showTrend = true,
}: DashboardCardProps & { showTrend?: boolean }) {
  // ...
}
```

### Component Composition

```tsx
// Compound components pattern
interface CardProps {
  children: React.ReactNode
  className?: string
}

function Card({ children, className }: CardProps) {
  return <div className={`rounded border ${className}`}>{children}</div>
}

Card.Header = function CardHeader({ children }: { children: React.ReactNode }) {
  return <div className="border-b p-4 font-bold">{children}</div>
}

Card.Body = function CardBody({ children }: { children: React.ReactNode }) {
  return <div className="p-4">{children}</div>
}

// Usage
;<Card>
  <Card.Header>Details</Card.Header>
  <Card.Body>Content here</Card.Body>
</Card>
```

---

## 3. State Management

### When to Use What

| State Type        | Solution                    |
| ----------------- | --------------------------- |
| Server/async data | TanStack Query              |
| Form state        | react-hook-form or useState |
| Local UI state    | useState                    |
| Shared UI state   | Context or Zustand          |
| URL state         | React Router                |

### useState Best Practices

```tsx
// Group related state
const [user, setUser] = useState({ name: "", email: "" })

// Functional updates for state based on previous value
setCount((prev) => prev + 1)

// Initialize expensive state lazily
const [data, setData] = useState(() => expensiveComputation())
```

### Context API

```tsx
// Create context
const AppContext = createContext<AppContextType | null>(null)

// Provider component
function AppProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<AppState>({})

  const value = {
    state,
    updateState: (newState: Partial<AppState>) =>
      setState((prev) => ({ ...prev, ...newState })),
  }

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>
}

// Custom hook for consuming context
function useAppContext() {
  const context = useContext(AppContext)
  if (!context) {
    throw new Error("useAppContext must be used within AppProvider")
  }
  return context
}
```

---

## 4. Data Fetching

### TanStack Query Setup

```tsx
// main.tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      retry: 1,
    },
  },
})

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Router />
    </QueryClientProvider>
  )
}
```

### Basic Query

```tsx
// hooks/useData.ts
import { useQuery } from "@tanstack/react-query"

import { fetchData } from "../api/data"

export function useData() {
  return useQuery({
    queryKey: ["data"],
    queryFn: fetchData,
  })
}

// Usage in component
function DataList() {
  const { data, isLoading, error } = useData()

  if (isLoading) return <Spinner />
  if (error) return <Error message={error.message} />

  return (
    <ul>
      {data.map((item) => (
        <DataItem key={item.id} item={item} />
      ))}
    </ul>
  )
}
```

### Mutations

```tsx
import { useMutation, useQueryClient } from "@tanstack/react-query"

export function useCreateItem() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: createItem,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["items"] })
    },
  })
}

// Usage
function CreateButton() {
  const { mutate, isPending } = useCreateItem()

  return (
    <button onClick={() => mutate(newItem)} disabled={isPending}>
      {isPending ? "Creating..." : "Create"}
    </button>
  )
}
```

---

## 5. Forms & Validation

### React Hook Form with Zod

```tsx
import { zodResolver } from "@hookform/resolvers/zod"
import { useForm } from "react-hook-form"
import { z } from "zod"

const schema = z.object({
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email"),
})

type FormData = z.infer<typeof schema>

function Form() {
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<FormData>({
    resolver: zodResolver(schema),
  })

  const onSubmit = (data: FormData) => {
    console.log(data)
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register("name")} placeholder="Name" />
      {errors.name && <span>{errors.name.message}</span>}

      <input {...register("email")} placeholder="Email" />
      {errors.email && <span>{errors.email.message}</span>}

      <button type="submit">Submit</button>
    </form>
  )
}
```

---

## 6. Styling with Tailwind

### Common Patterns

```tsx
// Conditional classes
<div className={`p-4 ${isActive ? 'bg-blue-500' : 'bg-gray-200'}`}>

// With clsx/cn utility
import { cn } from '@/lib/utils';

<div className={cn(
  'p-4 rounded',
  isActive && 'bg-blue-500',
  disabled && 'opacity-50 cursor-not-allowed'
)}>
```

### Component Variants

```tsx
const buttonVariants = {
  primary: "bg-blue-500 text-white hover:bg-blue-600",
  secondary: "bg-gray-200 text-gray-800 hover:bg-gray-300",
  danger: "bg-red-500 text-white hover:bg-red-600",
}

interface ButtonProps {
  variant?: keyof typeof buttonVariants
  children: React.ReactNode
}

function Button({ variant = "primary", children }: ButtonProps) {
  return (
    <button className={`rounded px-4 py-2 ${buttonVariants[variant]}`}>
      {children}
    </button>
  )
}
```

---

## 7. Performance

### Memoization

```tsx
// Memoize expensive computations
const sortedItems = useMemo(() => {
  return items.sort((a, b) => a.name.localeCompare(b.name))
}, [items])

// Memoize callbacks passed to children
const handleClick = useCallback((id: string) => {
  setSelected(id)
}, [])

// Memoize components
const MemoizedChild = memo(function Child({ data }: Props) {
  return <div>{data}</div>
})
```

### When NOT to Memoize

- Simple components that render quickly
- Props that change on every render anyway
- Premature optimization (measure first!)

---

## 8. Hooks Patterns

### Custom Hook Pattern

```tsx
function useToggle(initialValue = false): [boolean, () => void] {
  const [value, setValue] = useState(initialValue)
  const toggle = useCallback(() => setValue((v) => !v), [])
  return [value, toggle]
}

// Usage
const [isOpen, toggleOpen] = useToggle()
```

### useEffect Pitfalls

```tsx
// BAD: Missing dependency
useEffect(() => {
  fetchData(userId)
}, []) // userId not in deps - stale closure

// GOOD: Include all dependencies
useEffect(() => {
  fetchData(userId)
}, [userId])
```

---

## 9. Routing

### React Router v6 Setup

```tsx
import { BrowserRouter, Route, Routes } from "react-router-dom"

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Layout />}>
          <Route index element={<Dashboard />} />
          <Route path="settings" element={<Settings />} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
```

### Route Parameters

```tsx
import { useNavigate, useParams } from "react-router-dom"

function ItemDetail() {
  const { itemId } = useParams()
  const navigate = useNavigate()

  return (
    <div>
      <button onClick={() => navigate("/")}>Back</button>
      <h1>Item {itemId}</h1>
    </div>
  )
}
```

---

## 10. Error Handling

### Error Boundaries

```tsx
import { Component, ErrorInfo, ReactNode } from "react"

interface Props {
  children: ReactNode
  fallback?: ReactNode
}

interface State {
  hasError: boolean
}

class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false }

  static getDerivedStateFromError(): State {
    return { hasError: true }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("Error caught:", error, errorInfo)
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || <div>Something went wrong</div>
    }
    return this.props.children
  }
}

// Usage
;<ErrorBoundary fallback={<ErrorPage />}>
  <App />
</ErrorBoundary>
```

---

## 11. Testing

### Component Testing

```tsx
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"

describe("Button", () => {
  it("renders text", () => {
    render(<Button>Click me</Button>)
    expect(screen.getByText("Click me")).toBeInTheDocument()
  })

  it("calls onClick when clicked", async () => {
    const onClick = vi.fn()
    render(<Button onClick={onClick}>Click</Button>)

    await userEvent.click(screen.getByRole("button"))

    expect(onClick).toHaveBeenCalledOnce()
  })
})
```

---

## 12. Accessibility

### Semantic HTML

```tsx
// Use semantic elements
<header>...</header>
<nav>...</nav>
<main>...</main>
<article>...</article>
<footer>...</footer>

// Use headings properly (h1 > h2 > h3)
<h1>Dashboard</h1>
<section>
  <h2>Overview</h2>
</section>
```

### ARIA Attributes

```tsx
// Labels
<button aria-label="Close modal">×</button>

// States
<button aria-pressed={isCompleted}>Complete</button>
<button aria-expanded={isOpen}>Menu</button>

// Roles
<div role="alert">{errorMessage}</div>
```

---

## Quick Reference

### Common Imports

```tsx
// React
import {
  createContext,
  memo,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import { zodResolver } from "@hookform/resolvers/zod"
// TanStack Query
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
// Form
import { useForm } from "react-hook-form"
// React Router
import {
  BrowserRouter,
  Link,
  Route,
  Routes,
  useNavigate,
  useParams,
} from "react-router-dom"
import { z } from "zod"
```

---

## Resources

- [React Documentation](https://react.dev/)
- [TanStack Query](https://tanstack.com/query/latest)
- [React Router](https://reactrouter.com/)
- [Tailwind CSS](https://tailwindcss.com/)
- [React Hook Form](https://react-hook-form.com/)
