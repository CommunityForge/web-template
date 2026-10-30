# Tasks: define-feature-alignment-flow

## 1. Redesign discovery phases in schema.yaml

- [x] 1.1 Read the full current discovery instruction in `openspec/schemas/guided/schema.yaml`
      and identify the exact text of Phases 1–6 to be replaced; verify by checking that all phase
      tags are present in the file
- [x] 1.2 Rewrite Phase 3 (challenge-before-refining) to lead with a synthesis check: evaluate
      whether the initial request includes sufficient motivation for the scope, synthesize in 2–3
      plain-language sentences ending with "is that right?", and (per design.md Decision 1) embed
      any premise-challenge note as a sentence within the synthesis when relevant rather than as a
      separate adversarial opening; verify the rewritten phase contains no engineering vocabulary
      that would fail the Colleague Test
- [x] 1.3 Rewrite Phase 4 (ask) to require questions be framed as behavioral choices — naming
      consequences, not technical options — and cap questions at 1–3 before offering the two-way
      choice; add the two-way agency moment ("build from here" vs "a couple more questions") as the
      closing step of this phase; verify the rewritten phase explicitly forbids questions about
      implementation details
- [x] 1.4 Rewrite Phase 5 (confirm assumptions) to replace the flat ASSUMED list with
      reasoning chains grouped by motivation ("You said X, so I'm: [bullets]"), omitting obvious
      defaults and confirmations of what was explicitly said; verify the rewritten phase includes an
      example in the reasoning-chain format
- [x] 1.5 Run a complete /DefineFeature invocation on a simple test request and confirm: (a)
      synthesis appears before any question, (b) questions are framed as behavioral choices, (c)
      the two-way choice appears after questions, (d) assumptions display as reasoning chains

## 2. Update DefineFeature.md Amendment 2

- [x] 2.1 Read `.claude/commands/DefineFeature.md` and identify the exact text of Amendment 2
- [x] 2.2 Update Amendment 2 to remove the implication that ASSUMED lines are a flat list and
      add a note that they appear as reasoning chains grouped by motivation; preserve the core
      behavior (show them before /WriteCode, participant approves by moving on); verify the updated
      amendment does not conflict with the schema's Phase 5 output format
- [x] 2.3 Verify a complete /DefineFeature run produces an ASSUMED display before the /WriteCode
      sentence that reads as reasoning chains, not as an engineering audit trail
