# Design Language — VS Code-Inspired Dark Workbench

## Intent

A dark developer workspace with quiet chrome, slightly lifted content planes, restrained borders, and one strong blue accent. The interface must feel dense, calm, and operational rather than brand-heavy or decorative.

## Principles

- Use neutral surfaces first; use color only for state and priority.
- Keep chrome darker than content.
- Separate areas with low-contrast borders, not shadows.
- Use blue for focus, active selection, badges, and primary CTA.
- Avoid gradients, glows, glassmorphism, and oversized radii.
- Let AI panels inherit the same workbench language as the rest of the product.

## Typography

### UI font
- Primary: Inter, Segoe UI, system-ui, sans-serif
- Weights: 400, 500, 600
- Sizes:
  - 12px: metadata, counts, helper labels
  - 13px: tree items, side panels, tabs
  - 14px: buttons, inputs, command rows
  - 15px: section titles only if needed

### Code font
- Cascadia Code, JetBrains Mono, Consolas, monospace
- Sizes:
  - 12px–13px for inline/code chips
  - 14px–15px for editor/code areas
- Line-height: 1.45–1.6

### Rhythm
- Letter spacing: normal
- Avoid display fonts
- Use weight and color before increasing size

## Core color tokens

### Neutrals
- `bg.app` = `#181818`
- `bg.chrome` = `#181818`
- `bg.canvas` = `#1F1F1F`
- `bg.elevated` = `#222222`
- `bg.input` = `#313131`
- `bg.input-hover` = `#3C3C3C`

### Borders
- `border.subtle` = `#2B2B2B`
- `border.default` = `#3C3C3C`
- `border.softAlpha` = `#FFFFFF12`
- `border.group` = `#FFFFFF17`

### Text
- `fg.default` = `#CCCCCC`
- `fg.strong` = `#FFFFFF`
- `fg.muted` = `#9D9D9D`
- `fg.inactive` = `#868686`
- `fg.placeholder` = `#989898`

### Accent
- `accent.primary` = `#0078D4`
- `accent.primaryHover` = `#026EC1`
- `accent.secondary` = `#2488DB`
- `accent.secondaryAlpha` = `#2489DB82`
- `accent.link` = `#4DAAFC`
- `accent.linkActive` = `#4DAAFC`

### Status
- `status.error` = `#F85149`
- `status.success` = `#2EA043`
- `status.warning` = `#9E6A03`
- `status.warningSoft` = `#BB800966`
- `status.info` = `#0078D4`

### AI / chat
- `ai.commandBg` = `#26477866`
- `ai.commandFg` = `#85B6FF`
- `ai.editedFileFg` = `#E2C08D`

## Surface map

- App frame: `bg.app`
- Activity bar: `bg.chrome`
- Sidebar: `bg.chrome`
- Editor header / tab strip: `bg.chrome`
- Active editor: `bg.canvas`
- Panel / terminal region: `bg.chrome`
- Menus / quick input / popovers: `bg.elevated`
- Inputs / dropdown controls: `bg.input`

## Component language

### Activity bar
- Background: `bg.chrome`
- Active icon: `fg.default`
- Inactive icon: `fg.inactive`
- Active indicator: 2px line in `accent.primary`
- Border against sidebar: `border.subtle`

### Sidebar
- Background: `bg.chrome`
- Text: `fg.default`
- Section headers: same background as sidebar
- Dividers: `border.subtle`
- Selected row: use low-alpha accent fill or subtle canvas contrast; never a bright solid tile

### Tabs
- Strip background: `bg.chrome`
- Active tab background: `bg.canvas`
- Inactive tab background: `bg.chrome`
- Active top border: `accent.primary`
- Active label: `fg.strong`
- Inactive label: `fg.muted`
- Tab separator: `border.subtle`

### Editor
- Background: `bg.canvas`
- Text: `fg.default`
- Gutter active line number: `fg.default`
- Gutter inactive line number: `#6E7681`
- Find match / transient highlight: `status.warning` or `status.warningSoft`

### Buttons
- Primary:
  - Background: `accent.primary`
  - Text: `fg.strong`
  - Hover: `accent.primaryHover`
  - Border: `border.softAlpha`
- Secondary:
  - Background: `bg.input`
  - Text: `fg.default`
  - Hover: `bg.input-hover`

### Inputs
- Background: `bg.input`
- Border: `border.default`
- Text: `fg.default`
- Placeholder: `fg.placeholder`
- Active/focus border: `accent.secondary`
- Active/focus fill: optionally `accent.secondaryAlpha` for selected tokens only

### Panels
- Background: `bg.chrome`
- Border: `border.subtle`
- Active title underline: `accent.primary`
- Inactive title: `fg.muted`

### Menus / command palette
- Background: `bg.elevated`
- Text: `fg.default`
- Group border: `border.default`
- Selected row: `accent.primary`
- Selected row text: `fg.strong`

## AI extension panel language

