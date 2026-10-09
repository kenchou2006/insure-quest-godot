# Fix: Game Screen Scales Up and Overflows When Right Side "Quests" Card Expands

## Phenomenon
In landscape (desktop) screen, clicking 「展開」 ("Expand") on the right sidebar's quests card causes the entire game (board, tiles, text) to scale up by a notch, clipping off the bottom.

## Cause
`client/scripts/ui/game.gd` around lines 266–333: `sv` (VBox) inside `_side_panel` does not have an outer scroll wrapper. After the quests card expands, `sv`'s minimum height (title bar + quests card + player card ×3 + client directory + feed + emote bar) exceeds the window height, causing `_root` to be stretched vertically -> overall layout scales up. Although 「動態」 ("Feed")'s `UI.scroll(_log_box)` shrinks, the sum of other fixed content already exceeds height.

## Fix (Modify game.gd only, minimal changes)
1. Wrap `sv` into a ScrollContainer that only allows vertical scrolling before adding to `_side_panel` (can use `UI.scroll(sv)`, which already disables horizontal scrolling and sets `EXPAND_FILL`), preventing sidebar content from stretching the layout regardless of height.
2. The `ls := UI.scroll(_log_box)` for 「動態」 is now inside the outer scroll container, where `EXPAND_FILL` will become ineffective (0 height); give it a `custom_minimum_size.y` (~160 in landscape, 120 on mobile) so the feed remains visible.
3. In portrait mode, `_side_panel` is a full-screen tab; the same applies, do not branch separately.
4. Do not modify the expand/collapse logic, text, or colors of the quests card itself; do not touch any other file.
5. Mouse scroll wheel: outer ScrollContainer's `mouse_filter` remains `PASS` (`UI.scroll` already sets this).

## Constraints
- Godot 4.7 GDScript, file is `@tool`, must not trigger network in editor.
- Do not use emojis. Do not run any shell commands. Work synchronously; do not start a background subagent.
