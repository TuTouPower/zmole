---
version: alpha
name: Zmole Quiet Utility
description: A calm, native-feeling macOS utility design system for high-trust cleanup, uninstall, optimization, disk analysis, and system status workflows.
colors:
  primary: "#1D1D1F"
  secondary: "#6E6E73"
  tertiary: "#0A7F68"
  neutral: "#F5F5F7"
  surface: "#FFFFFF"
  surface-raised: "#F8F8FA"
  surface-selected: "#E7F3F0"
  border: "#D2D2D7"
  separator: "#E5E5EA"
  on-tertiary: "#FFFFFF"
  success: "#0F703E"
  success-subtle: "#E7F4EC"
  warning: "#8A5700"
  warning-subtle: "#F8EEDD"
  error: "#C9182B"
  error-subtle: "#FBE8EA"
  info: "#1F64B2"
  info-subtle: "#E8F0FA"
  visualization-purple: "#7655D9"
  visualization-blue: "#2B74C8"
  visualization-teal: "#0A8F8C"
  dark-primary: "#F5F5F7"
  dark-secondary: "#A1A1A6"
  dark-tertiary: "#55D6B2"
  dark-neutral: "#2B2B2F"
  dark-surface: "#232326"
  dark-surface-raised: "#1D1D1F"
  dark-surface-selected: "#173A33"
  dark-border: "#48484A"
  dark-separator: "#38383A"
  dark-on-tertiary: "#102720"
typography:
  headline-display:
    fontFamily: "SF Pro Display"
    fontSize: 32px
    fontWeight: 700
    lineHeight: 1.12
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: "SF Pro Display"
    fontSize: 24px
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: -0.015em
  headline-md:
    fontFamily: "SF Pro Text"
    fontSize: 17px
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: "SF Pro Text"
    fontSize: 14px
    fontWeight: 600
    lineHeight: 1.35
  body-lg:
    fontFamily: "SF Pro Text"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.45
  body-md:
    fontFamily: "SF Pro Text"
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.4
  body-sm:
    fontFamily: "SF Pro Text"
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.4
  label-lg:
    fontFamily: "SF Pro Text"
    fontSize: 13px
    fontWeight: 600
    lineHeight: 1.2
  label-md:
    fontFamily: "SF Pro Text"
    fontSize: 11px
    fontWeight: 600
    lineHeight: 1.2
  label-sm:
    fontFamily: "SF Pro Text"
    fontSize: 10px
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: 0.04em
  data-md:
    fontFamily: "SF Mono"
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.35
  data-sm:
    fontFamily: "SF Mono"
    fontSize: 11px
    fontWeight: 400
    lineHeight: 1.35
rounded:
  none: 0px
  xs: 4px
  sm: 6px
  md: 8px
  lg: 10px
  xl: 12px
  window: 14px
  full: 9999px
spacing:
  xxs: 2px
  xs: 4px
  sm: 6px
  md: 8px
  lg: 12px
  xl: 16px
  2xl: 20px
  3xl: 24px
  4xl: 32px
  5xl: 40px
  6xl: 48px
