---
name: flutter-generate-documentation
description: >
  Generates and maintains project documentation using the 7-document framework: project-overview, requirements, project-structure, tech-stack, features, implementation, and user-flow. Use this skill when creating documentation for a new project, updating existing docs after major changes, onboarding new team members, or preparing delivery documentation. Triggers on 'document project', 'create docs', 'onboarding docs', 'project overview', 'tech stack doc', 'delivery documentation', or any request to produce structured project knowledge.
commands:
  - generate-docs
inputs:
  - name: action
    description: Action to perform (generate, update, audit). "generate" creates documentation from scratch using the 7-document framework, "update" refreshes specific documents after project changes, "audit" checks existing documentation for completeness, outdated sections, or missing documents.
    required: true
  - name: target
    description: Path to the docs directory or project root where documentation will be generated (e.g. docs/ for generate, . for audit).
    required: true
  - name: documents
    description: Comma-separated list of documents to generate or update (project-overview, requirements, project-structure, tech-stack, features, implementation, user-flow, index, all). Defaults to all.
    required: false
  - name: audience
    description: Primary audience for the documentation (developers, architects, stakeholders, all). Adjusts detail level and focus.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.0"
---

# Project Documentation

Generates structured project documentation using the 7-document framework.
Each document serves a specific purpose and audience.

## The 7-Document Framework

| # | Document | Purpose | Audience |
|---|----------|---------|----------|
| 1 | `index.md` | Navigation hub — links to all docs, reading paths by role | Everyone |
| 2 | `project-overview.md` | Vision, objectives, problems solved, current state | Everyone |
| 3 | `requirements.md` | Functional, technical, and quality requirements | Architects, Developers |
| 4 | `project-structure.md` | Folder organization, module map, dependency graph | Everyone |
| 5 | `tech-stack.md` | Technologies, versions, justification for each choice | Developers |
| 6 | `features.md` | Feature catalog with status, ownership, and links | Users, Developers |
| 7 | `implementation.md` | Development guide, standards, contribution process | Contributors |
| 8 | `user-flow.md` | Key user journeys and interaction flows | Users, Stakeholders |

---

## When to Generate

| Trigger | Documents to generate |
|---|---|
| New project kickoff | All 7 + index |
| Feature complete (delivery) | project-overview (update), features (add entry), implementation (update) |
| Architecture change | project-structure, tech-stack, requirements |
| New team member onboarding | Audit all — ensure completeness |
| Sprint/milestone delivery | features (update status), implementation (update) |
| Tech stack migration | tech-stack, implementation, requirements |

---

## Document Generation Rules

### General Rules
- Write in the project's primary language (Spanish or English — match the team)
- Use concrete data from the actual codebase — never placeholder text
- Include Mermaid diagrams where they add clarity (architecture, flows)
- Link between documents — never duplicate content
- Date each document with `last_updated` in frontmatter

### Per Document

**project-overview.md**
- Vision statement (1–2 sentences)
- 3–5 concrete objectives
- Problems solved (with before/after)
- Current state table (component → status → coverage)

**requirements.md**
- Functional requirements grouped by feature/module
- Non-functional requirements (performance, security, scalability)
- Quality attributes with measurable targets
- Constraints and assumptions

**project-structure.md**
- Full directory tree (annotated)
- Module dependency diagram (Mermaid)
- Naming conventions table
- "Where does X go?" quick reference

**tech-stack.md**
- Every dependency with version and justification
- Decision records for key choices (why BLoC over Riverpod, why Drift over Isar)
- Minimum SDK/platform versions
- Dev tools and their purpose

**features.md**
- Feature catalog table (name, status, owner, link)
- Feature descriptions with acceptance criteria summary
- Roadmap / planned features

**implementation.md**
- Development environment setup
- Build and run commands
- Coding standards summary (link to full standard)
- Contribution workflow (branch → PR → review → merge)
- CI/CD pipeline overview

**user-flow.md**
- Key user journeys as step-by-step flows
- Mermaid sequence diagrams for complex flows
- Entry points and navigation map
- Error/edge case handling per flow

---

## Reading Paths by Role

### New Developer
1. project-overview → 2. project-structure → 3. implementation → 4. features

### Architect / Tech Lead
1. project-overview → 2. requirements → 3. project-structure → 4. tech-stack

### Stakeholder / Product Owner
1. project-overview → 2. features → 3. user-flow

### QA / Tester
1. features → 2. user-flow → 3. requirements

---

## Quick Wins Checklist

- [ ] All 7 documents + index exist
- [ ] `index.md` has reading paths for each role
- [ ] `project-structure.md` matches actual folder structure
- [ ] `tech-stack.md` versions match `pubspec.yaml` / `package.json`
- [ ] `features.md` reflects current feature status (not outdated)
- [ ] No placeholder text ("TBD", "TODO", "Lorem ipsum")
- [ ] Cross-links between documents work (no broken links)
- [ ] Mermaid diagrams render correctly
- [ ] `last_updated` date is current

## Templates

Ready-to-use templates for each document:

- `assets/index.md` — Navigation hub template
- `assets/project-overview.md` — Project overview template
- `assets/requirements.md` — Requirements template
- `assets/project-structure.md` — Structure template
- `assets/tech-stack.md` — Tech stack template
- `assets/features.md` — Features catalog template
- `assets/implementation.md` — Implementation guide template
- `assets/user-flow.md` — User flow template
