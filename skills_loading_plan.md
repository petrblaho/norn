# Norn Dynamic Skills Loading Plan (Official Agent Skills Spec)

This document outlines the architecture and implementation plan for adding native **Agent Skills** support to Norn, conforming exactly to the specification and guidelines of [Agent Skills (agentskills.io)](https://agentskills.io/client-implementation/adding-skills-support).

---

## 1. Core Principle: Progressive Disclosure

To keep base prompts lean, minimize token usage, and scale to dozens of installed skills, we follow the **Three-Tier Progressive Disclosure** loading strategy:

| Tier | What's loaded | When | Token Cost |
| :--- | :--- | :--- | :--- |
| **Tier 1: Catalog** | Skill `name` and `description` | Session start | ~50-100 tokens per skill |
| **Tier 2: Instructions** | Full `SKILL.md` body content | When the skill is activated | <5000 tokens (on demand) |
| **Tier 3: Resources** | Supporting files, scripts, and assets | When referenced by instructions | Varies (as needed) |

The LLM is shown the *Catalog* of available skills upfront. When the LLM determines a skill is relevant to the task, it calls a dedicated tool (`activate_skill`) to load the full instructions and list supporting resources.

---

## 2. Step 1: Discover Skills

### Scanning Scopes
Norn will scan for skills in both project-level and user-level scopes, checking both client-native and cross-client `.agents/skills/` directories:

1. **Project Scope (High Precedence):**
   - `<workspace_root>/.norn/skills/` (Native)
   - `<workspace_root>/.agents/skills/` (Cross-client convention)
2. **User Scope (Low Precedence):**
   - `~/.norn/skills/` (Native)
   - `~/.agents/skills/` (Cross-client convention)

### Scanning Rules
- Scan for subdirectories containing a file named exactly `SKILL.md`.
- Exclude noise folders: `.git/`, `node_modules/`, `build/`, `tmp/`.
- Limit directory traversal to a depth of 5 levels and max 1000 folders to avoid performance issues in large repos.

### Name Collisions
- **Project-level skills override user-level skills** of the same name.
- When a collision occurs, Norn will log a warning indicating that the user-level skill was shadowed by the project-level skill.

---

## 3. Step 2: Parse `SKILL.md` Files

A skill file is parsed into two parts: YAML frontmatter and a Markdown body.

### Robust and Lenient Parsing
- **Frontmatter Extraction:** Located between the first `---` and second `---`. Everything after the second `---` is the body content.
- **Handling Malformed YAML:** Standard YAML parsers throw errors on unquoted colons in values (e.g., `description: Use this when: handling PDFs`). Norn will handle this gracefully:
  - If standard YAML parsing fails, Norn will pre-process the frontmatter lines (such as quoting unquoted values with secondary colons) or fallback to simple regex key-value extraction for `name` and `description`.
- **Validation Rules:**
  - `name`: Must exist. Warn if it doesn't match the parent directory name, but load anyway.
  - `description`: Must exist. If missing, skip the skill entirely (as a description is required for Tier 1 disclosure).
  - Diagnostic logging: Warn on formatting discrepancies but keep loading the skill if possible.

---

## 4. Step 3: Disclose Available Skills (Tier 1)

At session startup, we compile a compact **Skill Catalog** and inject it into the system prompt.

### Format
We use an XML structure which LLMs parse with high fidelity:

```xml
<available_skills>
  <skill>
    <name>basecamp</name>
    <description>Interact with Basecamp via the Basecamp CLI. Use for ANY Basecamp question or action.</description>
    <location>/path/to/workspace/.agents/skills/basecamp/SKILL.md</location>
  </skill>
</available_skills>
```

We append instructions explaining how the model can activate these skills:
> *You have access to specialized skills listed in `<available_skills>`. If a skill is relevant to the user's task, you MUST activate it first to see its complete instructions and resources. To activate a skill, call the `activate_skill` tool with its name.*

---

## 5. Step 4: Activate Skills (Tier 2 & 3)

### The `activate_skill` Tool
We will register a standard Norn tool:
- **Name:** `activate_skill`
- **Description:** `"Activate an available skill by name to load its complete, detailed instructions and list bundled resources."`
- **Capabilities required:** `[:sys_read]`
- **Arguments:**
  - `name`: `string` (required)

### Execution and Structured Wrapping
When the model invokes `activate_skill(name: "basecamp")`:
1. Find the skill in the registry.
2. If found, mark it as active for the current session (making it sticky in the system prompt for subsequent turns to prevent context compression loss).
3. Scan the skill's base directory for supporting resources (any file in the folder other than `SKILL.md`, e.g. `scripts/evaluate.py`).
4. Return a structured XML response containing the full instructions and the list of available files/resources:

```xml
<activated_skill name="basecamp">
  <instructions>
    [Markdown content of SKILL.md body...]
  </instructions>
  <resources>
    <file>scripts/evaluate.py</file>
  </resources>
</activated_skill>
```

---

## 6. Step 5: Manage Context & Session State

- **Deduplication:** Avoid double-activation or duplicate injection in the system prompt. If already active, the tool simply returns the instructions again without double-appending.
- **System Prompt Compilation:**
  - `Norn::Mode#compile_system_prompt` will dynamically query the registry for any activated skills in the session.
  - Active skill bodies are appended as a designated system prompt section:
    ```
    ACTIVE SKILLS INSTRUCTIONS:
    === basecamp ===
    [Instructions body...]
    ```

---

## 7. Interactive / Human Enhancements

We will add a new Slash Command to the interactive REPL:
- **`/skills`**:
  - `bare`: Lists all available skills discovered in the current workspace/user scopes, showing which ones are currently activated.
  - `/skills activate <name>`: Explicitly activates a skill on behalf of the human operator.

---

## 8. Development Implementation Roadmap

1. **`Norn::Skill` Model (`lib/norn/skill.rb`):** Frontmatter parsing, YAML safety, and trigger matching.
2. **`Norn::SkillRegistry` (`lib/norn/skill_registry.rb`):** In-memory storage, active-tracking, thread-safety, and catalog generation.
3. **`Norn::SkillLoader` (`lib/norn/skill_loader.rb`):** File discovery across project and home scopes, collision handling.
4. **Tool Registration (`plugins/activate_skill/plugin.rb`):** Register the `activate_skill` tool.
5. **Mode Integration (`lib/norn/mode.rb`):** Catalog disclosure & dynamic instruction appending.
6. **Slash Commands Integration (`plugins/slash_commands/plugin.rb`):** Add the `/skills` command.
7. **Comprehensive Unit & Integration Testing (`spec/norn/skills_spec.rb`):** Testing discovery, parsing, validation, and execution.