components:
  window:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.primary}"
    rounded: "{rounded.window}"
  window-dark:
    backgroundColor: "{colors.dark-surface-raised}"
    textColor: "{colors.dark-primary}"
    rounded: "{rounded.window}"
  toolbar:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.primary}"
    height: 52px
  toolbar-dark:
    backgroundColor: "{colors.dark-surface-raised}"
    textColor: "{colors.dark-primary}"
    height: 52px
  content-surface:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary}"
    rounded: "{rounded.lg}"
  content-surface-dark:
    backgroundColor: "{colors.dark-surface}"
    textColor: "{colors.dark-primary}"
    rounded: "{rounded.lg}"
  secondary-surface:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.secondary}"
    rounded: "{rounded.md}"
  secondary-surface-dark:
    backgroundColor: "{colors.dark-neutral}"
    textColor: "{colors.dark-secondary}"
    rounded: "{rounded.md}"
  mode-control:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.secondary}"
    rounded: "{rounded.lg}"
    height: 34px
  mode-control-active:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary}"
    rounded: "{rounded.md}"
  mode-control-dark:
    backgroundColor: "{colors.dark-neutral}"
    textColor: "{colors.dark-secondary}"
    rounded: "{rounded.lg}"
    height: 34px
  mode-control-active-dark:
    backgroundColor: "{colors.dark-surface}"
    textColor: "{colors.dark-primary}"
    rounded: "{rounded.md}"
  button-primary:
    backgroundColor: "{colors.tertiary}"
    textColor: "{colors.on-tertiary}"
    rounded: "{rounded.md}"
    height: 30px
    padding: 10px
  button-primary-dark:
    backgroundColor: "{colors.dark-tertiary}"
    textColor: "{colors.dark-on-tertiary}"
    rounded: "{rounded.md}"
    height: 30px
    padding: 10px
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary}"
    rounded: "{rounded.md}"
    height: 30px
    padding: 10px
  button-secondary-dark:
    backgroundColor: "{colors.dark-surface}"
    textColor: "{colors.dark-primary}"
    rounded: "{rounded.md}"
    height: 30px
    padding: 10px
  button-destructive:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.error}"
    rounded: "{rounded.md}"
    height: 30px
    padding: 10px
  selection-shelf:
    backgroundColor: "{colors.surface-selected}"
    textColor: "{colors.primary}"
    rounded: "{rounded.none}"
    height: 42px
  selection-shelf-dark:
    backgroundColor: "{colors.dark-surface-selected}"
    textColor: "{colors.dark-primary}"
    height: 42px
  list-row:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary}"
    rounded: "{rounded.md}"
    height: 52px
  list-row-selected:
    backgroundColor: "{colors.surface-selected}"
    textColor: "{colors.primary}"
    rounded: "{rounded.md}"
  list-row-dark:
    backgroundColor: "{colors.dark-surface}"
    textColor: "{colors.dark-primary}"
    rounded: "{rounded.md}"
  list-row-selected-dark:
    backgroundColor: "{colors.dark-surface-selected}"
    textColor: "{colors.dark-primary}"
    rounded: "{rounded.md}"
  muted-label:
    backgroundColor: "transparent"
    textColor: "{colors.secondary}"
    typography: "{typography.body-sm}"
  muted-label-dark:
    backgroundColor: "transparent"
    textColor: "{colors.dark-secondary}"
    typography: "{typography.body-sm}"
  border-swatch:
    backgroundColor: "{colors.border}"
    textColor: "{colors.primary}"
    height: 1px
  separator-swatch:
    backgroundColor: "{colors.separator}"
    textColor: "{colors.primary}"
    height: 1px
  dark-border-swatch:
    backgroundColor: "{colors.dark-border}"
    textColor: "{colors.dark-primary}"
    height: 1px
  dark-separator-swatch:
    backgroundColor: "{colors.dark-separator}"
    textColor: "{colors.dark-primary}"
    height: 1px
  badge-success:
    backgroundColor: "{colors.success-subtle}"
    textColor: "{colors.success}"
    rounded: "{rounded.sm}"
    height: 20px
  badge-warning:
    backgroundColor: "{colors.warning-subtle}"
    textColor: "{colors.warning}"
    rounded: "{rounded.sm}"
    height: 20px
  badge-error:
    backgroundColor: "{colors.error-subtle}"
    textColor: "{colors.error}"
    rounded: "{rounded.sm}"
    height: 20px
  badge-info:
    backgroundColor: "{colors.info-subtle}"
    textColor: "{colors.info}"
    rounded: "{rounded.sm}"
    height: 20px
  treemap-primary:
    backgroundColor: "{colors.visualization-blue}"
    textColor: "{colors.on-tertiary}"
    rounded: "{rounded.sm}"
  treemap-secondary:
    backgroundColor: "{colors.visualization-purple}"
    textColor: "{colors.on-tertiary}"
    rounded: "{rounded.sm}"
  treemap-tertiary:
    backgroundColor: "{colors.visualization-teal}"
    textColor: "{colors.on-tertiary}"
    rounded: "{rounded.sm}"
---

# Zmole Design System

## Overview

