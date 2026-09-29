# Coaching a bug report

Reached from the **Bug** row: the change was built, the person tried it, and it isn't doing what
was agreed. The fix happens in a fresh chat; this chat's job is to make that chat's first message
good enough that the fix lands on the first try.

## The four parts

A report the next chat can act on has all four, each one line, in the person's own words:

1. **Did**: the exact clicks or typing, from a screen they can name.
2. **Expected**: what they thought would happen, as something visible.
3. **Saw**: what happened instead, as something visible. An error message goes in verbatim.
4. **Screenshot**: attached when the difference is visual. The desktop app's Code tab accepts a
   pasted image.

Ask for whichever part is missing, one question per message. Two parts are usually missing: the
"did" is vague ("the login broke") and the "expected" is implied. A report without a "saw" is a
guess, not a report.

## Scope

- **One bug per fresh chat.** A second bug in the same chat lengthens the transcript the first fix
  needs, and the fixes start undoing each other. When they have three, they have three chats.
- **Inside this change.** The fix belongs to the change that introduced the behavior, on that
  change's branch, so it rides in the same pull request and the same preview. Name the change in the
  report so the next chat starts on the right branch: in a local session the branch is already
  checked out; in cloud the next chat fetches it (the `/Align` cloud checkout offer).
- **The fix is ordinary work, not a workflow command.** The next chat reads the report and fixes the
  code; when it is done it pushes to the same branch, and the preview updates on its own. No
  `/DefineFeature`, no `/WriteCode`.

## The message to paste

Draft it for them, ready to paste into the new chat:

```
In the <change name> change, on the <screen> screen, I <did>.
I expected <expected>. Instead <saw>.
(screenshot attached)
```

End on the instruction: start a new chat, paste this, attach the screenshot. When the preview is the
place they tried it, the preview link goes in too, so the next chat can look at the same thing.
