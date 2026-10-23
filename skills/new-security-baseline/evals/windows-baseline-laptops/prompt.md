---
tags: [skill-creator]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Create a security baseline for our corporate Windows 11 laptops using the latest Windows security baseline. Keep the Microsoft defaults, except set the machine inactivity limit to 600 seconds, and leave BitLocker settings not configured because our separate BitLocker policy handles encryption.