Zmole is a **quiet professional Mac utility**, not a dashboard, not a gamified “cleaner,” and not a website wrapped in a desktop window. Its job is to make powerful system operations understandable and trustworthy while preserving the efficiency expected from a native macOS tool.

The product wraps the bundled `mole` CLI. The interface therefore has two equally important responsibilities:

1. **Make system state legible.** Users should quickly understand what occupies space, which application data will be affected, what a maintenance task does, and what the current machine status is.
2. **Make consequential actions safe.** `clean`, `uninstall`, `optimize`, and `purge` always follow **preview → explicit confirmation → execution**. The UI must never imply that a destructive action has occurred before the confirmed execution begins.

The visual personality is **calm, precise, dense when useful, and native to macOS**. Zmole should feel closer to a well-made first-party utility or developer tool than to an aggressive consumer optimization product. Avoid exaggerated “health” marketing, giant circular action buttons, neon gradients, and full-window brand-color washes.

### Product structure

The global navigation has exactly five primary work modes:

- **Clean** — identify reclaimable files, review categories, select items, preview, confirm, execute.
- **Software** — uninstall applications and edit the whitelist. Application rows may expand inline to reveal related files.
- **Optimize** — maintenance tasks and purge operations, with an execution preview before confirmation.
- **Analyze** — read-only disk-space exploration. No delete, clean, or uninstall action may originate from this mode.
- **Status** — live status and local history. Dense telemetry belongs here, not on every screen.

Secondary modes belong inside their parent workflow instead of becoming global navigation. Examples: Software contains **Uninstall / Whitelist**; Status contains **Live / History**.

### Design principles

- **Task before dashboard.** Each screen answers one operational question and gives one obvious next step.
- **Progressive density.** Clean and Optimize stay relatively calm; Software and Status may be denser; Analyze dedicates most of the window to spatial relationships.
- **Contextual navigation only.** Do not keep a large global sidebar visible when the current task does not need one. Use a contextual sidebar only for filters, directory hierarchy, or similar local structure.
- **Preview is a first-class state.** A preview is not a modal afterthought. It should show the exact objects, paths, sizes, or tasks that will be affected.
- **Danger is explicit, not theatrical.** Red is reserved for destructive semantics and failure states. Do not turn the entire screen red before a destructive action.
- **Local and private by default.** Do not design telemetry, accounts, cloud-sync affordances, or social proof into the core UI unless the product scope explicitly changes.
- **Data, not decoration.** Visualizations must encode real values. Decorative charts that do not help a decision are not allowed.

## Colors

The palette is a neutral macOS foundation with a restrained green accent. The green suggests reclamation and safe completion without turning the product into a “green cleaner” brand.

- **Primary (`#1D1D1F`)** — main light-mode text and high-emphasis controls.
- **Secondary (`#6E6E73`)** — metadata, captions, inactive navigation, timestamps, paths when de-emphasized.
- **Tertiary (`#0A7F68`)** — Zmole accent. Use for selected checkboxes, the primary non-destructive action, reclaimable-space emphasis, and active semantic highlights.
- **Neutral (`#F5F5F7`)** — secondary panes, filter rails, grouped backgrounds, and quiet containment.
- **Surface (`#FFFFFF`)** — primary content surface in light mode.
- **Error (`#C9182B`)** — destructive action labels, destructive confirmation, and actual failures only.
- **Success / Warning / Info** — semantic status colors; always pair them with text, icons, or labels so color is never the sole meaning.
- **Visualization Blue / Purple / Teal** — reserved for quantitative spatial or categorical visualization such as the disk space map. Do not reuse these colors as arbitrary brand accents.

### Light and dark mode

Zmole must support both macOS appearances. The `dark-*` tokens define the intended dark baseline. In SwiftUI, prefer system semantic materials and colors where they faithfully preserve this hierarchy; do not hard-code light colors into a dark appearance.

Dark mode is **not** a black theme. Use layered charcoal surfaces with visible but quiet separators. The accent becomes lighter (`#55D6B2`) to retain clarity on dark surfaces.

### Color usage rules

