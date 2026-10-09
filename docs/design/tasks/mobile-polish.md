# Mobile Polish (3 Items)

Screenshots are in `docs/design/tasks/mobile-shots/` (Android Chrome portrait, layout profile = phone_portrait, `content_scale_size` 480x854, see `client/scripts/main.gd` `_on_size_changed`):
- 69aa5ed9: Main menu, two account cards momentarily appear after login (one with Google avatar, one with a "周" circle).
- 1f0372b7: Training records / AI usage tab.
- 64693b6c: Training records / Past records tab.
- c4969d50: Training records / All learners tab.

## 1. Duplicate Account Cards After Login (`client/scripts/ui/menu.gd`)
`_update_auth_card()` calls `UI.clear` and rebuilds; avatar downloads asynchronously (`_load_avatar` -> await -> `_update_auth_card` again).
`_ready` connects `Net.auth_changed`, and lines 37 and 126 also call it; additionally, `main.gd` may rebuild the entire menu during layout changes (`on_layout_changed`). Please identify why two cards coexist (possible causes: two menu instances in the tree simultaneously, `_load_avatar` triggered repeatedly, or old menu still visible before `queue_free`), and fix so that only one card exists at any moment. During avatar loading, there can only be one in-flight request.

## 2. Mobile Layout for Training Records Screen (`client/scripts/ui/records.gd`)
- Title bar: 「回主選單」 ("Back to main menu") button is clipped beyond the right edge.
- Tab bar `_tabs_bar` (line 150) 5 buttons exceed screen width. In phone portrait, change to wrapping (HFlowContainer) or two rows so all are visible.
- AI usage tab cards exceed the screen on the right (content width appears > viewport). Find the element forcing width (labels with long text need autowrap, but must not be placed inside HBox, otherwise they become one character per line; place inside VBox or provide `custom_minimum_size`).
- Past records tab: in empty state, filter bar's LineEdit and 「查詢」 ("Search") button are vertically stretched to hundreds of px tall, and overlap underneath the empty list. Filter bar should be at the very top, fixed height around 44, with list/details below; in phone portrait, `split_box` should stack vertically (list on top, details on bottom) without overlapping.
- All learners tab filter bar also extends past right edge (「查詢」 is clipped).
- Principle: in phone portrait, nothing may exceed 480 width; having an outer vertical scroll is sufficient.

## 3. Game Board Too Small on Mobile (`client/scripts/ui/game.gd`, `board.gd`)
In phone portrait, the board (7x? circular board), tile text, and central dice rolling area are too small to read clearly. In phone_portrait:
- Board should maximize available width and height (reduce outer frame padding / margin); enlarge font size for tile titles and names;
- Central area legend text can be omitted or shortened on mobile to make the roll button and dice larger;
- If necessary, reduce phone_portrait's `content_scale_size` (e.g. 420x747) to scale up all UI, but ensure main menu, training records, interview panel (`session_panel.gd`), and event panel still do not exceed width at that size. If changed, explain in the report.
- Do not affect desktop and tablet layouts.

## Constraints
- Godot 4.7 GDScript, all UI scripts must be `@tool`, new scripts must also be `@tool`.
- Do not use emojis (not available in font); ✓×★●◆※ etc. may be used.
- Do not define functions with same name as native engine methods; `Button.flat = true` hides stylebox.
- Do not put autowrapping Labels inside HBox (causes one character per line).
- Do not run any shell commands. Work synchronously; do not start a background subagent.
- After completion, list modified files, lines, and reasons for each item.
