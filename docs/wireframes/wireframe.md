# Mobile IDE / Agent App — Wireframe Documentation

VS Code-inspired Dark Workbench design language · full-screen layouts

---

## Design Tokens

### Surfaces
- `bg.app` / `bg.chrome` = `#181818`
- `bg.canvas` = `#1F1F1F`
- `bg.elevated` = `#222222`
- `bg.input` = `#313131`
- `bg.input-hover` = `#3C3C3C`

### Borders
- `border.subtle` = `#2B2B2B`
- `border.default` = `#3C3C3C`

### Text
- `fg.default` = `#CCCCCC`
- `fg.strong` = `#FFFFFF`
- `fg.muted` = `#9D9D9D`
- `fg.inactive` = `#868686` / `#6E7681`
- `fg.placeholder` = `#989898`

### Accent
- `accent.primary` = `#0078D4`
- `accent.primary-hover` = `#026EC1`
- `accent.secondary` = `#2488DB`
- `accent.link` = `#4DAAFC`

### Status
- `status.error` = `#F85149`
- `status.success` = `#2EA043`
- `status.warning` = `#9E6A03`

### AI / Chat
- `ai.commandBg` = `#26477866`
- `ai.commandFg` = `#85B6FF`
- `ai.editedFileFg` = `#E2C08D`

### Fonts
- UI: `system-ui, -apple-system, "Segoe UI", "SF Pro", Ubuntu, sans-serif`
- Mono: `Monaco, Menlo, Consolas, "Droid Sans Mono", "Ubuntu Mono", monospace`

### Icons
- Codicons (`vscode-codicons`)

---

## Screen 1 — Main / Search & Agent Chat Screen

### Design
- Surfaces: app frame & chrome use `bg.chrome #181818`; the conversation/results area uses `bg.canvas #1F1F1F`; cards/responses use `bg.elevated #222222` with `border.subtle`.
- Header: ☰ hamburger (Codicon menu) + search input on `bg.input #313131` with `border.default`; close (x) and stop (square) icons in `fg.muted`.
- **File search / grep toggle:** active segment uses `accent.primary #0078D4` fill with `fg.strong` text; inactive segment uses `bg.input`.
- Result list styled as sidebar tree rows (13px workbench UI / monospace for paths), `fg.default` text, active-line indicator bar in `accent.primary`, line-range badge in `fg.inactive`.
- **Cursor responses panel:** each block follows AI panel language — file-edit badges use `ai.editedFileFg #E2C08D`; slash/tool-command blocks use `ai.commandBg #26477866` + `ai.commandFg #85B6FF` in monospace; streaming caret in `accent.primary`.
- **Composer (matches reference):** rounded 8px card on `bg.elevated #222222`, `border.default`, placeholder "Plan, Build, / for skills, @ for context" in `fg.placeholder #989898`. Footer row inside composer holds an **∞** (context/length) pill, an **Auto ⌄** model selector, and attach/mic icons (Codicons, `fg.muted`, 16px).
- Bottom nav tabs: active tab gets `bg.canvas` background + 2px top border in `accent.primary` + `fg.strong` label; inactive tabs sit on `bg.chrome` with `fg.default`.

### Working
- Full-screen layout. Header row contains: ☰ hamburger (opens the slide-in menu — see Screens 4 & 5), the Search Bar, and Close / Stop controls at top-right (**Stop** halts an in-progress agent action).
- `Ctrl+A` performs "select all" within search results.
- Below the search bar is a File search / grep mode toggle.
- Search results render in a GitHub-like file list view, supporting `.cpp` file display. Long-press makes entries selectable, and a selection range can be defined.
- Below results is a Cursor responses panel — the main flexible area showing AI/agent responses tied to cursor context, with a vertical scroll indicator on the right edge.
- The composer pinned above bottom navigation is the agent chat input (replaces the original "Type message" + send affordance).
- Bottom navigation has three full-width tabs: **Projects**, **Terminals**, **Remote** (consistent across all screens).
- **Behavior — Projects tab, when searching:** the agent window collapses to just the message/composer; the search/results area takes ~60vh.
- **Behavior — when referencing files:** when in file-select (incl. full-file select on top), the agent panel takes ~60% and only the search bar stays visible at top.
- The `@` file-reference selector still works inside agent chat (distinct from the cursor-select-vs-reference mechanism described above).