- One accent action per local decision area is usually enough.
- Neutral selection can use `surface-selected`; destructive selection should not use a red fill until the confirmation surface.
- Do not color every category in Clean. Category icons should be mostly neutral; color is earned by state or quantitative meaning.
- Treemap color is categorical support. **Area communicates size; color does not communicate size.**
- Maintain WCAG AA contrast for normal text where custom colors are used.

## Typography

Zmole uses the **native Apple system typography model**. In SwiftUI, implement these tokens with `.system` styles and weights rather than shipping font files. Chinese text should naturally fall back to the system CJK font (for example PingFang SC on Simplified Chinese systems).

- **Display / large headlines** are rare. They are for an empty state, scan result, or one major summary number, not for every section.
- **17–14px headlines** organize panes and groups without turning the interface into a web landing page.
- **13px body** is the default working density for tables, lists, and explanatory text.
- **11–10px labels** are for metadata, section eyebrows, timestamps, and compact status badges.
- **SF Mono** is reserved for paths, command-oriented identifiers, PIDs, byte-level values, and other technical data where character alignment matters.

### Numeric alignment

Columns containing sizes, percentages, PIDs, CPU values, or durations should align numerically. In SwiftUI, use monospaced digits for rapidly changing metrics even when the surrounding label uses SF Pro.

### Tone of copy

Use direct nouns and verbs: **Scan**, **Preview**, **Clean Selected Items**, **Move to Trash**, **Run Tasks**, **Cancel**. Avoid vague labels such as “Boost,” “Fix Everything,” “Make My Mac Faster,” or a generic “OK” for consequential actions.

## Layout

Zmole is a resizable desktop application. Design for a comfortable default window around **1200 × 760 px** and remain functional down to roughly **880 × 620 px**. Wider layouts should use the available width instead of centering everything in a narrow web-style column.

### Global shell

The shell is composed of:

1. Native window chrome / title bar.
2. A compact global mode control for **Clean / Software / Optimize / Analyze / Status**.
3. A view toolbar containing only actions relevant to the current mode.
4. The mode's working content area.

Do not use a permanent global sidebar. The five work modes are stable enough to live in the top-level mode switch; sidebars appear only when a task benefits from local hierarchy.

### Contextual sidebars and split views

- **Software:** a 190–230px contextual rail may contain filters such as All Apps, Unused, Large, Vendor, or Whitelist state. The main area remains the application list.
- **Analyze:** use a split view. The left pane is a 280–340px directory browser; the right pane is the space map and inspector.
- **Clean / Optimize:** avoid sidebars. Use grouped rows and a compact summary or preview panel.
- **Status:** use the full width for metrics and a process/history table.

### Spacing rhythm

Use the spacing tokens as a 4px-rooted rhythm with 6px and 12px optical steps for native control density.

- 4–8px: icon-to-label gaps, row internals, micro-alignment.
- 12–16px: control groups, pane padding, card interiors.
- 20–24px: section separation and content margins.
- 32–48px: only for major empty states or hero summaries.

Avoid web-dashboard padding inflation. A desktop utility should fit meaningful information without feeling cramped.

### Lists and tables

- Standard operational row: **48–56px**.
- Dense telemetry/history row: **30–38px**.
- Application row: **56–64px**, including icon, name, metadata, size, and disclosure affordance.
- Dividers are subtle and usually 1px; use whitespace plus separators instead of individual cards for every row.
- Prefer column alignment over floating badges when comparing repeated values.

### Selection shelf

When multiple objects are selected for a consequential action, show a **selection shelf directly below the view toolbar**, approximately 42px tall. It summarizes selected items, total size, cancel-selection, and the next preview action.

Do not rely on a giant persistent action button at the bottom of the window. The user's current selection and next action should remain close to the controls that created the selection.

### Analyze space map

The Analyze mode's signature element is the **Space Map**:

- The right pane should receive at least ~55% of the available width on a comfortable window.
- Rectangle area represents disk usage.
- Clicking a rectangle synchronizes the directory list and inspector.
- Labels disappear when a rectangle is too small; do not force text into unreadable tiles.
- Preserve a clear breadcrumb/path context.
- Analyze is read-only; do not place a destructive button in the map, inspector, context menu, or toolbar.

