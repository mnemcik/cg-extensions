# Spec-Driven Development with AI

A reusable methodology for building software from scratch using
AI-assisted spec authoring followed by AI-driven implementation.

> Shipped by the [`spec-driven`](https://github.com/mnemcik/cg-extensions/tree/main/spec-driven) Consigliere extension. Edit the source there, not this copy — `cg extension update spec-driven` overwrites it.

---

## Core Principles

These four rules govern every interaction between the human and the AI
throughout both phases. They belong in the project's `CLAUDE.md` (or
equivalent AI instruction file) so they are loaded into every session.

> **1. Don't assume. Don't hide confusion. Surface tradeoffs.**
>
> When a requirement is ambiguous, ask — don't guess. When two specs
> conflict, flag it. When a decision has meaningful tradeoffs (cost vs
> complexity, speed vs correctness, now vs later), present the options
> with pros/cons and let the human choose. Silent assumptions become
> silent bugs.

> **2. Minimum code that solves the problem. Nothing speculative.**
>
> Implement exactly what the spec requires. No extra features, no
> premature abstractions, no "while we're here" refactors. If a future
> need isn't in the PRD, it doesn't exist yet. Three lines of
> straightforward code are better than a clever abstraction that
> anticipates requirements nobody asked for.

> **3. Touch only what you must. Clean up only your own mess.**
>
> Don't reformat files you didn't change. Don't add docstrings to code
> you didn't write. Don't refactor adjacent code that happens to be
> nearby. If you introduced a problem, fix it. If it was already there,
> leave it unless explicitly asked.

> **4. Define success criteria. Loop until verified.**
>
> Before starting a task, know what "done" looks like — a passing test,
> a build with zero warnings, a spec-gate script that exits clean.
> After completing the task, verify it meets those criteria. If it
> doesn't, fix it before moving on. Never declare a milestone complete
> with failing checks.

These principles apply equally during spec authoring (don't assume the
user wants a message queue — ask; don't spec features not in the PRD)
and during implementation (don't refactor the auth layer while fixing a
CSS bug; verify the build after every change).

---

## Overview

The workflow has three phases:

1. **PRD authoring** — Human describes the idea; AI interviews,
   structures, and drafts the PRD. Human reviews, corrects, and
   approves. The result is a complete PRD.md.
2. **Spec authoring** — AI expands the approved PRD into a layered
   specification tree that is machine-verifiable and serves as the
   single source of truth for implementation.
3. **Implementation** — AI implements against the specs in milestone
   batches, using the spec tree as acceptance criteria. Specs gate CI;
   code that violates a spec fails the build.

The key insight: **specs are cheaper to review than code**. A human can
validate a 200-line API contract in minutes. Reviewing 2,000 lines of
generated code takes hours. By front-loading decisions into the PRD and
specs — both co-authored with the AI — the human stays in control of
*what* while the AI handles *how*.

---

## Phase 1: PRD Authoring

The PRD is co-authored by the human and the AI. The human brings domain
knowledge, constraints, and opinions. The AI structures, asks probing
questions, identifies gaps, and drafts the document. The human reviews,
corrects, and approves. The result is a `PRD.md` file in the repo root.

### How it works

1. **Human provides the seed.** This can be anything from a single
   paragraph to a detailed brief. The less you provide, the more the
   AI will need to interview you — but even a few sentences about the
   problem and the users is enough to start.

2. **AI interviews.** The AI reads the seed and asks clarifying
   questions — grouped, not one at a time. It should surface tradeoffs
   and propose options where your input is vague. Expect 1–3 rounds of
   questions before the AI has enough to draft.

3. **AI drafts the PRD.** The AI writes `PRD.md` with all sections
   populated, flagging any section where it had to make assumptions
   with a `[ASSUMED — please verify]` marker.

4. **Human reviews.** Read the draft. Correct assumptions. Add detail
   the AI couldn't know (internal politics, budget constraints, domain
   nuance). Remove anything that's wrong.

5. **Iterate.** The AI revises based on your corrections. Repeat until
   both sides agree the PRD is complete. Then freeze it — changes after
   this point go through the authority order (update PRD first, then
   cascade to specs).