### Goal
The right-side AI panel for Copilot, Cursor-style assistant, or Claude Code-style tooling must feel native to the workbench, not like an embedded consumer chat app.

### Layout
- Docked right panel width: 320px–420px
- Header height: 40px–48px
- Conversation area on `bg.canvas` or `bg.chrome`
- Composer pinned to bottom on `bg.chrome`
- Use `border.subtle` between header, thread, and composer

### Message styling
- Assistant/user bubbles should be understated:
  - Preferred: flat rows or lightly tinted blocks
  - Avoid fully rounded speech bubbles
- Assistant row background: transparent or subtle `bg.canvas`
- User row background: optional `bg.input`
- Code blocks inside chat: `bg.input` with `border.default`
- Slash commands: `ai.commandBg` + `ai.commandFg`
- Edited file mention / patch badge: `ai.editedFileFg`

### AI states
- Active model badge: outline with `accent.primary`
- Streaming cursor/caret: `accent.primary`
- Suggested action chips: `bg.input` with hover `bg.input-hover`
- Approve/apply patch CTA: primary button
- Risk/destructive action: `status.error`
- Success/applied patch: `status.success`

### Extension affordances
- Tree/list items for chats, contexts, files, symbols should match sidebar rows
- Inline citations, file refs, terminal refs, and diff refs should appear as compact pills on `bg.input`
- Tool execution blocks (terminal, git, file edit, search) should use monospace labels and neutral frames
- Diff previews should use:
  - added = `status.success`
  - removed = `status.error`
  - modified = `status.info`

## Spacing

- Base unit: 4px
- Control heights:
  - compact row: 28px
  - default row: 32px
  - input/button: 32px–36px
- Padding:
  - panels/cards: 8px–12px
  - side rows: 6px 10px
  - tab labels: 8px 12px

## Radius and effects

- Radius scale:
  - 0px for structural panes
  - 4px for inputs, menus, chips
  - 6px max for buttons and small cards
- Shadows should be minimal; prefer border separation
- No glow effects on active items

## Iconography

### Icon system
- Primary pack: Codicons
- Role: default workbench/product icon language
- Use for: activity bar, panel actions, tree views, status indicators, inline commands, editor affordances, AI tool actions
- Do not mix multiple unrelated icon packs in the same workbench shell

### Icon categories
- Product/workbench icons: Codicons or a product-icon-theme-compatible mapping
- File icons: separate file-icon-theme layer
- Extension custom icons: only when Codicons do not cover the action

### Styling rules
- Default size: 16px
- Dense inline size: 14px
- Large toolbar/icon button size: 16px–18px
- Stroke/visual weight should stay visually consistent with Codicons
- Use `fg.muted` for inactive icons, `fg.default` for standard actions, `fg.strong` for active/hover states
- Use `accent.primary` only for selected/active semantic state, not as the default icon color
- Destructive icons use `status.error`
- Success/apply icons use `status.success`

### Placement rules
- Activity bar icons: monochrome, centered, no filled background tile
- Sidebar/tree icons: small, aligned to text baseline, secondary to labels
- Panel header actions: icon-only allowed if tooltip and accessible label exist
- Inline AI actions: keep icons neutral unless stateful
- Avoid decorative icons in cards, banners, and empty-state circles

### AI panel icon language
Use Codicons for:
- chat/session history
- new chat / compose
- attach file / context
- terminal/tool execution
- diff/apply/revert
- model/settings
- stop/refresh/retry
- warning/error/success states

### Accessibility
- Every icon-only button must have an accessible label
- Hover-only meaning is not enough; state must also be shown by text, border, or color
- Keep touch/click targets at least 32px desktop, 40px–44px touch

## Exact default fonts (VS Code)

### UI (workbench) font
- Use the system UI font:
  - Windows: Segoe UI, Segoe WPC, sans-serif
  - macOS: SF Pro, -apple-system, sans-serif
  - Linux: Ubuntu, system-ui, sans-serif
- CSS:
  font-family: system-ui, -apple-system, Segoe UI, SF Pro, Ubuntu, sans-serif;

### Editor + terminal font
- Use the first monospace on the system:
  - Windows: Consolas (or Cascadia Code if installed)
  - macOS: Menlo (or Monaco on older macOS)
  - Linux: Ubuntu Mono or first monospace found
- CSS:
  font-family: Monaco, Menlo, Consolas, "Droid Sans Mono", "Ubuntu Mono", monospace;

### Density
- UI text: 12px–14px
- Editor text: 13px–15px
- Line-height: 1.45–1.6 for code

## Implementation notes

- Preserve semantic token names even if the framework changes.
- Map design tokens to CSS variables, Tailwind theme tokens, styled-system tokens, Flutter theme extensions, or design tokens JSON.
- Keep editor/content and shell/chrome as separate surface families.
- AI panels should reuse the same tokens, plus only a tiny AI-specific layer for commands and patch state.

