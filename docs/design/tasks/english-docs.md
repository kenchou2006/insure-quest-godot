# Translate project documentation to English

Translate the assigned Markdown files from Chinese into natural, concise English.

- Keep the structure: headings, lists, tables, code blocks, links, image paths, file paths, commands.
- Do not translate content inside code blocks or inline code, except Chinese comments inside code blocks.
- Player-facing UI text that is quoted (e.g. 「擲骰子」, "多人連線需先登入") stays in Chinese; add an English gloss in parentheses
  the first time it appears if the meaning is not obvious.
- Domain terms: 顧問 = advisor, 客戶 = client, 面談 = interview, 合規 = compliance, 稽核 = audit, 保障卡 = coverage card,
  人生事件 = life event, 講師 = trainer, 學員 = learner, 額度 = quota, 房主 = host, 電腦顧問 = bot advisor,
  單人練習 = solo practice, 十年後的信 = letter from ten years later, 人生顧問局 keeps its name (Life Advisor Bureau in parentheses once).
- Do not invent or drop facts. Do not "improve" content; translate it.
- Do not run any shell commands. Work synchronously; do not start a background subagent. List the files you changed.
