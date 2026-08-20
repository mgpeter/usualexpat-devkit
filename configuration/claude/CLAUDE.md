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
- Prefer British spelling in prose: organisation, authorisation, finalise, colour

### Writing that reads as machine-written

Applies to chat, commit messages, PR descriptions, code comments and docs:

- Two balanced clauses joined by a comma, or a metaphor standing in for a noun
- A paragraph per decision, each defending a choice nobody questioned
- Restating the previous sentence in a different register
- "Deliberately", "precisely", "exactly this", "which is the point", "not X, but Y"
- Closing flourishes in commits and PR descriptions: test counts, "verified in the browser",
  "N tests pass, up from M"
- Bold applied to whole sentences rather than to the term being defined

---

## Version Control / Git

These match `.cursor/rules/git-commits.mdc` in the desktop-companion repo, which is the
authoritative statement of the preference. Where a repo has its own commit rule file, it wins.

### Commit subjects

A factual label naming what changed. Name the artifacts - components, technologies, files -
not the effect on the product's story.

- Imperative mood: "Add health check", not "Added", "Adds" or "Adding"
- Capital first letter, no full stop at the end
- 72 characters is the hard limit; in personal repos most land near 30
- Never use Conventional Commits types (`feat:`, `fix:`, `chore:`)
- Ordinary verbs, roughly in order of use: Update, Add, Fix, Remove, Cleanup, Implement,
  Refactor, Move, Wire up, Setup, Migrate, Bump, Prepare, Improve, Handle, Allow, Optimize
- Common patterns: `Add [feature]`, `Fix [issue]`, `Refactor [component]`,
  `Optimize [component]`, `Update [docs]`
- Joining two changes with "and" is fine when they shipped as one unit of work
- No metaphor, no wordplay, no two balanced clauses joined by a comma. If the subject would
  work as a magazine headline or a chapter title, rewrite it

Good, all real:

    Add Blazor app to Aspire app host
    Wire up Angular app with Aspire
    Fix camera-microphone conflicts
    Implement voice recognition and text-to-speech
    Update git config to use nvim
    Remove OpenAI from Powershell config as it was taking too long

Bad, all real and all machine-written:

    Put a YARP gateway in front, and Aspire behind the dev loop
      metaphor and parallel clauses, and it names no artifact
    Let the market be restocked for stamina, at a steepening price
      narrates the product fiction instead of the code
    Turn overdue tasks into contracts worth hunting
      same, and "worth hunting" is editorialising
    Adds Liss aerial reel and updates projects
      third-person "Adds" instead of imperative "Add"

### Repos that prefix the ticket

Work repos put the work item first. Match the surrounding history exactly:

    <Type> #<id> - <Area>: <Imperative sentence>

    Story #35601 - API: Add /v2/api/organisations/{id}/logo endpoint
    Fix #57203 - Dependencies: Align NuGet versions and resolve dependency conflicts

Types in use: `Story`, `DevTask`, `Hotfix`, `Fix`, `Feature`, `Task`, `INFRA`. Areas:
`API`, `WEB`, `SDK`, `Auth`, `Docs`, `INFRA`, and pairs like `API & WEB`. The ticket is
always a prefix, never a suffix, and these subjects routinely run past 72 characters.

### Commit bodies

- Default to none. Most commits are subject-only, and that is correct
- Add one only when the diff leaves a real question: why, a rejected alternative, a breaking
  change, or a manual step someone has to take
- Hyphen bullets, not paragraphs. Three to eight lines is the normal shape
- Blank line after the subject, wrap at 72 characters
- Explain what and why, never how
- Do not narrate the work, walk the diff file by file, justify every choice, or sign off with
  test counts and verification runs
- Breaking changes start a body line with `BREAKING CHANGE:`, in commits and PR descriptions

### Existing project conventions

- Match the surrounding history when people wrote it, including the ticket prefix above
- Do not match it when it is machine-written. Essayistic bodies and literary subjects are a
  symptom, not a house style, and copying them compounds the problem. These rules win

### Everything else

- Branch naming prefixes: `feature/`, `bugfix/`, `hotfix/`, `refactor/`
- Do not add CLAUDE attribution nor claude session links in commit messages

---

## Project-Specific Instructions

For project-specific instructions, create a `CLAUDE.md` file in the project root.
Those instructions will take precedence over these global defaults.