### Seed prompt

Use this to kick off the PRD authoring session. You can provide as
much or as little detail as you have.

```
I want to build [one-sentence description].

Here's what I know so far:
[Paste whatever you have — a paragraph, bullet points, a slide deck
summary, a conversation transcript, or even just the problem statement.
Don't worry about structure; the AI will organise it.]

Please:
1. Read what I've provided.
2. Ask me all the clarifying questions you need to write a complete
   PRD. Group them by topic. Don't ask one at a time.
3. After I answer, draft a full PRD.md following the section structure
   below. Flag any assumptions with [ASSUMED — please verify].
4. I'll review and correct. We iterate until the PRD is solid.

Ground rules:
- Don't assume. Don't hide confusion. Surface tradeoffs.
- Minimum code that solves the problem. Nothing speculative.
- Touch only what you must. Clean up only your own mess.
- Define success criteria. Loop until verified.
- [Your cost/complexity stance, or "I want this cheap and simple"]
- [Your stack preferences, or "you decide and justify via ADR"]
```

### PRD sections

The AI should produce a PRD with these sections. Not all sections apply
to every project — the AI should include a section only if the project
needs it and note "N/A" for sections that don't apply.

| # | Section | Purpose | What the AI should ask about |
|---|---------|---------|------------------------------|
| 1 | **Problem statement** | What problem does this solve, for whom? | Who is the primary user? What pain are they in today? What does success look like? |
| 2 | **Users & roles** | Who uses it and what can each role do? | How many distinct actors? Which are authenticated? Which have elevated privileges? Are there anonymous/public paths? |
| 3 | **Core features** | Numbered feature list with enough detail to derive entities, endpoints, and processing steps. | For each feature: who initiates it, what data flows, what's the happy path, what are the edge cases? |
| 4 | **Domain rules** | Business logic that is non-obvious. | Are there formulas, state transitions, aggregation rules, ordering constraints, uniqueness rules? What would surprise a new developer? |
| 5 | **Data model sketch** | Entity names, key relationships, and data flow direction. | What are the core nouns? How do they relate? What's the cardinality? Where does data originate? |
| 6 | **External integrations** | Systems the software connects to. | For each: direction (read/write/both), protocol, auth method, required or optional, data volume, rate limits? |
| 7 | **Output & reporting** | What the system produces for human consumption. | What formats? Who sees what? Real-time or scheduled? What tool do consumers use to view it? |
| 8 | **Non-functional requirements** | Performance, cost, security, accessibility, compliance. | Hard numbers: latency budgets, user ceilings, data volumes, processing SLAs, monthly cost targets, compliance regimes? |
| 9 | **Stack preferences** | Languages, frameworks, cloud provider. | Do you have existing investment in a stack? Team expertise? Licensing constraints? Or no preference? |
| 10 | **Hosting & infra constraints** | Deployment model, budget, regions. | Serverless or containers? Managed services or self-hosted? What will you NOT pay for? Any compliance zones? |
| 11 | **Auth model** | Who authenticates how? | Identity provider, token format, service-to-service auth, anonymous paths, multi-tenancy? |
| 12 | **Open questions** | Things neither side has decided. | The AI should also contribute its own open questions here — things it noticed that the human hasn't addressed. |

### Tips for the human during PRD co-authoring

- **Answer the AI's questions honestly.** If you don't know, say "I
  don't know — propose something." That's better than a vague answer
  the AI will silently interpret.
- **Be opinionated where you have opinions.** The AI will respect
  explicit preferences. It only guesses when you're silent.
- **Be explicit about cost constraints.** AI defaults to
  over-engineering. State your budget and repeat it.
- **Name your external dependencies.** The AI cannot guess what data
  sources, BI tools, or identity providers you use.
- **Include rough numbers.** Expected users, data volumes, request
  rates, computation frequency, report sizes. Order-of-magnitude is
  fine.
- **Don't worry about structure or prose quality.** The AI handles
  that. Focus on getting the right information across.

### Transition to spec authoring

Once the PRD is approved, transition to Phase 2 with:

