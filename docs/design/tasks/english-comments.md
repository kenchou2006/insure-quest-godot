# Translate code comments to English

Translate every **comment** written in Chinese into clear, concise English in the files assigned to you.

## What counts as a comment
- GDScript: `#` comments and `##` doc comments.
- TypeScript / JavaScript / mjs: `//`, `/* */`, `/** */` (JSDoc).
- Shell / Python: `#` comments. `wrangler.jsonc`: `//` comments.

## Hard rules (a script will verify these)
1. **Edit in place, one line for one line.** Do not add, remove, merge or split lines. A Chinese comment line becomes exactly one English comment line at the same position.
2. **Never change code.** Everything outside the comment on each line must stay byte-for-byte identical.
3. **Never change string literals**, even if they contain Chinese — they are player-facing UI text, log text, AI prompts, test names or data. `"擲骰子"`, `'多人連線需先登入'`, `` `${p.name} 加入了房間` `` all stay as they are.
4. Keep comment markers and indentation exactly (`#`, `##`, `//`, ` * `, `/**`).
5. Domain terms: 顧問 = advisor, 客戶 = client, 面談 = interview, 合規 = compliance, 稽核 = audit, 保障卡 = coverage card,
   人生事件 = life event, 講師 = trainer, 學員 = learner, 額度 = quota, 房主 = host, 電腦顧問 = bot advisor, 單人練習 = solo practice,
   回合 = round, 棋盤 = board, 格子 = tile, 擲骰 = dice roll, 結算 = settlement / report, 十年後的信 = letter from ten years later.
   When a comment quotes UI text (e.g. 「展開」), keep the Chinese quote and translate around it: `the "展開" (expand) button`.
6. Comments that are already English: leave them.
7. Do not run any shell commands. Work synchronously; do not start a background subagent.

When done, list the files you changed.