---

## Screen 2 — Terminals Tab

### Design
- Terminal output region: `bg.canvas #1F1F1F`, editor monospace (Consolas / Ubuntu Mono) 13px, `fg.default` for normal text, success/output lines in `status.success #2EA043`, blinking cursor block in `accent.primary`.
- **Selected Terminal bar:** `bg.elevated #222222` with `border.default`; live status dot in `status.success`; label in `fg.strong`; **+** (new) and trash (delete) Codicons in `fg.muted`, 16px.
- **Terminal list:** alternating row backgrounds (`bg.canvas` / `bg.chrome`) matching sidebar tree styling, status dot per session, scrollbar thumb in `bg.input`.
- Composer is hidden/dimmed on this tab (dashed placeholder in `border.subtle` / `fg.inactive`) — not part of the terminal workflow.
- Bottom nav unchanged: active tab indicated with 2px `accent.primary` top border + `bg.canvas` fill.

### Working
- Same header chrome: ☰ hamburger top-left, "Terminals" title.
- Main pane is a live terminal output area showing a command prompt (`C:/ --->`), demonstrated with `echo "I'm the best"`.
- Below the output is a Selected Terminal bar with a **+** (new terminal) and trash (delete terminal) action.
- A scrollable terminal list appears below the selected-terminal bar, allowing switching between multiple open terminal sessions.
- Bottom navigation: **Projects | Terminals (active) | Remote**.
- **SSH behavior:** terminals support SSH, with VS-Code-like add/delete controls for managing connections. After establishing an SSH session, the terminal automatically navigates (`cd`) into the current project directory.

---

## Screen 3 — Remote Tab — Screen + Controls (Trackpad tab vs Keyboard tab)

### Design
- **Screen with pointer (top ~50%):** rendered on near-black `#0F0F0F` (deeper than canvas, to distinguish remote framebuffer from local chrome); remote window chrome mocked with `bg.canvas` rectangles and an `ai.commandBg` tinted panel; cursor arrow outlined in `accent.primary`.
- **Controls (bottom ~50%):** panel on `bg.canvas #1F1F1F` with `border.subtle`.
- **Trackpad tab (left):** trackpad surface fills the panel; **Left** / **Right** click buttons styled as secondary buttons (`bg.input` / `border.default`, hover `bg.input-hover`).
- **Keyboard tab (right):** reference text block in `fg.default`, then three key buttons (`Fn`, `$#` monospace, `123`) styled as secondary buttons on `bg.input`.
- **Action icons next to keys:** `x` (cancel staged input) in `status.error #F85149`; `+` (compose/add to combo) in `fg.muted`; `✓` (send keystroke to remote) in `status.success #2EA043` — mirrors the diff-preview color convention (added/success = green, destructive = red).
- **Sub-tabs (Trackpad | Keyboard):** active tab gets 2px `accent.primary` top border + `fg.strong` label, matching the main tab-strip pattern.

### Working
- Same header chrome: ☰ hamburger top-left, "Remote" title.
- Body splits roughly: **top ~50%** = "Screen with pointer" (the remote desktop/device view, live cursor shown over it), **bottom ~50%** = Controls.
- **Controls area has two sub-tabs at its bottom edge: Trackpad and Keyboard.** Only one is shown at a time, swapping the content of the controls panel above the tabs:
  - **Trackpad tab (left wireframe):** shows the Trackpad area plus **Left** / **Right** click buttons.
  - **Keyboard tab (right wireframe):** shows the three special-key categories and their buttons:
    - `Fn` — special keyboard keys; Fn acts as a shift/modifier layer, etc.
    - `$#` — special characters
    - `123` — number row
    
    Alongside the three key buttons are three actions: `x`, `+`, `✓`.
- **Input trigger flow:** in either tab, interactions are staged (typed/clicked/composed). **x** cancels the staged input without sending. **+** adds/builds up the staged key combination (e.g. composing a modifier + key combo). Pressing **✓ (tick)** sends the composed input as actual keystroke/input events to the remote session.
- Same bottom nav: **Projects | Terminals | Remote (active)**.

---

## Screen 4 — Hamburger Menu — Workspace Panel (FTP Navigator)

