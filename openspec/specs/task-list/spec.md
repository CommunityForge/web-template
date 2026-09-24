## Purpose

Lets one person keep a list of things they need to do — adding tasks, ticking them off, renaming,
reordering and deleting them — and find that list unchanged when they come back to the app on the
same device.

## Requirements

### Requirement: Adding a task

The system SHALL let someone add a task by typing its wording into a single text box and confirming.
A task consists of its wording and whether it is done, and nothing else.

#### Scenario: A task is added

- **WHEN** someone types `Buy milk` into the add box and presses Enter
- **THEN** a task reading `Buy milk` appears in the list, not ticked off
- **AND** the add box is empty again and ready for the next task

#### Scenario: New tasks join the end of the list

- **WHEN** someone adds `Buy milk` and then adds `Call the dentist`
- **THEN** `Call the dentist` appears below `Buy milk`

#### Scenario: An empty entry adds nothing

- **WHEN** someone presses Enter with the add box empty, or containing only spaces
- **THEN** no task is added and the list is unchanged
- **AND** no error message appears

### Requirement: Ticking a task off

The system SHALL let someone mark any task done and undo that. A task that is done SHALL stay in the
list, in its position, visibly ticked.

#### Scenario: Ticking a task

- **WHEN** someone ticks the box on `Buy milk`
- **THEN** `Buy milk` is shown as done
- **AND** it stays where it was in the list

#### Scenario: Unticking a task

- **WHEN** someone unticks a task that was done
- **THEN** it is shown as not done again, still in the same position

#### Scenario: Finished tasks are not hidden

- **WHEN** every task in a list of five is ticked off
- **THEN** all five are still listed and readable
- **AND** nothing has removed, collapsed or filtered them out of view

### Requirement: Renaming a task

The system SHALL let someone change a task's wording on the task's own row, without deleting it and
typing it again. Renaming SHALL NOT change whether the task is done or where it sits in the list.

#### Scenario: A rename is kept by pressing Enter

- **WHEN** someone edits `Buy milk` to read `Buy oat milk` and presses Enter
- **THEN** the task reads `Buy oat milk`, in the same position, with its tick unchanged

#### Scenario: A rename is kept by clicking away

- **WHEN** someone edits a task's wording and clicks elsewhere on the page
- **THEN** the new wording is kept

#### Scenario: A rename is abandoned by pressing Escape

- **WHEN** someone edits `Buy milk` to read `Buy oat milk` and presses Escape
- **THEN** the task still reads `Buy milk`

#### Scenario: A task cannot be renamed to nothing

- **WHEN** someone clears a task's wording entirely and confirms
- **THEN** the task keeps its previous wording and remains in the list

### Requirement: Deleting a task

The system SHALL let someone remove a task from the list. Deleting SHALL take effect immediately,
with no confirmation step, and SHALL NOT be reversible from within the app.

#### Scenario: A task is deleted

- **WHEN** someone chooses to delete `Buy milk` from a list of three tasks
- **THEN** `Buy milk` is gone from the list and the other two remain, in their existing order

#### Scenario: A deleted task cannot be brought back

- **WHEN** a task has just been deleted
- **THEN** nothing on the page offers to restore it
- **AND** the only way to get it back is to type it in again

### Requirement: Ordering the list by hand

The system SHALL let someone put the tasks in any order they choose by dragging a task to a new
position. That order SHALL be the only ordering the list applies — nothing re-sorts it on the
person's behalf. Reordering SHALL be achievable without a pointing device.

#### Scenario: Dragging a task to a new position

- **WHEN** someone drags the third task to the top of the list
- **THEN** it is shown first and the other tasks close the gap it left, keeping their relative order

#### Scenario: Reordering with the keyboard alone

- **WHEN** someone moves a task up or down using only the keyboard
- **THEN** the task changes position exactly as it would when dragged
- **AND** the person is told, without needing to see the screen, where the task ended up

#### Scenario: Ticking a task does not move it

- **WHEN** someone ticks off the second task in a list of four
- **THEN** it is still the second task

### Requirement: The list is still there tomorrow, on that device

The system SHALL keep the list on the device it was created on, so that returning to the app shows
the same tasks, the same ticks and the same order. It SHALL NOT carry the list to another device or
browser.

#### Scenario: Coming back after closing the browser

- **WHEN** someone adds three tasks, ticks the middle one, drags it to the top, closes the browser and
  reopens the app on the same computer
- **THEN** all three tasks are listed, the same one is ticked, and it is first

#### Scenario: Opening the app somewhere else

- **WHEN** someone who has a list on their laptop opens the app on their phone, or in a different
  browser on the same computer
- **THEN** they see an empty list, as if they had never used the app there

#### Scenario: The saved list cannot be read back

- **WHEN** what was saved for this device is present but unreadable
- **THEN** the page opens with an empty list and the person can add tasks straight away
- **AND** no error screen or crash is shown, and the unreadable data does not reappear on later visits

### Requirement: The list belongs to one person

The system SHALL treat the list as private to whoever is using that device. There SHALL be no sign-in
and no way to share a list or see anyone else's.

#### Scenario: Nothing invites anyone else in

- **WHEN** someone looks over the task list page
- **THEN** there is nothing to sign in to, nothing to share, and no other person's tasks anywhere on it

### Requirement: The empty list

The system SHALL make it obvious what to do when there are no tasks yet.

#### Scenario: The first visit

- **WHEN** someone opens the task list for the first time
- **THEN** the page shows a short line inviting them to add their first task
- **AND** the add box is present and ready to type into

#### Scenario: Deleting the last task

- **WHEN** someone deletes the only remaining task
- **THEN** the page returns to that same inviting state rather than showing a bare empty area

### Requirement: Usable without a mouse or a screen

The system SHALL make every action on the task list reachable by keyboard alone, and SHALL describe
each task well enough to be understood without seeing the page.

#### Scenario: Reaching everything by keyboard

- **WHEN** someone moves through the page using only the keyboard
- **THEN** they can reach the add box and, for every task, its tick, its wording for renaming, its
  delete action, and its move-up and move-down actions

#### Scenario: A task read aloud

- **WHEN** a screen reader reaches a task
- **THEN** it announces the task's wording and whether it is done
