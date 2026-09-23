## Purpose

Gives the app shared chrome on every page, a sidebar, so that a person who lands on any page can see
what else the app holds and get there, including from a page that does not exist.

## Requirements

### Requirement: Moving between the app's pages

The system SHALL show a sidebar on every page with one entry for each of the app's pages; today that
is the home page. Following an entry SHALL change the page without reloading the app.

#### Scenario: Reaching the home page from the sidebar

- **WHEN** someone on any page follows the sidebar's Home entry
- **THEN** the home page is shown with its `Welcome` heading, without the app reloading

#### Scenario: The current page is identifiable

- **WHEN** someone is on the home page
- **THEN** the sidebar's Home entry is marked as the page they are on

### Requirement: Collapsing the sidebar

The system SHALL let someone collapse the sidebar to a narrow strip of icons, and expand it again,
from a toggle in the page header.

#### Scenario: Collapsing and expanding

- **WHEN** someone uses the toggle in the page header
- **THEN** the sidebar collapses to its icons, and using the toggle again expands it to show the
  entries' names

### Requirement: A path the app does not recognize

The system SHALL show a not-found page for any address it does not recognize, and that page SHALL
carry the sidebar like every other page.

#### Scenario: An unknown address

- **WHEN** someone opens an address the app has no page for
- **THEN** the not-found page is shown, the home page's content is not
- **AND** the sidebar is present, and the page offers a way back to the home page

### Requirement: Navigation usable without a mouse or a screen

The system SHALL make the navigation reachable by keyboard alone and understandable without seeing
the page.

#### Scenario: Reaching the navigation by keyboard

- **WHEN** someone moves through a page using only the keyboard
- **THEN** they can reach each sidebar entry and the header toggle
- **AND** a screen reader identifies which entry is the current page