### Design
- Full-screen panel opened via hamburger; top tab strip follows tab-strip rules: active **Workspace** tab gets `bg.canvas` fill + 2px `accent.primary` top border + `fg.strong` label; inactive **Git** tab on `bg.chrome` with `fg.muted`.
- `x` close icon top-right in `fg.muted`; "git graph" shortcut icon rendered in `ai.commandFg #85B6FF` to hint at AI/graph affordance.
- **Current workspace selector:** dropdown styled as input — `bg.input #313131`, `border.default`, chevron in `fg.muted`.
- **Recent items list:** sidebar-row styling — alternating `bg.canvas`/`bg.chrome`, active/selected row marked with a small `accent.primary` dot.
- **FTP Navigator:** tree view on `bg.canvas`, monospace paths in `fg.default`, folders tinted with `ai.editedFileFg #E2C08D` for emphasis, files in `fg.muted`, scrollbar thumb in `bg.input`.
- **FTP Path field:** `bg.input` input showing the active remote path in monospace.
- **Action buttons:** `Select` and `+ New folder` are secondary buttons (`bg.input`/`border.default`, hover `bg.input-hover`); `+ New file` is the primary CTA in `accent.primary` with `fg.strong` text.

### Working
- This is the full-screen panel opened by the ☰ hamburger from any screen — it overlays/replaces the main view. Two top tabs: **Workspace** (active here) and **Git** (Screen 5).
- `x` (close) button top-right closes the panel and returns to the previous screen. A small "git graph" indicator sits near the top-right corner as a quick-access shortcut into the Git tab's commit graph.
- **Current workspace ▾** — dropdown selector to switch between workspaces.
- Below the selector: a list of recent/pinned workspace items.
- **FTP Navigator** — main scrollable area showing the remote file/folder tree for the connected FTP/remote target.
- Bottom action row:
  - **FTP Path** — input field showing/editing the current remote path.
  - **Select** — choose/confirm the FTP path.
  - **+ New folder** — create folder at current FTP path.
  - **+ New file** — create file at current FTP path.
- Bottom nav (Projects | Terminals | Remote) remains visible/consistent even while this panel is open.

---

## Screen 5 — Hamburger Menu — Git Tab

### Design
- Tab strip: **Git** active (`bg.canvas` + 2px `accent.primary` top border + `fg.strong`); **Workspace** inactive (`bg.chrome` + `fg.muted`).
- **Commit message input:** `bg.input`/`border.default`, placeholder in `fg.placeholder`; **Commit** is the primary CTA (`accent.primary` + `fg.strong` + check icon).
- **Quick actions row** (Add / Stash / Discard / Commit / Sync): secondary buttons on `bg.input`; **Discard** labeled in `status.error #F85149` to signal destructive action.
- **Changed files list:** each row uses git-status letter + monospace path; modified (**M**) rows tinted with `ai.commandBg` and path in `ai.editedFileFg #E2C08D`; added (**A**) in `status.success`; deleted (**D**) in `status.error` — following the diff-preview convention (added=success, removed=error, modified=info/edited).
- Each file row has a `+ ⏎` stage action in `fg.muted`; list sits on `bg.canvas` with a `bg.input` scrollbar thumb.
- **Command input:** rounded 6px field on `bg.input`, monospace placeholder, ⏎ to execute raw git commands.
- **Branch selector:** current branch shown in monospace on `bg.input` with chevron; **Select** is a primary CTA — pressing it triggers a branch switch.
- **Commit history:** vertical graph line in `border.default`; HEAD commit dot in `accent.primary`, other commits in `fg.inactive #6E7681`; subject text in `fg.default`, meta (hash/branch/time) in `fg.inactive` at 10px.

### Working
- Same full-screen hamburger panel as Screen 4, with the **Git** tab active (Workspace | **Git**).
- **Commit message input** (with ⏎ shortcut) next to a **✓ Commit** button.
- Quick git actions accessible from this view: `add`, `stash`, `discard`, `commit`, `sync`.
- **Changed files** — scrollable list of modified files, each with a **+ ⏎** action (stage file).
- **Command input** field (rounded, with ⏎ to execute) — allows running raw git commands.
- **Branch dropdown** ("Branch ▾") on the left and a **Select** button on the right; pressing Select on a chosen branch triggers a branch switch.
- **Commit history** — scrollable git log/graph (e.g., "some commit" + further entries).
- Same `x` close button top-right returns to the previous main screen; bottom nav remains consistent.