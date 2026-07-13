# Architectural Plan: Collapsible Terminal Outputs in Norn

This document outlines the design, technical constraints, and implementation options for introducing collapsible/expandable output blocks in the Norn CLI interface (e.g. for long tool execution results, file diffs, or verbose LLM responses).

---

## 1. Technical Constraints of Terminal Streams

Standard terminal scrollback operates as a downward, write-only stream of characters. This imposes strict physical limits on any interactive inline folding (expand/collapse) system:

* **Viewport Bounds:** Toggling states inline via cursor navigation codes (e.g. `\e[A` to move up, `\e[K` to clear line) works perfectly if the text fits within the current viewport height.
* **The Scrollback Barrier:** If an expanded content block is taller than the terminal window height, the terminal will scroll. Once lines scroll past the top viewport boundary, they enter the terminal emulator's native history buffer. Standard ANSI cursor movement codes **cannot** scroll the terminal frame back down or overwrite lines above the viewport.
* **Residual Clutter:** Collapsing a scrolled block can leave truncated, orphaned text at the top of the viewport.

---

## 2. Implementation Paradigms

We have identified three distinct approaches to handle this feature, ordered from lowest complexity (inline toggle) to highest capability (full screen / mouse events).

### Approach A: Inline Accordion Toggle (Keyboard Driven)
This paradigm renders a toggleable header inline inside the standard stdout stream. It uses `io/console` to intercept keystrokes in raw mode.

* **Collapsed View:**
  ```text
  ▶ [Space] Expand: file_read spec/norn/errors_spec.rb (95 lines)
  ```
* **Expanded View:**
  ```text
  ▼ [Space] Collapse: file_read spec/norn/errors_spec.rb (95 lines)
  -------------------------------------------------------------
  require "spec_helper"
  require "norn/errors"
  ...
  -------------------------------------------------------------
  ```

#### Technical Design:
1. **Interactive Loop:** The component yields the collapsed state. It intercepts stdin using `IO#getch`.
2. **Expansion:** Upon pressing a trigger (like Space or Enter), the header line is cleared, the expanded text block is output, and the state flips.
3. **Collapsing:** On a toggle-back keypress, the component calculates the height of the expanded content (`height = content.split("\n").size + boundaries`). It prints `\e[A` (cursor up) `height` times, clears each line with `\e[K`, and re-writes the collapsed header.
4. **Safety Guard:** If `height > terminal_height`, it disables inline collapse and automatically falls back to an static/scrolled display to prevent screen corruption.

---

### Approach B: Interactive Sub-Viewport / Custom Pager
For massive outputs (e.g., > 30 lines), we bypass inline stream rendering and draw the content inside an interactive window overlay.

* **Behavior:**
  - When a tool output exceeds a configurable length, Norn pauses and prompts: `[Press Enter to view output in pager]`.
  - It opens a viewport (either full-screen or half-screen via terminal boundary calculation).
  - The user scrolls using Up/Down arrow keys or PageUp/PageDown.
  - Pressing `q` or `Esc` closes the viewport, restores the cursor position, and prints a compact inline reference (e.g. `[Tool Output: file_read spec/norn/errors_spec.rb - 512 lines (viewed)]`).

#### Technical Design:
- Uses `IO#getch` to capture arrows (`\e[A` / `\e[B`).
- Erases and redraws only the viewport segment on each scroll action, ensuring no content ever overflows the viewport bounds.

---

### Approach C: XTerm Mouse Click Tracking
Modern terminal emulators (iTerm2, Windows Terminal, Kitty, Alacritty) support mouse tracking protocol.

* **Technical Design:**
  - Write `\e[?1000h` to stdout to enable mouse-click reporting.
  - When the user clicks inside the terminal window, the terminal sends a specialized escape sequence to stdin: `\e[M<code><x><y>`.
  - Norn's input loop decodes the click coordinates, translates them to the line number, checks if it falls on a collapsible header, and toggles the state!
  - Write `\e[?1000l` on shutdown to disable mouse tracking.

---

## 3. Recommended Roadmap

1. **Phase 1 (Prototype Approach A):** Build a utility class `Norn::UI::Collapsible` that takes a title and a block of text, rendering a keyboard-interactive toggle if the height fits within the screen height.
2. **Phase 2 (Fallback Pager):** If the text is too long, route it to `Approach B` (a simple scrollable pager).
3. **Phase 3 (Integration):** Register this utility in the rendering pipeline of `Norn::Mode` so that tool execution logs can be optionally folded automatically if configured by the user (e.g., `setting :fold_tool_outputs, default: true`).
