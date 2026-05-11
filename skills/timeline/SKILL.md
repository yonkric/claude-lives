---
description: Generate a narrative timeline of your project's history from session logs
---

Synthesize a chronological project history from session logs. Produces a readable narrative showing how the project evolved — milestones, decisions, turning points, and key discoveries.

## Arguments

- `/timeline` — timeline for current life/project
- `/timeline --weeks 4` — limit to last N weeks (default: all)
- `/timeline --format brief` — one-line-per-session summary instead of full narrative

## Steps

1. **Detect life and project**: Find `.claude-life`, determine life name, type, and project.

2. **Gather session logs**: Read all session log files chronologically:
   - Flat life: `~/.claude-lives/{life}/sessions/*.md`
   - Workspace project: `~/.claude-lives/{life}/projects/{project}/sessions/*.md`
   - Also read archived sessions: `archive/*.md`
   
   Sort by filename (YYYY-MM-DD-NNN format ensures chronological order).
   
   If `--weeks N` is specified, filter to sessions from the last N weeks.

3. **Read all session logs**: For each session file, extract:
   - Date (from frontmatter or filename)
   - Summary section
   - Decisions Made section
   - Completed section
   - Key Findings section

4. **Also read current state**: Read memory.md and handover.md for the current context:
   - What's the current focus?
   - What's pending?

5. **Synthesize the timeline**: Generate a narrative with this structure:

   ```markdown
   # Timeline: {life_name}{" / " + project_name if workspace}

   **Period:** {earliest_date} → {latest_date} ({N} sessions)
   **Current focus:** {from memory.md Current Focus}

   ## Week of {YYYY-MM-DD}

   **{date} — {session summary title}**
   {1-2 sentence narrative of what happened}
   - Key decision: {if any}
   - Milestone: {if something was completed}

   **{date} — {session summary title}**
   ...

   ## Week of {YYYY-MM-DD}
   ...

   ---

   ## Key Milestones
   - {date}: {milestone description}
   - {date}: {milestone description}

   ## Major Decisions
   - {date}: {decision and rationale}
   - {date}: {decision and rationale}

   ## Current State
   {from handover: what's in progress, what's next}
   ```

   For `--format brief`:
   ```
   # Timeline: {life_name} (brief)
   
   - {YYYY-MM-DD}: {one-line summary}
   - {YYYY-MM-DD}: {one-line summary}
   ...
   ```

6. **Present to user**: Show the synthesized timeline. Offer:
   - "Want me to save this to a file?"
   - "Want me to focus on a specific time period?"

## Guidelines

- Write in past tense for completed work, present tense for current state
- Highlight turning points — moments where direction changed
- Call out decisions that had lasting impact
- Keep each session entry to 2-3 sentences max in the narrative
- If there are 20+ sessions, group by week and summarize; don't narrate every session individually
- The brief format should be scannable in under 30 seconds

$ARGUMENTS
