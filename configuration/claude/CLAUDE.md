# CLAUDE.md

Personal global instructions for Claude Code.

IMPORTANT: This context may or may not be relevant to your tasks. Apply these instructions when they are relevant to the current work.

---

## .NET Development Preferences

### Code Style

- Use file-scoped namespaces where possible
- Prefer `var` for obvious types, explicit types for clarity
- Use expression-bodied members for simple getters/methods
- Follow existing project conventions over general preferences

### Entity Framework Core

- Prefer explicit configuration over conventions
- Use `IEntityTypeConfiguration<T>` for entity configurations
- Always specify column types explicitly (`HasColumnType`)
- Use cascade delete for owned relationships

### Project Structure

- Keep models in dedicated Models projects
- Keep data access in dedicated Data projects
- Configurations go in `Configuration/` subdirectories

---

## General Workflow Preferences

### Before Making Changes

- Read existing code before suggesting modifications
- Understand existing patterns in the codebase
- Ask clarifying questions for ambiguous requirements

### During Implementation

- Use TodoWrite to track multi-step tasks
- Complete one task fully before moving to the next
- Keep changes focused - don't over-engineer

### File Operations

- Prefer editing existing files over creating new ones
- When renaming/moving files, update all references within scope
- Delete obsolete files rather than leaving them

---

## Agent Usage Notes

### research

Use for gathering information on unfamiliar best practices and technologies before starting complex implementation tasks.

### context-manager

Use for projects exceeding 10k tokens or complex multi-agent workflows.

### context-fetcher

Use to retrieve specific sections from documentation without loading entire files.

### test-runner

Use to run tests and analyze failures - it reports but doesn't fix.

### architect

Use for high-level feature planning and task breakdowns.

### code-reviewer

Use for in-depth code reviews and improvement suggestions.

### sdk-research-specialist

Use for researching third-party SDKs and libraries.

---

## Communication Style

- **Never use the em-dash character, U+2014.** Not in chat replies, code, comments, documentation, commit
  messages, or UI copy. Use a plain hyphen `-` instead, or restructure the sentence. (Stated by codepoint
  rather than by example, so this file does not break its own rule.)
- Be direct and concise
- Skip unnecessary validation phrases ("Great question!", "Absolutely!")
- Focus on actionable information
- When presenting options, include trade-offs

---

## Version Control / Git

- Use imperative present tense for commit message subjects (e.g., "Add feature XYZ" not "Added feature XYZ" and not "Adds feature XYZ")
- Use the body of the commit message to explain why a change was made, not just what was changed
- Be consistent with branch naming conventions (e.g., `feature/`, `bugfix/`, `hotfix/`, `refactor/`)
- Use commit message formatting (wrap lines at 72 characters, use bullet points for lists)
- Be explicit about breaking changes in commit messages and PR descriptions
- Be concise in commit messages; avoid unnecessary verbosity

---

## Project-Specific Instructions

For project-specific instructions, create a `CLAUDE.md` file in the project root.
Those instructions will take precedence over these global defaults.
