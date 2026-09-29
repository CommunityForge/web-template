# Context docs

Reached from the **No context docs** row. `docs/context/` is reference for epistemic alignment:
the material that lets `/DefineFeature` ask fewer, better questions because it already knows how
the work is done today. Its own `README.md` holds the contract and the index; this file is the
coaching for a person who has none yet.

## Why it matters, in one breath

Every `/DefineFeature` starts by looking things up before asking. With nothing to look up, every
gap becomes a question, and the answers live only in that chat. A folder of the trade's own
documents turns those questions into lookups, and the same answer holds for every change after.

## What belongs

Things that describe how the work is done today, which the app is meant to serve:

- **How it is done now**: the current process, step by step, with who does what.
- **Terms of the trade**: a glossary of the words people actually use, with the ones that mean
  something specific in this line of work.
- **Forms and templates**: the intake sheet, the report layout, the checklist, as they exist today.
- **Rules**: what must always or never happen, and where that rule comes from (policy, law, habit).
- **Examples of good output**: a finished report, a filled form, a record done right.

Things that belong elsewhere:

- Plans and designs for a change: `openspec/changes/<name>/`, written by `/DefineFeature`.
- What the app already does: `openspec/specs/`, kept current by `/UpdateDocs`.
- Anything secret: passwords, keys, personal data about real people. A form template, yes; a
  filled-in form about a real person, no.

## The offer

When the person has files at hand (attached, or named), offer to save them:

1. Copy each file into `docs/context/` under a kebab-case name that says what it is
   (`intake-form.md`, `glossary.md`, `weekly-report-example.pdf`).
2. Add one line per file to the index in `docs/context/README.md`: what it is and when to open it.
   A file without an index line is invisible to discovery.
3. Commit on a clear yes, on the current branch, with a message naming the files.

When `docs/context/README.md` is missing, recreate it before adding files: three short paragraphs
(what the folder is for, that files here are consulted rather than loaded, and that a file without
an index line is invisible) followed by an `## Index` list with one line per file.
