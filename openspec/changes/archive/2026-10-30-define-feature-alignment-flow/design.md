# Design: define-feature-alignment-flow

## Context

See proposal.md — Why.

Two files govern the /DefineFeature conversation as it currently exists:

1. `openspec/schemas/guided/schema.yaml` — the `discovery` artifact instruction (phases 1–6) which
   drives the live conversation with the participant.
2. `.claude/commands/DefineFeature.md` — Amendment 2, which controls how ASSUMED lines from
   discovery.md are displayed at the end, before the `/WriteCode` sentence.

The current discovery instruction runs: look up → triage → challenge (premise first) → ask
one-way-door questions → confirm flat ASSUMED list → write. The problem is that the first
user-facing output is a challenge ("here's why this might be unnecessary"), the questions are not
required to be framed as behavioral choices, there is no agency moment after questions, and the
assumptions confirmation is a flat list of ASSUMED-marked items.

## Goals / Non-Goals

**Goals**: Restructure the discovery phases so participants see a synthesis first, questions are
behavioral, a two-way choice closes questions, and assumptions display as reasoning chains.

**Non-goals**: Do not change phases 1–2 (look up and triage); do not change how design.md or
tasks.md are authored; do not change any command other than DefineFeature.md.

## Decisions

### Decision 1: What happens to the premise challenge?

The current Phase 3.2 requires sending a challenge as the very first question: "the strongest
reason this change might be unnecessary." This conflicts with leading with a synthesis.

**Option A — Replace entirely**: Remove the premise challenge from the instruction. The synthesis
implicitly checks the goal; if the participant's stated purpose is unclear, the synthesis exposes
that.

**Option B — Subsume into synthesis**: The synthesis still opens with what the participant is
trying to do and why. A sentence can note an alternative path or acknowledge the change's scope.
This preserves the intent of the premise check (is this the right change?) inside a collaborative
frame rather than an adversarial one.

**Option C — Keep as-is but move after synthesis**: Premise challenge fires second, after
synthesis confirmation.

**Recommendation: Option B.** The synthesis can include an honest framing note when relevant ("One
thing worth flagging: [premise observation]. Does this still match what you want?") without leading
with a challenge. This preserves the analytical value (catching a misguided change early) while
fitting the LAUDE participant profile. Rejected A because the premise check catches real scope
issues; rejected C because it still creates a defensive second message after an inviting first.

### Decision 2: Schema modification approach

**Option A — Rewrite the discovery instruction in schema.yaml directly.** Clean, single source of
truth.

**Option B — Add an amendment in DefineFeature.md that overrides the schema phases.** No schema
changes; the amendment layer handles it.

**Recommendation: Option A.** The schema instruction is already the authoritative source for this
behavior; adding a competing layer in DefineFeature.md creates two places that must stay in sync.
The `discovery` instruction is self-contained in schema.yaml and is the right place for this logic.
Rejected B because it introduces the exact kind of prompt-arguing-with-itself problem the
config.yaml comment describes.

### Decision 3: Amendment 2 scope

Amendment 2 currently instructs DefineFeature.md to list every ASSUMED line from discovery.md
verbatim before the /WriteCode sentence. Once the schema changes, ASSUMED lines will be written as
reasoning chains. Amendment 2 needs only a small update: remove the implication that ASSUMED lines
are a flat list, and add a note that they appear as reasoning chains that the participant can scan.
The core behavior (show them before /WriteCode; the participant approves by moving on) is preserved.

### Decision 4: Edge case — no motivation and participant says "just do it"

If the motivation question is unanswered or the participant says "just do it / figure it out," the
synthesis should proceed with whatever was inferred, marking it clearly as an inference and noting
it could be refined. This keeps momentum while still being transparent. Record as ASSUMED in
discovery.md; the participant can correct at the assumptions stage.

## Risks / Trade-offs

- **Risk: Synthesis is wrong and participant doesn't correct it** → The reasoning-chain
  assumptions display catches this; a wrong synthesis produces wrong assumptions the participant
  can see. Mitigation: the synthesis must end with a direct question ("is that right?"), not a
  statement.
- **Risk: The two-way agency choice adds friction for participants who never want more questions**
  → Mitigation: the choice only appears when questions were actually asked; if there are no
  genuine ambiguities, the conversation moves directly to assumptions without showing it.
- **Risk: Reasoning-chain format makes discovery.md ASSUMED lines harder to parse in downstream
  artifacts** → Discovery.md is engineering-facing; the format change is cosmetic for downstream
  readers. Proposal.md already carries ASSUMED items forward as stated assumptions; that behavior
  is unchanged.

## Migration Plan

The schema change takes effect for all future /DefineFeature invocations. Existing in-flight
changes in `openspec/changes/*/` are not affected — their discovery.md files are already written.
No data migration needed.

## Open Questions

None load-bearing.
