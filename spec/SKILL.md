---
name: spec
description: Generate a feature specification through an interactive interview. Use when starting a new feature spec, when the user wants to document requirements, or mentions "create a spec" or "write a spec".
argument-hint: "[feature-name] [optional: brief description]"
---

# Spec Generator - Interactive Wizard

Generate a comprehensive feature specification by interviewing the user about their requirements, then analyzing the codebase to produce a customized spec document.

## Arguments

- `$ARGUMENTS[0]` / `$0` - Feature name (optional, will ask if not provided)
- `$ARGUMENTS[1:]` / remaining args - Brief description of the feature (optional)

**Examples:**
```
/spec
/spec notifications
/spec notifications Send push notifications when a crew lineup is submitted
/spec user-preferences Allow users to customize their dashboard layout and notification settings
```

When a description is provided, use it to:
1. Pre-fill the Problem and Goals sections with a draft
2. Skip basic "what is this feature" questions
3. Jump straight to clarifying questions about scope, edge cases, and technical approach
4. Make the interview faster and more focused

## Phase 1: Codebase Analysis (Silent)

Before asking questions, quickly analyze the codebase to understand context:

1. **Detect stack** - Check for Gemfile, package.json, requirements.txt, go.mod, etc.
2. **Find conventions** - Read CLAUDE.md, AGENTS.md, CONTRIBUTING.md if they exist
3. **Check existing specs** - Look at specs/, docs/specs/, docs/ for format examples
4. **Identify patterns** - Note authorization, testing, service patterns in use

Store this context internally - you'll use it to ask better questions and generate appropriate output.

## Phase 2: Discovery Interview

Use the AskUserQuestion tool to gather requirements through focused questions. Ask in batches of 1-3 related questions to keep the flow conversational.

### Adapt Based on Input Provided

**If description was provided** (e.g., `/spec notifications Send push notifications when lineup submitted`):
- Draft the Problem statement from the description
- Present it back: "Based on your description, here's what I understand: [draft]. Is this accurate?"
- Skip Round 1 basic questions, jump to clarifying questions
- Focus interview on gaps: scope boundaries, edge cases, technical constraints

**If only feature name provided** (e.g., `/spec notifications`):
- Start Round 1 with: "Tell me about the notifications feature you want to build."
- Run full interview

**If nothing provided** (e.g., `/spec`):
- Start with: "What feature would you like to spec out?"
- Get feature name first, then run full interview

### Round 1: The Problem

Ask about the core problem (skip if description provided):

```
Questions to cover:
- What problem are you trying to solve? (or what capability are you adding?)
- Who is affected by this problem? (user role, system component)
- What happens today? What's the pain point or gap?
- Why is this important now?
```

### Round 2: The Solution

Ask about the desired outcome:

```
Questions to cover:
- What should happen instead? (desired end state)
- Can you walk me through the ideal user flow?
- Are there any specific UI/UX requirements?
- Are there similar features in this codebase I should reference?
```

### Round 3: Scope & Constraints

Ask about boundaries:

```
Questions to cover:
- What's explicitly OUT of scope for this feature?
- Are there any technical constraints I should know about?
- Does this depend on other features or enable future ones?
- Any performance, security, or compliance considerations?
```

### Round 4: Edge Cases & Errors

Ask about failure modes:

```
Questions to cover:
- What could go wrong? How should errors be handled?
- Are there edge cases we need to handle specifically?
- What validation rules apply?
- What error messages should users see?
```

### Round 5: Verification (Optional)

If unclear, ask:

```
Questions to cover:
- How will we know this feature is working correctly?
- What should QA test specifically?
- Any metrics or success criteria?
```

## Phase 3: Generate the Spec

Based on the interview answers AND the codebase analysis, generate a complete spec using the template below.

**Key:** Fill in as much as possible from the interview. Don't leave placeholders where you have answers.

### Template Structure

