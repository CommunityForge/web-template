## Purpose

Gives the app shared chrome for moving between its pages, so that a person who lands on any page can
see what else the app holds and get there, including from a page that does not exist.

## Requirements

### Requirement: Moving between the app's pages

The system SHALL show, at the top of every page, a way to reach each of the app's pages. Following it
SHALL change the page without reloading the app.

#### Scenario: Reaching the task list from the starter page

- **WHEN** someone on the starter page follows the link to the task list
- **THEN** the task list page is shown and the address ends in `/tasks`

#### Scenario: Reaching the starter page from the task list

- **WHEN** someone on the task list follows the link to the starter page
- **THEN** the starter page is shown, with its heading and its click-counter exactly as before

#### Scenario: The current page is identifiable

- **WHEN** someone is on the task list
- **THEN** the task list's link is marked as the page they are on, distinguishably from the other links

### Requirement: The starter page keeps working

The system SHALL leave the starter page's existing content unchanged. The only visible difference
SHALL be the shared navigation now above it.

#### Scenario: The starter page after this change

- **WHEN** someone opens the app at its root address
- **THEN** the starter page shows its `Get started` heading, its click-counter, and its documentation
  and community sections, all behaving as they did before
- **AND** the shared navigation is shown above them

### Requirement: A path the app does not recognize

The system SHALL continue to show a not-found page for any address it does not recognize, and that
page SHALL carry the shared navigation like every other page.

#### Scenario: An unknown address

- **WHEN** someone opens an address the app has no page for
- **THEN** the not-found page is shown, the starter page's content is not
- **AND** the shared navigation is present, so the task list and starter page are both one step away

### Requirement: Navigation usable without a mouse or a screen

The system SHALL make the navigation reachable by keyboard alone and understandable without seeing
the page.

#### Scenario: Reaching the navigation by keyboard

- **WHEN** someone moves through a page using only the keyboard
- **THEN** they reach each navigation link before the page's own content
- **AND** a screen reader announces it as the app's navigation and identifies which page is current