## Elevation & Depth

Zmole uses **tonal hierarchy and separators**, not card shadows, as its primary depth system.

- Primary working surfaces sit directly on the window surface or a slightly raised neutral surface.
- Contextual sidebars use a small tonal shift plus a separator line.
- Group containers may use a 1px border; they should not float like independent web cards.
- Shadows are reserved for true overlays: confirmation sheets/dialogs, menus, popovers, toasts, and the outer window in web prototypes.
- Selected rows use a quiet tinted background rather than elevation.

Avoid glassmorphism as a visual motif. Native materials may be used where macOS naturally provides them, but readability and hierarchy must remain clear without blur.

## Shapes

The shape language is **native-soft, not pill-heavy**.

- 6–8px radius: buttons, segmented-control selections, search fields, row hover/selection backgrounds.
- 10–12px radius: grouped panels, preview containers, metric cards.
- 14px radius: outer web-prototype window only; native SwiftUI windows should use the system window shape.
- Full pill radius: status dots, tiny count capsules, or controls that are natively pill-shaped. Do not turn every button into a capsule.

Application icons should preserve the source app icon. Utility glyph containers may use an 8px rounded square with a neutral background.

## Components

### Global mode switch

A compact five-item control placed in or near the top toolbar. Only one mode is active. The active item uses a neutral raised surface; the control should not look like a bright website navigation bar.

Keyboard shortcuts may map `⌘1` through `⌘5` to the five modes if this remains discoverable and does not conflict with macOS conventions.

### View toolbar

The toolbar changes by mode. Examples:

- Clean: scan state, rescan, scan scope when needed.
- Software: Uninstall / Whitelist scope, search, sort, refresh.
- Optimize: Maintenance / Purge scope and preview state.
- Analyze: breadcrumb/search, rescan/analyze action, depth controls.
- Status: Live / History scope and refresh.

Do not mirror every possible action into the toolbar. Keep it to high-frequency or view-level actions.

### Buttons

- **Primary:** use the accent for a safe, affirmative next step such as Scan or Preview.
- **Secondary:** neutral surface and border for utility actions.
- **Destructive:** red text or red-tinted treatment only when the action itself is destructive. A destructive button must use a specific verb such as **Clean**, **Move to Trash**, or **Run Purge**.
- Disable an action when its prerequisites are not met; explain why when the reason is not obvious.

A preview button is not destructive even when the eventual operation is. Keep Preview visually separate from Execute.

### Checkboxes and multi-selection

Checkboxes use the Zmole accent when selected. Selection state and destructive intent are separate concepts: selected rows remain green/neutral, not red.

For grouped cleanup data, parent categories may support mixed/indeterminate state. Child selection changes must update the parent state and size summary.

### Application list

Each app row should support fast scanning:

- selection control
- real application icon
- app name
- secondary metadata such as version, last use, or status when available
- app size
- related-data size or count when available
- disclosure control

Expanding an app reveals related paths **inline**, grouped by semantic type such as App Support, Cache, Logs, HTTP Storage, Preferences, or Containers. Paths use `data-sm` / SF Mono. Keep the user in the list instead of forcing a separate inspector for routine review.

For uninstall identity, the UI should retain the exact underlying app identity required by the product logic. Never allow a visually identical name to substitute for a verified path/bundle identity.

### Clean list

Present reclaimable data as semantic categories with size totals. Categories expand to show paths or subgroups when useful. The page should make three things continuously clear:

1. what is selected,
2. how much space is represented,
3. whether the user is still previewing or has reached execution confirmation.

Do not preselect ambiguous user data merely to maximize the reclaimable total.

### Optimize / Purge preview

Maintenance tasks are rows with name, short consequence description, and state such as Recommended, On Demand, or Requires Authorization. A preview panel summarizes selected tasks, approximate duration when known, authorization requirements, and reversibility.

Purge must keep its dry-run result visually distinct from execution. Never style a dry-run result as if bytes have already been removed.

### Space Map

The Space Map is Zmole's distinctive visualization. Use treemap rectangles, not ornamental bubbles. Optional inner marks may indicate hierarchy, but the rectangle area remains the authoritative size encoding.