```markdown
# [Feature Name] Spec

**Status:** `draft`
**Branch:** `feat/[kebab-case-feature-name]`
**Author:** [from user if known, otherwise leave blank]
**Created:** [today's date]

---

## Problem

**What:** [From Round 1 - one sentence]

**Who:** [From Round 1 - affected users/roles]

**Impact:** [From Round 1 - why it matters, current pain]

---

## Goals

1. [Primary goal derived from Round 2]
2. [Secondary goals if mentioned]

### Non-Goals

- [From Round 3 - explicit out of scope items]

---

## User Stories

[Generate user stories from the user flow described in Round 2]

### US-1: [Title based on primary flow]

**As a** [role from Round 1]
**I want** [capability from Round 2]
**So that** [benefit derived from problem/impact]

**Acceptance Criteria:**
- [ ] [Derived from user flow]
- [ ] [Derived from edge cases in Round 4]
- [ ] [Validation rules from Round 4]

[Add more user stories as needed based on interview]

---

## Technical Approach

### Overview

[Synthesize the solution from Round 2, incorporating codebase patterns you detected]

### [Appropriate Layer 1 for this codebase]

[Fill in based on interview + codebase patterns]

### [Appropriate Layer 2 for this codebase]

[Fill in based on interview + codebase patterns]

### [Appropriate Layer 3 for this codebase]

[Fill in based on interview + codebase patterns]

---

## Files

[Predict files based on codebase structure + feature requirements]

| Action   | Path                              | Purpose              |
| -------- | --------------------------------- | -------------------- |
| ...      | ...                               | ...                  |

---

## Patterns to Follow

### Existing Similar Feature

[Reference the similar feature mentioned in Round 2, or find one yourself]

### Code References

[Actual paths from this codebase based on your analysis]

---

## Edge Cases

[From Round 4]

| ID  | Scenario                | Expected Behavior          |
| --- | ----------------------- | -------------------------- |
| E1  | [from interview]        | [from interview]           |

---

## Error Messages

[From Round 4]

| Trigger                   | Message                              |
| ------------------------- | ------------------------------------ |
| [from interview]          | "[from interview]"                   |

---

## UI/UX Specifications

[From Round 2 UI/UX requirements]

---

## Testing Requirements

[Customize test types for detected framework]

### [Test Type 1]
- [ ] [Derived from acceptance criteria]

### [Test Type 2]
- [ ] [Derived from user flows]

---

## Open Questions

[Any unresolved items from the interview]

- [ ] **Q1:** [question] — *Affects: [section]*

---

## Dependencies

[From Round 3]

**Requires:**
- [Prerequisites mentioned]

**Enables:**
- [Future features mentioned]

---

## Post-Deployment Verification

[From Round 5 or derive from acceptance criteria]

1. [ ] [Verification step]

---

## References

- [Any links or references mentioned during interview]
```

## Phase 4: Output & Next Steps

1. **Write the spec file:**
   - If `$ARGUMENTS` provided: `specs/$ARGUMENTS.md`
   - Otherwise: Ask user for the feature name, then create `specs/[name].md`

2. **Summarize what was created:**
   - Recap the key points from the interview
   - Note any open questions that need resolution
   - Suggest next steps (e.g., "Review the spec and mark status as `ready` when approved")

3. **Offer to iterate:**
   - Ask if any sections need expansion or clarification
   - Offer to add more user stories or edge cases

## Interview Guidelines

- **Be conversational** - Don't dump all questions at once. Ask 1-3 questions per round.
- **Use context** - Reference codebase patterns you found ("I see you use Pundit policies - will this need a new policy?")
- **Probe deeper** - If an answer is vague, ask follow-up questions
- **Summarize back** - Confirm understanding before generating ("So the main flow is: user clicks X, then Y happens, then Z. Is that right?")
- **Fill gaps intelligently** - Use codebase knowledge to suggest reasonable defaults, but flag assumptions
- **Keep momentum** - Don't over-interview. 3-5 rounds should be enough for most features.

## Special Modes

### Quick Mode: Just the Template

If user says "just give me the template", "skip the interview", or "blank template":
1. Analyze the codebase for terminology
2. Generate a template with appropriate section headers and placeholder text
3. Save to `specs/TEMPLATE.md`
4. Skip the interview entirely

### Update Mode: Existing Spec

If `specs/[feature-name].md` already exists:
1. Read it first
2. Ask: "I found an existing spec for [feature]. Would you like to update it or start fresh?"
3. If updating, preserve completed sections and focus questions on gaps

### Description Provided (Fast Track)

If user runs `/spec notifications Send push notifications when a crew lineup is submitted`:
1. Parse feature name (`notifications`) and description (`Send push notifications...`)
2. Draft Problem/Goals from description
3. Present draft for confirmation: "Here's what I understand: [draft]. Is this right?"
4. Skip basic "what is this" questions
5. Jump to clarifying questions: scope, edge cases, technical approach
6. Shorter interview (2-3 rounds instead of 4-5)

### Feature Name Only

If user runs `/spec notifications-system`:
1. Still do the full interview, but use the name to make questions more specific
2. "Tell me about the notifications system you want to build..."

### No Arguments

If user runs just `/spec`:
1. Ask: "What feature would you like to spec out? Give me a name and optionally a brief description."
2. Then proceed based on what they provide
