## Purpose

Governs how `/DefineFeature` conducts discovery — synthesizing participant intent first, asking
behavioral-choice questions, and presenting assumptions as reasoning chains — so participants remain
informed and in control of what gets built throughout the process.

## Requirements

### Requirement: Synthesis check opens the conversation

The system SHALL evaluate whether the initial request includes sufficient motivation for the scope
of the change. When motivation is sufficient, it SHALL present a plain-language synthesis — two to
three sentences stating what the participant is trying to accomplish and why, followed by a direct
"is that right?" — before asking any questions. When motivation is not sufficient, it SHALL ask one
focused question about the purpose of the change before synthesizing.

#### Scenario: Request with clear motivation

- **WHEN** a participant invokes /DefineFeature with a description that states both what they want
  and why
- **THEN** the first thing shown is a 2–3 sentence synthesis in plain language, ending with a
  direct question confirming understanding ("Is that right?" or equivalent), with no questions
  asked before it

#### Scenario: Request without stated motivation

- **WHEN** a participant invokes /DefineFeature with a description that names a change but gives
  no reason for it
- **THEN** the first thing shown is one focused question about the purpose of the change, not
  about its technical details, and the synthesis follows once that question is answered

#### Scenario: Participant corrects the synthesis

- **WHEN** a participant responds to the synthesis by correcting part of it
- **THEN** the corrected understanding is acknowledged and the conversation continues from the
  updated synthesis, not from the original one

#### Scenario: Participant confirms the synthesis

- **WHEN** a participant confirms the synthesis is correct
- **THEN** the conversation moves to the question phase, or to the assumptions display if there
  are no genuine ambiguities to ask about

Out of scope: synthesis of changes involving breaking changes or external integrations — those may
require more than one motivation question before synthesizing.

### Requirement: Questions are framed as behavioral choices

The system SHALL phrase clarifying questions in terms of what the participant and their users would
notice or do, not in terms of technical implementation. Each question SHALL name the behavioral
consequences of each option. The system SHALL ask at most 1–3 questions before offering the
two-way choice.

#### Scenario: Question about a genuine ambiguity

- **WHEN** there is an open question about how a feature should behave in a way that would affect
  what users see or do
- **THEN** the question names the two or three plausible behaviors in terms of their consequences
  ("Would this happen automatically every time, only when the user asks for it, or only under
  conditions they define?") with no option worded as recommended

#### Scenario: No genuine ambiguities

- **WHEN** the synthesis is confirmed and every open question can be resolved by reasonable
  assumption from the stated motivation
- **THEN** no questions are asked; the conversation moves directly to the assumptions display

Out of scope: technical questions about implementation (database choice, API shape, library
selection) — those belong in design.md.

### Requirement: Two-way agency choice closes the question phase

After asking its questions, the system SHALL offer exactly two paths: proceed with building from
the current understanding, or answer more questions to refine further. It SHALL NOT offer a third
path (such as a separate "explore design options" mode); behavioral design options are surfaced
through how questions are framed, not through a separate mode.

#### Scenario: Participant chooses to build

- **WHEN** a participant selects "build from here" (or equivalent)
- **THEN** the assumptions display is shown and the conversation moves toward writing the planning
  artifacts

#### Scenario: Participant chooses more questions

- **WHEN** a participant selects "a couple more questions" (or equivalent)
- **THEN** up to three more focused questions are asked, after which the two-way choice is
  offered again

#### Scenario: No questions were asked

- **WHEN** there are no genuine ambiguities after the synthesis is confirmed
- **THEN** the two-way choice is not shown; the conversation moves directly to the assumptions
  display

### Requirement: Assumptions are presented as reasoning chains

The system SHALL present only non-obvious assumptions, organized by the motivation or direction the
participant expressed. Each group SHALL open with what the participant said or indicated (in their
words) and list the decisions that follow from it. Obvious defaults ("things we didn't discuss stay
the same") and confirmations of what was explicitly said SHALL be omitted.

#### Scenario: Assumptions after questions

- **WHEN** the participant has confirmed the synthesis and the question phase is complete
- **THEN** the assumptions are shown grouped by motivation, each group opening with "You said X
  [or: you indicated X], so I'm:" followed by a short list of decisions, in plain sentences, with
  no engineering vocabulary

#### Scenario: Participant wants to push back on an assumption

- **WHEN** a participant identifies an assumption that does not match their intent
- **THEN** the specific assumption is addressed and the reasoning chain for that group is updated,
  without requiring the participant to comment on all other assumptions

Out of scope: showing assumptions that were answered as explicit questions — those are confirmed,
not assumed.