The map and directory browser are two views of the same selection state. Hover may reveal path and size; click pins the selection. Keyboard focus must work through the directory list even if direct keyboard traversal of the canvas is limited.

### Status metrics and process table

Status may use compact metric cards for CPU, memory, disk, network, battery, or other values that the underlying status data actually provides. Do **not** invent a composite “health score” unless the backend has a defined, documented computation for it.

Below the summaries, use a table for processes or detailed status data. Sortable numeric columns should align and use monospaced digits. High usage may receive semantic emphasis, but a single spike should not make the whole screen alarming.

### Badges

Badges are compact semantic labels, not decoration. Examples: Completed, Cancelled, Requires Authorization, Read Only, Active. They should be used sparingly and never replace an important sentence.

### Dialogs and confirmation surfaces

For consequential operations, the confirmation surface must show the exact current preview generation: objects, sizes/paths where useful, and the specific verb that will execute.

The confirmation flow is:

1. user requests a preview,
2. preview succeeds,
3. UI displays the objects represented by that preview,
4. user explicitly confirms the same object set,
5. execution starts.

If the preview is stale or the object identity changes, return to preview. Do not silently execute against a different set.

### Progress, completion, and error

- Long operations show determinate progress when real progress exists; otherwise use an indeterminate indicator with the current phase label.
- Completion should report the actual result, not the estimated preview number.
- Errors should name the failed operation and provide the next useful recovery action.
- Cancellation is a normal state, not an error state.
- Toasts are appropriate for low-stakes acknowledgement; destructive results and failures deserve a persistent result state.

### Empty states

An empty state should explain why the view is empty and offer one next action. Examples: “No applications match this filter,” “Run an analysis to build the space map,” “No history yet.” Avoid illustrations that consume a large portion of the working area.

## Do's and Don'ts

- **Do** make Zmole look and behave like a Mac utility first; **don't** imitate a web admin dashboard.
- **Do** keep five stable global modes; **don't** promote every sub-feature into global navigation.
- **Do** use contextual sidebars only where hierarchy or filtering genuinely benefits from one; **don't** keep a large empty sidebar on Clean or Optimize.
- **Do** show real app icons, paths, sizes, task names, and status values; **don't** use decorative stand-ins when real data exists.
- **Do** keep Analyze strictly read-only; **don't** add delete, clean, uninstall, or purge actions to the Analyze toolbar, map, inspector, or context menus.
- **Do** treat Preview as a safe informational action; **don't** style Preview in destructive red.
- **Do** require explicit confirmation before `clean`, `uninstall`, `optimize`, or `purge` execution; **don't** spawn the destructive process before confirmation.
- **Do** keep the confirmation tied to the exact previewed object set; **don't** reuse a stale preview after the selection or identity changes.
- **Do** use red only for destructive semantics and failures; **don't** use red to mean merely “selected.”
- **Do** use the green accent for selection, safe primary actions, and reclaimable emphasis; **don't** flood the window with green.
- **Do** let information density vary by task; **don't** force every screen into the same grid of cards.
- **Do** use rows and tables for repeated comparable data; **don't** put every list item into its own floating card.
- **Do** encode disk size by treemap area; **don't** use arbitrary bubble sizes, gradients, or colors as fake quantitative encodings.
- **Do** support light mode, dark mode, keyboard focus, reduced motion, and VoiceOver-readable labels; **don't** make hover the only way to access an action or explanation.
- **Do** prefer native SwiftUI controls and system typography; **don't** ship custom fonts or reinvent standard Mac controls without a clear interaction need.
- **Do** use concrete Chinese/English verbs in destructive confirmation; **don't** use a generic “OK” button for consequential actions.
- **Do** keep history local and factual; **don't** imply telemetry, cloud sync, or remote monitoring when the product has none.
- **Do** show authorization requirements before execution; **don't** surprise the user with an unexplained privilege prompt.
- **Do** preserve window usability at the minimum supported size; **don't** hide core actions behind horizontal scrolling.
- **Do** favor calm separators and tonal layers; **don't** add heavy shadows, glass blur, neon glow, or animated gradients as decoration.