```
The PRD is approved. Please proceed to spec authoring:
1. Propose which spec authoring steps apply and which to skip.
2. Wait for my approval on the step plan.
3. Then proceed step by step, waiting for my review after each.

Same ground rules as before. Specs are the source of truth from here on.
```

---

## Phase 2: Spec Authoring

After the PRD is agreed, the AI authors specs in the order below. Each
step produces files under `specs/`. The human reviews and approves each
step before the next begins.

**Not every project needs every step.** Before starting, the AI should
propose which steps apply to this specific project and which to skip,
with reasoning. The human approves the plan. The table below marks each
step as **always**, **usually**, or **conditional** to help calibrate.

| Step | Applies | Skip when... |
|------|---------|-------------|
| 1. ADRs | Always | — |
| 2. Domain model | Always | — |
| 3. Domain logic | Usually | Domain is pure CRUD with no non-obvious rules. |
| 4. API contract | Usually | No HTTP/RPC API (e.g., pure CLI, embedded library). |
| 5. Async / real-time | Conditional | No push-based communication, no message queues, no event streaming. |
| 6. Data integration | Conditional | No external data sources, no ETL, no BI output. |
| 7. Behaviour specs | Usually | Libraries or infra-only projects where unit tests suffice. |
| 8. NFRs | Always | — |
| 9. Infrastructure | Usually | No self-managed infra (e.g., PaaS managed by another team). |
| 10. CI pipeline | Usually | Single-developer projects that use manual verification. |
| 11. Codegen | Conditional | No generated code in the project. |

### Step 1: Architecture Decision Records (ADRs)

*Applies: **always.***

**Output:** `specs/adr/NNNN-slug.md`

ADRs capture the irreversible or expensive-to-reverse decisions. The AI
should propose 3–8 ADRs covering the decisions that matter most for the
project. Common topics:

- Stack choice (why this language/framework/database/platform)
- Data storage and processing strategy
- Communication patterns (sync, async, real-time, batch)
- Integration approach for external systems
- Auth architecture
- Deployment model
- Output/reporting strategy (embedded BI vs custom rendering vs export)
- Explicit exclusions ("no X in v1" — with reasoning and revisit criteria)

**Format per ADR:**
```markdown
# ADR NNNN — Title

- **Status:** Proposed | Accepted | Superseded | Deprecated
- **Date:** YYYY-MM-DD

## Context
Why this decision needs to be made.

## Options considered
Table of options with pros/cons/verdict.

## Decision
What we chose and why.

## Consequences
Positive, negative, and "revisit if" conditions.
```

**Review gate:** Human approves each ADR before proceeding. ADRs start
as `Proposed` and flip to `Accepted` on approval.

### Step 2: Domain Model

*Applies: **always.***

**Output:** `specs/domain/entities/*.schema.json`, `specs/domain/entities/common.schema.json`

- One schema file per entity (JSON Schema 2020-12 or equivalent for
  your stack — e.g., Protobuf `.proto`, TypeSpec, Zod schemas, SQL DDL).
- A shared definitions file for primitives (ID formats, enums,
  timestamps, common constraints).
- Valid and invalid example fixtures for each entity.
- An ID format specification if the system uses structured IDs.

For systems with external data sources, also specify:
- **Ingest schemas:** the shape of data as it arrives from external
  systems, before any transformation.
- **Mapping specs:** how external fields map to internal entities
  (field name mapping, type coercion, default values, nullability).

The AI derives entities from PRD sections 3–6. The human validates the
entity list and field names — these propagate into every downstream spec.

### Step 3: Domain Logic Specs

*Applies: **usually.** Skip if the domain is pure CRUD.*

**Output varies by project:**

- **State machines:** Lifecycle state specifications with transition
  tables, guards, side-effects, and illegal-transition contracts. Use a
  machine-readable format (e.g., XState JSON) alongside human-readable
  prose.
- **Computation rules:** Formulas, aggregation logic, scoring
  algorithms, derived metrics. Each rule should include canonical test
  vectors — a table of inputs and expected outputs that both backend
  and any client-side preview must reproduce identically.
- **Transformation pipelines:** For systems that process data through
  multiple stages, specify each stage's input schema, output schema,
  transformation logic, error handling, and idempotency guarantees.
