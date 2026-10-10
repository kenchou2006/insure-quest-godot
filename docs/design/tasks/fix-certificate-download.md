# Fix: Certificate 「儲存圖片」 Exports a Clipped, Background-Bleeding Screenshot

## Phenomenon
In the final report, pressing 「儲存圖片」 on the 「公平待客面談完訓卡」 downloads a PNG that is only a slice of the screen: the card is cut off at the top/bottom (only the title row and the name row are visible, the seal, five-power bars and coach comment are missing), the blurred report background and the "顧問結算報告" heading / formula line are included, and the card's rounded corners and gold border are cropped. Output size and scale also vary with window size.

## Cause
`client/scripts/ui/report.gd` `_download_certificate()` (~line 466) takes the whole viewport texture and crops it to `card_panel.get_global_rect()`:
- The card sits inside a ScrollContainer; when it is partly scrolled off-screen, `intersection` with the viewport silently drops the hidden part.
- Everything painted behind the card (report background, heading) is captured because the card has rounded corners with a translucent surround.
- The captured size depends on window size, DPI and stretch mode, so the PNG is not a consistent artifact.

## Fix (modify `report.gd` only, minimal changes)
Render the card off-screen at a fixed size instead of cropping the live viewport:
1. Refactor `_build_certificate_card(mine, s)` so a second instance can be built for export (add a parameter such as `for_export: bool = false`; when true, omit the download button, force the desktop/landscape layout, and use a fixed `custom_minimum_size` of about 1200 x 675 so layout is identical on phone and desktop).
2. In `_download_certificate()`: create a `SubViewport` (size 1200 x 675, `transparent_bg = true`, `render_target_update_mode = UPDATE_ONCE`, `own_world_3d` not needed, `canvas_item_default_texture_filter` linear), add the export card to it, add the SubViewport to the tree (hidden / off-layout), `await RenderingServer.frame_post_draw`, then `get_texture().get_image()`, `save_png_to_buffer()`, and `JavaScriptBridge.download_buffer(buf, "fair-treatment-certificate.png", "image/png")`. Free the SubViewport afterwards.
3. Optional if the export looks soft: render at 2x (SubViewport size 2400 x 1350 with `canvas_transform` scale 2, or `size_2d_override`) so the PNG is crisp when shared.
4. Wrap the whole card in a margin so the rounded gold border and corners are fully inside the image; leave the surround transparent (or fill with `#0d2821` if transparent corners look bad when pasted into chats).
5. Keep the button text 「儲存圖片」, keep it web-only, keep the filename. The on-screen card appearance must not change.
6. Make sure the date and name shown on the export match the on-screen card (same data, reuse the same builder).

## Constraints
- Godot 4.7 GDScript, file is `@tool`; guard with `Engine.is_editor_hint()` and `OS.has_feature("web")` as today. No network in the editor.
- No emojis. Do not run any shell commands. Work synchronously; do not start a background subagent.
- Do not touch other files. Claude will compile, export the web build and screenshot the downloaded PNG to verify (expected: full card, all rows visible, no background or heading from the report page).

## Acceptance
Downloaded PNG shows the entire card (title row, name + date, clients served, red-light stamp, five-power bars, grade seal, coach comment), 16:9, identical regardless of scroll position, window size or phone/desktop layout.

## Follow-up (round 2): the first SubViewport implementation still exports a broken image
Observed output (1200x675 PNG): the card is wider than the image (right edge and gold border cut off, no right margin), the header row is at the top, the left column (name, date, 服務客戶, 零違規 stamp) is pushed to the very bottom edge, and the whole middle is empty — five-power bars, grade seal and coach comment are missing. The 20px margin is not visible either. So the export card is not laid out inside the 1200x675 viewport: the body row is stretched/overflowing (the `SIZE_EXPAND_FILL` vertical flags plus `ALIGNMENT_CENTER` on `left_v` and the min size 1160x635 make the content taller/wider than the viewport, and the wrapper MarginContainer inside a SubViewport is not being sized to it).

Fix guidance:
1. Do not use expand flags or centering tricks for export. Build the export card with a fixed explicit size: a plain `Control` root of 1200x675 added to the SubViewport, inside it the card `PanelContainer` with `position = (20,20)`, `size = (1160, 635)` and `clip_contents = true`. Remove `ALIGNMENT_CENTER` on `left_v` and the vertical expand flags added in round 1.
2. Check the desktop (non-export) layout of the card: it is a header row + a body HBox (left column with five-power bars, right column with grade seal and coach comment). The export must reproduce exactly that, only wider. Ensure the right column and the five-power bars actually get built (they were absent in the output) — check for code paths that depend on `UI.is_phone()` / `get_viewport()` / on-screen-only nodes, or `await`s, that return empty children when the card is inside a SubViewport.
3. Labels with autowrap (coach comment) need a width: give them `custom_minimum_size.x` so a 0-width wrapped label does not blow up the height.
4. After `add_child(vp)`, wait two frames (`await get_tree().process_frame` twice) before `await RenderingServer.frame_post_draw`, so layout is settled before capture; set `render_target_update_mode = UPDATE_ALWAYS` until the image is read, then free.
5. Fill the area outside the card (the 20px margin) with transparent, but make sure the card itself is fully inside the image.
6. Self-check by reading the code carefully (no shell commands are allowed); Claude will build and verify the PNG.
