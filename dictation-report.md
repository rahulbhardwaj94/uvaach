# Dictation shootout — Uvaach vs Wispr Flow
_2026-07-05_

| Passage | Tool | WER | Last word kept | Adjacent dupes |
|---|---|---|---|---|
| Fillers + short command | Uvaach | 21.7% | yes | none |
| Fillers + short command | Wispr Flow | 8.7% | yes | none |
| Self-correction | Uvaach | 33.3% | **NO** | none |
| Self-correction | Wispr Flow | 40.0% | yes | none |
| Long technical monologue | Uvaach | 0.0% | yes | none |
| Long technical monologue | Wispr Flow | 3.9% | yes | none |
| Numbers and times | Uvaach | 57.1% | **NO** | none |
| Numbers and times | Wispr Flow | 50.0% | **NO** | none |
| Technical vocabulary | Uvaach | 50.0% | yes | none |
| Technical vocabulary | Wispr Flow | 27.3% | yes | none |

## Fillers + short command

**Reference:** Um, can you send me the report by Friday? I think, uh, we should also loop in the design team before the review.

**Uvaach:** Can you send me the report by Friday? We should also loop in the design team before review.

**Wispr Flow:** Can you send me the report by Friday? I think we should also loop in the design team before the review.


## Self-correction

**Reference:** I have a meeting tomorrow morning with a client. Let's change the meeting to Friday at 6 p.m. No, no, just change it to Friday at 6 p.m.

**Uvaach:** I have a meeting tomorroI have a meeting tomorrow morning with a client. Let’s change the meeting to Friday at 6 pm. No, no, just change it to Friday at 6

**Wispr Flow:** I have a meeting tomorrow morning with a client. Just change it to Friday at 6 p.m.


## Long technical monologue

**Reference:** You most likely fall into one of two camps. You either check every single command the AI runs before it runs, or you YOLO run AI with zero oversight. This either wastes your time or opens you up to huge security issues. That is why in this video I will show you how to sandbox your AI so you can save time and rest knowing your AI is unable to do anything malicious on its own.

**Uvaach:** You most likely fall into one of two camps. You either check every single command the AI runs before it runs or you YOLO run AI with zero oversight. This either wastes your time or opens you up to huge security issues. That is why in this video I will show you how to sandbox your AI so you can save time and rest knowing your AI is unable to do anything malicious on its own.

**Wispr Flow:** You most likely fall into one of two camps: 1. You check every single command the AI runs before it runs. 2. You YOLO run AI with zero oversight. This either wastes your time or opens you up to huge security issues. That is why in this video I will show you how to sandbox your AI so you can save time and rest knowing your AI is unable to do anything malicious on its own.


## Numbers and times

**Reference:** The standup is at nine thirty a.m., the demo is at 6 p.m. on the twenty-first, and the budget is around twenty-five thousand dollars.

**Uvaach:** The stand-up is at 9:30 am, the demo is at 6 pm on 21st, and the budget is approximately $25,000.

**Wispr Flow:** The stand-up is at 9:30 am. The demo is at 6 pm on the 21st, and the budget is around $25,000.


## Technical vocabulary

**Reference:** I'm using dev containers with node_modules mounted as a volume, running npm and pnpm commands, plus Ollama and WhisperKit on my MacBook.

**Uvaach:** I am using development containers with Node modules mounted as volumes, running npm or pnpm commands plus Olama and Whisper Kit on my Macbook.

**Wispr Flow:** I am using Dev containers with node modules mounted as a volume, running NPM and PNPM commands plus uvaach and Wisprkit on my Macbook.