- **Workflow rules:** Multi-step processes with pre/post-conditions.
- **Validation rules:** Cross-field and cross-entity constraints not
  expressible in the schema alone.

Include property test specifications: which invariants should be
verified under random input sequences.

### Step 4: API Contract

*Applies: **usually.** Skip for systems with no HTTP/RPC API.*

**Output:** `specs/api/openapi.yaml` (or GraphQL schema, gRPC `.proto`),
`specs/api/.spectral.yaml`, `specs/api/examples/*.json`

- Full contract for every endpoint: paths, methods, parameters,
  request/response schemas, error codes.
- A linting ruleset to enforce naming conventions and error format.
- Example request/response payloads for every endpoint variant.
- Error format contract.
- Link to the API style guide you're following.

### Step 5: Async / Real-time Contract

*Applies: **conditionally.** Skip for request/response-only systems
with no push-based communication or message queues.*

**Output:** `specs/api/asyncapi.yaml` (or equivalent), event example
payloads.

Needed when the system includes any of:
- WebSocket / SSE push channels
- Message queues or event buses
- Scheduled/triggered background processing
- Event-driven data pipelines

Specify:
- Channel/topic definitions and message schemas.
- Ordering, idempotency, and delivery guarantees.
- Reconnection and replay semantics (for client-facing channels).
- Throttle/debounce contracts for high-frequency events.
- Dead-letter and retry policies (for queue-based systems).

### Step 6: Data Integration & Output Contracts

*Applies: **conditionally.** Skip for self-contained systems with no
external data sources and no exported output.*

**Output:** `specs/integration/` — one spec per external system.

This step covers both sides of the data boundary:

