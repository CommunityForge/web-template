# Discovery: define-feature-alignment-flow

Date: 2026-10-30

## Coverage scan

| Category         | Status | Triage     | Notes                                                              |
| ---------------- | ------ | ---------- | ------------------------------------------------------------------ |
| Functional scope | Clear  | —          | Redesign /DefineFeature discovery phases                           |
| Domain model     | N/A    | —          | No user-facing data model involved                                 |
| Persistence      | Clear  | —          | schema.yaml + DefineFeature.md                                     |
| Interaction      | Clear  | PRODUCT    | The conversation experience for participants — answered in session |
| Data operations  | N/A    | —          |                                                                    |
| Ownership        | Clear  | CONVENTION | Internal harness tooling; owned by project                         |
| Non-functional   | N/A    | —          |                                                                    |
| Integration      | Clear  | DESIGN     | Must not break WriteCode/UpdateDocs; deferred to design.md         |
| Migration        | Clear  | DESIGN     | Existing in-flight changes unaffected; deferred to design.md       |
| Failure handling | N/A    | —          |                                                                    |
| Success criteria | Clear  | PRODUCT    | Answered in session                                                |

## Resolved by convention

- Out-of-scope commands (DescribeProblem, WriteCode, UpdateDocs, Verify) — not changed: their
  behavior is defined in their own command files and not referenced by the discovery schema.
- The LAUDE context doc (`/Users/samantha/Downloads/Laude Context.md`) establishes that participants
  are nonprofit domain experts, not engineers, and that elicitation is the primary job of any
  agent-facilitated conversation — this is the source of the design direction below.

## Premise check

**Premise as challenged:** The current schema already has a Phase 5 confirmation step with a
plain-language translation requirement. A language-only fix to that step could address the problem
without redesigning the flow.

**User's response:** Confirmed that timing (Phase 5 arrives after the user is committed and ready
to move) and structure (undifferentiated flat list vs. reasoning chains grouped by motivation) are
the core issues. A language-only patch would not fix the timing problem. Full flow redesign
confirmed as necessary.

## Ownership table

| Thing                          | Owner   | Place   | Audience      | Control             | Exit         |
| ------------------------------ | ------- | ------- | ------------- | ------------------- | ------------ |
| schema.yaml (discovery phases) | Project | Nowhere | Harness users | Project maintainers | With project |
| DefineFeature.md (amendments)  | Project | Nowhere | Harness users | Project maintainers | With project |

## Questions and answers

All product-level decisions were established in the preceding /DescribeProblem session. No
additional questions were needed.

**Q: Is the timing and structure of the current assumptions step (not just its language) the core
problem?**
A: Yes. The step arrives at the end when the user is committed, the format is a flat list of
engineering-language items, and the only interaction is "accept all or type one comment." This
replicates the Terms of Service failure mode.

**Q: What is the minimum input needed before a synthesis is possible?**
A: The LLM should evaluate whether the initial request includes sufficient motivation for the scope
of the change. "Sufficient" is proportional: a small visual change clears the bar with almost no
context; a change with broader implications needs the "why" before synthesis. If motivation is
absent, ask one focused question about it before synthesizing.

**Q: How should questions be framed?**
A: As behavioral choices — outcome-oriented, not technical. The question surfaces a design
alternative by naming the behavioral consequences: "Would this happen automatically, under
conditions you set, or when the user asks for it?" This means the questions ARE the design
exploration; no separate "explore design options" path is needed.

**Q: Two-way or three-way agency moment?**
A: Two-way. "Build from here" or "a couple more questions." The questions themselves surface design
options when framed right, so a separate third option is redundant.

**Q: What replaces the flat ASSUMED list?**
A: Reasoning chains grouped by motivation: "You said X, so I'm doing Y." Each group starts with
what the participant said or indicated, and the decisions that follow from it. Only non-obvious
assumptions are surfaced — obvious defaults (nothing we didn't discuss stays the same) and
confirmations of what was explicitly said are omitted.

## Deferred to design.md

- How the synthesis check interacts with the existing Phase 3 premise challenge in the schema
  (whether the synthesis replaces or subsumes it)
- Exact restructuring of schema phases 1–6
- Whether discovery.md's ASSUMED template section needs a new format hint
- How to handle the edge case where the initial request has zero stated motivation and the one
  motivation question is unanswered or answered with "just do it"

## Assumptions

ASSUMED: Both files change — `openspec/schemas/guided/schema.yaml` (discovery phases 1–6) and
`.claude/commands/DefineFeature.md` (Amendment 2, which controls how ASSUMED lines are displayed
before the /WriteCode sentence).

ASSUMED: The synthesis check becomes the opening user-facing move, replacing the current premise
challenge as the first thing shown. Background analysis (codebase read, gap triage) still runs
first, but the first message a participant sees is a synthesis confirmation, not a challenge.
The adversarial framing of the premise challenge does not fit the LAUDE participant profile.

ASSUMED: The reasoning-chain assumption format applies both inside the discovery conversation (shown
at the end of the question phase, before proceeding) and to the ASSUMED lines displayed by
DefineFeature.md's Amendment 2 before /WriteCode — so those automatically improve once the schema
changes.

ASSUMED: The two-way agency choice ("build from here" vs "a couple more questions") appears
whenever questions are asked, at the natural end of the question phase. It does not appear if the
synthesis is confirmed and there are genuinely no ambiguities to ask about.

## Out of scope

- DescribeProblem, WriteCode, UpdateDocs, and Verify commands are not changed.
- The visual or UI design of any application screen is not part of this change.
- Changes to how discovery.md is read by downstream artifacts (proposal, specs) — the file
  structure and ASSUMED marker are preserved; only the content format of assumptions changes.
