# Collaborative Development Workflow (Humans & Agents)

This document defines the development process for this repository. It serves as a unified execution manual and collaboration standard for Human Developers and AI Agents alike. In our ecosystem, both are treated as co-equal team members (referred to as **Implementers**) who collaborate asynchronously through **Basecamp** as our tracking engine, using **Gherkin/Cucumber** as our shared, executable specifications language.

---

## 1. Core Principles

1. **Co-Equal Partnership**: Humans and agents use the same boards, follow the same pipeline, and are held to the same standards of test coverage, code quality, and documentation.
2. **Basecamp as the Single Source of Truth**: Requirements, active state, implementation checklists, discussions, and technical decisions live in Basecamp.
3. **Behavior-Driven Development (BDD)**: All non-trivial functional changes must be described using Gherkin syntax (Given-When-Then). Gherkin serves as both the unambiguous requirement specification and the automated test suite.

---

## 2. Basecamp Card Table Structure (The State Machine)

Our development pipeline is managed via a Basecamp Card Table. The columns represent distinct phases of development and establish clear transitions of ownership:

```
[ Backlog ] ➔ [ Triage & Planning ] ➔ [ Up Next ] ➔ [ In Progress ] ➔ [ Blocked / On Hold ] ➔ [ Under Review ] ➔ [ Done ]
```

### Column Definitions & Transition Rules

#### 1. Backlog
* **Purpose**: A holding zone for raw ideas, bug reports, feature requests, and refactoring notes.
* **Who can add**: Anyone (humans, monitoring tools, automation scripts).
* **Requirements**: No strict format is required; entries can be unstructured.

#### 2. Triage & Planning
* **Purpose**: Active refinement zone where raw Backlog ideas are transformed into actionable, specified tickets.
* **Who manages**: Tech Leads, Product Owners, or Senior Agents.
* **Transition rule**: Cards are moved here from the Backlog to be refined. Once Gherkin scenarios are completed and approved, the card moves to **Up Next**.

#### 3. Up Next (The Queue)
* **Purpose**: The prioritized queue of structured, actionable cards ready for execution.
* **Who manages**: Product Owners (prioritization).
* **Requirements to enter**: To be moved into *Up Next*, a card must have:
  * An action-oriented **Title**.
  * A **Description** containing business context and **Gherkin Specifications**.
  * A high-level **Card Steps checklist** for core deliverables.

#### 4. In Progress
* **Purpose**: Active implementation phase.
* **Who manages**: The assigned Implementer (Human or Agent).
* **Transition rule**: An Implementer claims a card by **assigning it to themselves** and **moving it to In Progress** (moving out of *Up Next*).

#### 5. Blocked / On Hold (Human-in-the-Loop Gate)
* **Purpose**: A parking zone for active cards that cannot proceed due to ambiguity, missing environment secrets, upstream dependencies, or unresolved test failures.
* **Who manages**: The current Implementer + the requested Unblocker.
* **Transition rule**: When moving a card here from *In Progress*, the Implementer **must** leave a comment explaining the blocker in detail, provide diagnostic context (e.g., test logs, stack traces), and `@mention` the teammate (human or agent) needed to resolve the issue.

#### 6. Under Review
* **Purpose**: Code is complete, all local tests pass, and a Pull Request is ready for peer review.
* **Who manages**: The Peer Reviewer (Human or Agent).
* **Transition rule**: The Implementer pushes their branch, opens a PR, posts the PR link in a Basecamp card comment, and moves the card here from *In Progress*.

#### 7. Done
* **Purpose**: The Pull Request has been reviewed, approved, merged, and verified in production.
* **Who manages**: The Peer Reviewer, Tech Lead, or Deployment Automation.
* **Transition rule**: Moved here from *Under Review* after the code is merged and verified.

---

## 3. Card Anatomy (Executable Specifications)

To ensure that both humans and AI agents understand requirements without ambiguity, every card in **Up Next** must conform to this structured layout.

### A. Clear, Action-Oriented Title
Avoid vague titles like "User Invitations". Instead, use active verbs: "Implement user invitation expiration logic".

### B. Business Context & Gherkin Scenarios
The description must frame the business value and define the acceptance criteria in Gherkin format.

```markdown
### Business Context
Currently, user invitation tokens last indefinitely. To improve security and clean up stale pending users, invitation tokens should expire 48 hours after they are generated.

### Acceptance Criteria
Feature: Expire User Invitations

  Scenario: Invitation is still valid within 48 hours
    Given a user invitation was created "24 hours ago"
    When the user attempts to accept the invitation
    Then the invitation should be accepted successfully
    And the user account should be activated

  Scenario: Invitation is expired after 48 hours
    Given a user invitation was created "50 hours ago"
    When the user attempts to accept the invitation
    Then the system should refuse the invitation with an "expired" error
    And the user account should remain inactive
```

### C. Card Steps (The Checklist)
Steps serve as granular checkpoints. They provide visual tracking for teammates and structure the execution path for agents.