**Inbound (data sources):**
- Connection method (SDK, REST API, ODBC/JDBC, file drop, etc.).
- Authentication and credential management.
- Schema of ingested data (or reference to the external system's docs).
- Refresh cadence: real-time streaming, scheduled pull, or on-demand.
- Error handling: what happens when the source is unavailable or
  returns malformed data.
- Data volume estimates and rate limits.

**Outbound (reports, exports, BI):**
- Output formats: embedded dashboards, exported files (Excel, CSV,
  PDF), push to BI platform, API for external consumers.
- Report/export inventory: list every report or export the system
  produces, with its audience, refresh cadence, and delivery method.
- Schema of exported data — column definitions, aggregation levels,
  filter parameters.
- Semantic model definitions if publishing to a BI platform (measures,
  dimensions, relationships, hierarchies).
- Template specifications for formatted exports (column order, header
  labels, number formatting, sheet structure for multi-sheet exports).

**Both directions:**
- Data lineage: which source fields end up in which output fields,
  through which transformations. Even a simple mapping table prevents
  drift.
- Idempotency: can the same data be ingested or exported twice without
  side effects?

### Step 7: Behaviour Specs (Gherkin)

*Applies: **usually.** Skip for libraries or infrastructure-only
projects where behaviour is better expressed as unit tests.*

**Output:** `specs/features/*.feature`

- One `.feature` file per domain area or user workflow.
- Gherkin scenarios covering happy paths AND error/edge cases.
- A closed tag taxonomy for test matrix selection.
- Traceability: every scenario references its PRD section.

For data-processing systems, include scenarios for:
- End-to-end data flow (source → transform → output).
- Partial failure and recovery.
- Computation correctness with concrete example data.

Gherkin serves dual purpose: it's readable by non-developers AND
directly executable as acceptance tests.

### Step 8: Non-Functional Requirements

*Applies: **always.***

**Output:** `specs/nfr/` — machine-readable where possible, prose where
necessary.

Common NFR files:

| File | Content | When to include |
|------|---------|-----------------|
| `performance.yaml` | Latency budgets, throughput targets, capacity caps, query time SLAs, data freshness targets. | Always. |
| `cost-budget.yaml` | Monthly ceilings by scenario (idle, active, peak). Line-item breakdown by resource. | When the system has its own infrastructure or consumes metered services. |
| `security.md` | Threat model, auth matrix, rate limits, header requirements, input validation rules, secret management, dependency hygiene. | Always. |
| `accessibility.md` | WCAG level target, keyboard navigation, screen reader expectations. | When the system has a user-facing interface. |
| `compliance.md` | Data residency, retention, audit log, regulatory requirements. | When handling personal data, financial data, or operating in regulated industries. |
| `data-quality.md` | Freshness SLAs, completeness thresholds, deduplication rules, reconciliation checks. | When the system ingests, transforms, or publishes data. |

These feed CI gates. A freshness SLA in YAML can be asserted by a
monitoring script; a security header requirement can be checked by a
test.

### Step 9: Infrastructure Contracts

*Applies: **usually.** Skip for projects that don't manage their own
infrastructure.*

**Output:** `specs/infra/resources.md`, `specs/infra/*-contract.md`

- Exhaustive resource list with names, types, SKUs, tags.
- Module/stack boundaries and typed input/output contracts.
- Deployment invariants (assertions verified by dry-run or post-deploy
  check).
- IAM / RBAC assignments.
- Naming conventions and tagging rules.
- Network topology and access rules.

### Step 10: CI Pipeline Spec

*Applies: **usually.***

**Output:** `specs/ci/pipeline.md`, `specs/ci/jobs.md`, `specs/ci/workflows/*.yml`

- Tiered pipeline design: spec gates run first and fast; heavy tests
  and builds depend on them passing.
- Per-job contract: what it runs, what it asserts, when it fails, its
  time budget.
- Draft workflow files in the CI system's format.

### Step 11: Codegen Contracts

*Applies: **conditionally.** Skip if the project has no generated code.*

**Output:** `specs/codegen/README.md`, `specs/codegen/*.md`

- The generation matrix: source artifact → tool → output artifact →
  consuming project.
- Tool configurations.
- Principles: what is generated, what is hand-written, and how to tell
  the difference.

### Final: Spec Navigation Index

**Output:** `specs/README.md`

A single-page index linking every file in the spec tree. Include:

- File table with one-line descriptions.
- The authority order (see below).
- A "how to navigate by task" guide for common developer questions.
- A list of what is NOT in specs (and where to find it instead).
- A note on which optional steps were skipped and why.

---

## Phase 3: Implementation

### Milestone structure

Break implementation into milestones small enough to verify in one
session. Each milestone should produce a working (possibly incomplete)
system that builds and passes all tests.

**Typical milestone pattern:**

| Milestone | Scope |
|-----------|-------|
| **M0: Scaffolding** | Repository layout, build config, dev environment, CI skeleton, IaC skeleton, spec-gate scripts. |
| **M1: Foundation** | Infrastructure modules, domain layer (entities, business logic, computations), auth wiring, core communication layer. |
| **M2: Core features** | Data layer, API handlers or processing pipeline, integration with external systems, integration tests. |
| **M3: User interface** | Frontend pages or dashboards, client-side state management, reporting/export output, container or deployment build. |
| **M4: Hardening** | Security, input validation, error handling, management UI, missing endpoints, performance tuning. |
| **M5: Polish** | Remaining UI features, accessibility, export formatting, remaining CI workflows, documentation. |

Adapt to your project. A backend-only service has no M3 frontend work.
A data pipeline might merge M2 and M3 (data processing IS the core
feature). A library might collapse everything into M0–M2.

### Sub-agent strategy

When using Claude Code (or similar AI coding tools that support
sub-agents), delegate well-bounded tasks to lighter models:

| Task characteristic | Delegation strategy |
|--------------------|--------------------|
| **Typed contract exists** (e.g., IaC module, report template, data mapper with specified I/O) | Delegate to fast/cheap model. Include the contract in the prompt. |
| **Pattern already established** (e.g., "write another component/module/handler like this one") | Delegate to mid-tier model. Reference the existing example. |
| **First of its kind** (e.g., auth middleware, pipeline orchestrator, computation engine) | Do it yourself on the main thread. |
| **Cross-cutting or architectural** (e.g., composing modules, wiring DI, data lineage) | Do it yourself. Sub-agents lack the full context. |

**Rules for sub-agent delegation:**

1. Each sub-agent writes to a distinct file. No two sub-agents touch
   the same file.
2. Include the complete contract (inputs, outputs, invariants) in the
   sub-agent prompt. Don't assume it will read the right spec file.
3. Review every sub-agent's output before wiring it into the system.
4. The briefing cost is real — if explaining the task takes longer than
   doing it, just do it.

### Verification loop

After each milestone, verify:

```
1. Build succeeds with 0 warnings, 0 errors.
2. All tests pass (unit, integration, property).
3. Spec-gate scripts pass (lint specs, validate fixtures, check drift).
4. Manual smoke test (if the milestone includes UI, API, or output changes).
```

Fix failures before starting the next milestone.

---

## Authority Order

When two sources of truth disagree, the higher-authority source wins.
Fix the lower-authority source, not the higher one.

```
 1. PRD.md                    (human intent — highest authority)
 2. specs/adr/*.md            (architectural decisions)
 3. specs/nfr/*               (non-functional constraints)
 4. specs/domain/**           (entities, logic, computations)
 5. specs/api/*               (API contracts)
 6. specs/integration/*       (data integration + output contracts)
 7. specs/infra/**            (infrastructure contracts)
 8. specs/ci/**               (CI/CD pipeline contracts)
 9. specs/codegen/**          (code generation rules)
10. Implementation code       (lowest authority — must conform to above)
```

If implementation code contradicts a spec, **the code is wrong** — fix
the code, not the spec. If the spec itself is wrong, update the spec
first (in the same PR as the code change).

---

## Anti-Patterns

1. **Skipping spec review.** Approving specs without reading them means
   the AI's assumptions become your architecture. Specs are the
   leverage point — spend your review budget here, not on code.

2. **Editing code instead of specs.** If you want to change behaviour,
   change the spec first. The AI will propagate the change to code.
   Editing code directly creates drift that compounds over time.

3. **Over-specifying implementation details.** Specs describe *what*
   and *constraints*, not *how*. Don't put function names, file paths,
   or internal architecture in specs — those are implementation choices
   that should remain flexible.

4. **Massive milestones.** A milestone that touches 50+ files is too
   large to verify. Split it. Each milestone should be reviewable in a
   single focused session.

5. **Ignoring cost constraints.** AI defaults to enterprise-grade
   patterns. State your budget explicitly and repeat it throughout the
   conversation.

6. **Spec sprawl without CI enforcement.** Specs that aren't checked by
   CI drift silently. For every spec file, there should be a
   corresponding gate script in CI. If you can't automate the check,
   the spec is too vague.

7. **Delegating everything to sub-agents.** Sub-agents are effective
   for mechanical, bounded tasks. They fail at cross-cutting concerns,
   novel architecture, and ambiguous requirements. Keep the hard
   decisions on the main thread.

8. **Treating external system contracts as stable.** External APIs,
   data source schemas, and BI platform capabilities change. Pin the
   version you're building against in the integration spec. When the
   external system changes, update the spec first, then propagate.

---

## Prompt Templates

### Starting from scratch (no PRD yet)

Use the seed prompt from Phase 1 (see above). The AI will interview
you and draft the PRD. After the PRD is approved, use the transition
prompt to move into spec authoring.

### Starting with an existing PRD

If you already have a PRD, skip the interview and go straight to spec
authoring:

```
I have a PRD for a new project. It's in PRD.md — please read it.

Proceed to spec authoring:
1. Propose which steps apply and which to skip.
2. Wait for my approval on the step plan.
3. Proceed step by step, waiting for my review after each.
4. After all specs are approved, propose milestones and implement.

Ground rules:
- Don't assume. Don't hide confusion. Surface tradeoffs.
- Minimum code that solves the problem. Nothing speculative.
- Touch only what you must. Clean up only your own mess.
- Define success criteria. Loop until verified.
- [Your cost/complexity stance]
- [Your stack preferences, or "you decide and justify via ADR"]
- Specs are the source of truth.
- Ask before adding complexity I didn't request.
```

### Resuming after a context break

```
Continue where we left off. The specs are in specs/ and the
implementation has reached [describe current state]. The next
milestone is [X]. Please read the task list and pick up the next
pending item.
```

### Delegating a bounded task to a sub-agent

```
Write exactly one file: [absolute file path].
Do not modify any other file.

## Authoritative specs to read first
- [List the 1–3 spec files this task depends on, with paths]

## Contract
[Paste the exact input/output/invariant contract from the spec]

## Hard requirements
[Numbered list of must-haves and must-not-haves]

## Conventions
[File header format, naming rules, coding style notes]

Write the file. Return a short summary listing what you created,
what it contains, and any spec ambiguity you had to resolve (and how).
```

---

## File Tree Template

Adapt to your project. Not every directory is needed. Directories
marked *(optional)* correspond to conditional spec steps.

```
project-root/
├── PRD.md                       ← human-authored input
├── specs/
│   ├── README.md                ← navigation index + authority order
│   ├── adr/
│   │   ├── 0001-*.md
│   │   └── README.md
│   ├── domain/
│   │   ├── entities/
│   │   │   ├── common.schema.*
│   │   │   ├── *.schema.*
│   │   │   └── examples/{valid,invalid}/*
│   │   ├── state-machine.*      ← (optional) lifecycle specs
│   │   └── *.md                 ← business logic / computation specs
│   ├── api/                     ← (optional) API contracts
│   │   ├── openapi.yaml
│   │   ├── asyncapi.yaml        ← (optional) async / real-time
│   │   ├── .spectral.yaml
│   │   └── examples/*
│   ├── integration/             ← (optional) external system contracts
│   │   ├── sources/             ← inbound data specs
│   │   └── outputs/             ← reports, exports, BI specs
│   ├── features/                ← (optional) Gherkin behaviour specs
│   │   └── *.feature
│   ├── nfr/
│   │   ├── performance.yaml
│   │   ├── cost-budget.yaml     ← (optional)
│   │   ├── security.md
│   │   ├── accessibility.md     ← (optional) if UI exists
│   │   ├── compliance.md        ← (optional) if regulated
│   │   └── data-quality.md      ← (optional) if data processing
│   ├── infra/                   ← (optional) IaC contracts
│   │   ├── resources.md
│   │   └── *-contract.md
│   ├── ci/                      ← (optional) CI/CD pipeline specs
│   │   ├── pipeline.md
│   │   ├── jobs.md
│   │   └── workflows/*
│   └── codegen/                 ← (optional) code generation specs
│       └── *.md
├── apps/                        ← application code
├── infra/                       ← IaC implementation
├── tests/
├── scripts/                     ← spec-gate scripts for CI
├── dev/                         ← local development environment
└── .github/workflows/           ← CI/CD
```

---

## Adapting This Methodology

### For smaller projects (CLI tools, libraries, scripts)

Skip steps 5–6 (async, integration), and 11 (codegen). Collapse
milestones into one or two. The PRD can be a single page. You still
benefit from steps 1 (ADRs), 2 (domain model), and 8 (NFRs — even a
CLI has performance budgets).

### For backend-only services (no UI)

Skip accessibility NFRs. Replace E2E browser tests with API contract
tests (consumer-driven contracts, Pact, or Schemathesis).

### For data platforms and analytics systems

Step 6 (data integration & output contracts) is the most important step
after the domain model. Spec every external data source, every
transformation stage, and every report/export. Include:
- Ingest schemas pinned to the external system's version.
- Transformation logic with test vectors (input rows → expected output).
- Semantic model definitions if publishing to a BI platform.
- Export templates for formatted output (column order, headers, number
  formatting, multi-sheet structure).
- Data freshness SLAs in `specs/nfr/data-quality.md`.
- Computation correctness assertions in Gherkin or as property tests.

### For mobile apps

Add a step for the UI/UX contract: screen inventory, navigation flow,
design tokens. Use platform-specific E2E tools instead of browser-based
tests.

### For multi-team projects

Add a `specs/api/consumers.md` listing which teams consume which
contracts. ADRs need broader sign-off. Consider splitting the spec tree
into per-service subtrees with cross-references.

### For event-driven / microservice architectures

Step 5 (async contracts) becomes critical. Specify every event schema,
every topic/queue, and every consumer's processing guarantee. Add
a domain event catalogue to step 2 alongside the entity schemas.
Consider a shared schema registry spec.
