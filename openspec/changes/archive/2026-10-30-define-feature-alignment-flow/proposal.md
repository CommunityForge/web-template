# Proposal: define-feature-alignment-flow

## Why

Participants consistently skip the assumptions confirmation step at the end of `/DefineFeature`,
leaving them without real agency in what gets built. The step arrives after several exchanges when
they are already committed and ready to move forward; it presents an undifferentiated flat list of
engineering-language items; and it offers only "accept all or type one comment" — a design that
replicates the Terms of Service failure mode instead of supporting informed participation. One of
LAUDE's core goals is that participants feel included in and in control of what their tool does;
the current design works against that goal at the moment it matters most.

## What Changes

- **Discovery schema redesigned** (`openspec/schemas/guided/schema.yaml`): the discovery
  conversation phases are restructured so a plain-language synthesis check happens first (before
  detailed questions), questions are framed as behavioral choices rather than technical
  specifications, and a two-way agency moment ("build from here" vs. "a couple more questions")
  closes the question phase. The assumptions confirmation is restructured as reasoning chains
  grouped by motivation ("You said X, so I'm doing Y") rather than a flat list of ASSUMED items.

- **DefineFeature.md Amendment 2 updated** (`.claude/commands/DefineFeature.md`): the instruction
  governing how ASSUMED lines are displayed before the `/WriteCode` sentence is updated to reflect
  the new reasoning-chain format.

## Non-Goals

- DescribeProblem, WriteCode, UpdateDocs, and Verify commands are not changed.
- The synthesis check does not replace the background analysis work (codebase read, gap triage);
  it only changes what is shown first to the participant.
- The format of discovery.md as read by downstream artifacts (proposal, specs) is not changed;
  the ASSUMED marker and file structure are preserved.
- Existing in-flight changes are not affected; the new flow applies to future /DefineFeature
  invocations only.

## Capabilities

### New Capabilities

- `define-feature-flow` — the observable conversation behavior of the /DefineFeature command as
  experienced by LAUDE participants.

### Modified Capabilities

_(none)_

## Impact

- `openspec/schemas/guided/schema.yaml` — discovery artifact instruction phases 1–6 restructured
- `.claude/commands/DefineFeature.md` — Amendment 2 updated