* [ ] Write regression/integration tests matching the Gherkin specifications
* [ ] Implement token generation timestamp in database migration
* [ ] Implement token expiration check in `UserInvitation` model
* [ ] Handle expired token exceptions in the UI/Controller
* [ ] Verify the entire test suite passes green locally
* [ ] Push branch and open Pull Request

---

## 4. The Collaborative Execution Loop

When an Implementer (Human or Agent) begins working on a card, they follow this exact, disciplined loop. This loop directly drives the state transitions of the Basecamp Card Table:

### Workflow State Matrix

| Execution Step | Starting Column | Ending Column | Key Action / Tooling |
| :--- | :--- | :--- | :--- |
| **Step 1: Claim & Branch** | `Up Next` | `In Progress` | Assign self, move card, checkout local branch |
| **Step 2: Refine Plan** | `In Progress` | `In Progress` | Expand/add sub-steps to Card checklist |
| **Step 3: Edit & Verify** | `In Progress` | `In Progress` | Write tests first, implement, verify locally |
| **Step 4: Block Escalation** *(Optional)* | `In Progress` | `Blocked / On Hold` | Comment with diagnostics, @mention supervisor, pause |
| **Step 5: PR & Hand-off** | `In Progress` | `Under Review` | Push branch, open PR, link PR in comment, move card |
| **Step 6: Merge & Close** | `Under Review` | `Done` | Peer review approval, merge PR, move card |

---

### Step-by-Step Execution Guide

#### Step 1: Claiming & Branching
1. Take the top card from the **Up Next** column.
2. Assign the card to yourself.
3. Move the card to **In Progress**.
4. Check out a local feature branch named after the card (e.g., `feature/invitation-expiration-789`).

#### Step 2: Refining the Plan
* Read the Gherkin scenarios carefully.
* If the pre-authored **Card Steps** are too high-level, the Implementer should add sub-steps (e.g., `[ ] Generate ActiveRecord migration`, `[ ] Refactor token lookup query`) directly to the Basecamp Card Steps checklist. This acts as a collaborative implementation plan.

#### Step 3: Local Edit & Verify Loop (BDD Execution)
1. **Write Tests First**: Translate the Gherkin specs into automated executable test files (e.g., Cucumber features or RSpec integration specs). Run them and observe them fail.
2. **Implement Code**: Write the minimal code necessary to make the tests pass.
3. **Verify Locally**: Run the test suite and linters locally.
4. **Self-Correction**: If tests fail, analyze the error output, inspect logs, make adjustments, and rerun. The Implementer must iterate locally until all tests pass.
5. **Asynchronous Updates**: As steps are completed, check them off on the Basecamp card. This keeps the entire team aligned on progress in real time without distracting status meetings.

#### Step 4: Handling Blocks (The Escape Hatch)
If the Implementer cannot make a test pass, detects an edge-case contradiction in the Gherkin spec, or lacks access to a required key/secret:
1. Stop local execution.
2. Move the card to **Blocked / On Hold**.
3. Write a comment on the card detailing the block:
   > 🤖 **AGENT UPDATE**: I have implemented the model logic, but the controller test is failing because the Mock API requires a client ID secret.
   >
   > **Blocker**: Missing `API_CLIENT_ID` in test environment.
   > @Jane Smith, could you help me configure this or point me to where test credentials are stored?
4. Do not block yourself; return to **Up Next** and claim a different card.

#### Step 5: Submission & Hand-off
1. Verify all tests, linters, and type-checkers are completely green.
2. Commit changes with clean, atomic commit messages detailing *what* was done and *why*.
3. Push the feature branch to the remote repository.
4. Open a Pull Request.
5. Post a comment on the Basecamp card containing a brief summary of the solution and a link to the PR.
6. Move the card to **Under Review**.

#### Step 6: Merge & Close
1. Teammates review the Pull Request and offer feedback.
2. Once the PR is approved, it is merged into the main branch.
3. The card is moved to **Done** (and eventually archived).

---

## 5. Basecamp as a Project Knowledge Base

Beyond progress tracking, Basecamp acts as the central knowledge graph for our system. Developers and agents use it to document and retrieve high-level system state:

### A. Architecture Decision Records (ADRs)
* Major architectural decisions, design patterns, or database modeling choices must be documented in **Basecamp Docs** (within the project's **Vault**).
* ADRs must be assigned a unique ID (e.g., `ADR-004: Event-Driven Auditing`).

### B. Discussions & RFCs
* When a design requires open discussion, an Implementer posts a message on the **Basecamp Message Board** labeled as an RFC (Request for Comments).
* Human team members and AI agents participate in the comment thread to brainstorm, resolve design trade-offs, and reach consensus before code is written.

### C. Contextual Linking
* Every card in **Up Next** that depends on a specific design pattern must link to the corresponding ADR in its description.
* Conversely, once an ADR or discussion is closed with a consensus, the concluding message or document must link back to the resulting Basecamp card(s).

This bi-directional linking guarantees that human developers and agents have immediate, rich context for *every single line of code* they are asked to write.
