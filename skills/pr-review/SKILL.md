---
name: pr-review
description: Provides PR code review conventions including severity levels, feedback types, review language guidelines, and best practices for constructive feedback. Use when conducting code reviews, writing review comments, or refining review documents.
---

# PR Review Conventions

## Quick Start

### Severity Levels

| Severity     | Description                                                  | Blocking |
| ------------ | ------------------------------------------------------------ | -------- |
| `major`      | Must be addressed before merging to production               | Yes      |
| `minor`      | Non-blocking if merged, but should be addressed in follow-up | No       |
| `suggestion` | Loose opinion — an idea the author can freely ignore         | No       |
| `nit`        | Strong but unimportant opinion — stylistic preference        | No       |

### Feedback Types

| Type       | Description                                 | Guidelines                                                        |
| ---------- | ------------------------------------------- | ----------------------------------------------------------------- |
| `question` | Needs clarification from author             | Use when intent is unclear or design decision needs explanation   |
| `praise`   | Pattern or technique deserving appreciation | Include only 2-3 per review — highlight genuinely impressive work |

### Nit vs Suggestion

- **Nit**: "I feel strongly about this, but it doesn't really matter" (naming, formatting preferences)
- **Suggestion**: "Here's an idea you could consider" (alternative approach, optional optimization)

### Review Language

- Use "we", "I", or "the code" instead of "you"
- Be specific in suggestions — include file paths and line numbers
- Provide actionable feedback with code examples when possible
- Prioritize: major items first, nits last

### Praise Budget

Reviews should have **2-3 praise items maximum**. Recognize genuinely impressive patterns, elegant solutions, or good architectural decisions. Don't overuse.

### Review Checklist

Before finalizing any review, verify coverage of:

- [ ] Code correctness and logic
- [ ] Error handling
- [ ] Type safety
- [ ] Security implications
- [ ] Performance considerations
- [ ] Test coverage
- [ ] Documentation needs
- [ ] Conventional commit compliance

### Verdict Criteria

| Condition                          | Verdict                     |
| ---------------------------------- | --------------------------- |
| Any major issues remain            | CHANGES REQUESTED           |
| Unanswered questions remain        | NEEDS DISCUSSION            |
| Only minor/suggestion/nit          | APPROVED (with suggestions) |
| All items addressed or only praise | APPROVED                    |

## Additional Resources

- For full review process, report template, and examples, see [conventions.md](conventions.md)
- For the complete review command, see `.cursor/commands/code-review/review-pr.md`
- For interactive review refinement, see `.cursor/commands/code-review/interactive-review.md`
