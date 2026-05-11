#!/usr/bin/env python3
"""
Migrate claude-mem SQLite data into claude-lives memory structure.

Reads observations and session_summaries from claude-mem.db,
groups by project, and writes them into the appropriate life's
memory store at ~/.claude-lives/{life}/.

Usage:
    python3 claude_mem.py [--db PATH] [--output DIR] [--mapping FILE] [--dry-run]

The mapping file is a YAML/text file that maps claude-mem project names
to claude-lives life names. If not provided, uses project names as-is.
"""

import sqlite3
import os
import sys
import json
from datetime import datetime
from pathlib import Path
from collections import defaultdict


def get_db_path():
    default = Path.home() / ".claude-mem" / "claude-mem.db"
    for arg in sys.argv:
        if arg.startswith("--db="):
            return Path(arg.split("=", 1)[1])
    if "--db" in sys.argv:
        idx = sys.argv.index("--db")
        if idx + 1 < len(sys.argv):
            return Path(sys.argv[idx + 1])
    return default


def get_output_dir():
    default = Path.home() / ".claude-lives"
    for arg in sys.argv:
        if arg.startswith("--output="):
            return Path(arg.split("=", 1)[1])
    if "--output" in sys.argv:
        idx = sys.argv.index("--output")
        if idx + 1 < len(sys.argv):
            return Path(sys.argv[idx + 1])
    return default


def is_dry_run():
    return "--dry-run" in sys.argv


def load_mapping():
    """Load project→life mapping from file, or return empty dict for 1:1 mapping."""
    for arg in sys.argv:
        if arg.startswith("--mapping="):
            path = Path(arg.split("=", 1)[1])
            mapping = {}
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if ":" in line:
                        proj, life = line.split(":", 1)
                        mapping[proj.strip()] = life.strip()
            return mapping
    return {}


def read_observations(conn, project):
    """Read all observations for a project, return as list of dicts."""
    cursor = conn.cursor()
    cursor.execute(
        "SELECT title, subtitle, narrative, facts, created_at "
        "FROM observations WHERE project = ? ORDER BY created_at_epoch",
        (project,),
    )
    results = []
    for row in cursor.fetchall():
        facts = []
        if row[3]:
            try:
                facts = json.loads(row[3])
            except (json.JSONDecodeError, TypeError):
                facts = [row[3]]
        results.append({
            "title": row[0] or "",
            "subtitle": row[1] or "",
            "narrative": row[2] or "",
            "facts": facts,
            "date": row[4] or "",
        })
    return results


def read_summaries(conn, project):
    """Read all session summaries for a project."""
    cursor = conn.cursor()
    cursor.execute(
        "SELECT request, investigated, learned, completed, next_steps, notes, created_at "
        "FROM session_summaries WHERE project = ? ORDER BY created_at_epoch",
        (project,),
    )
    results = []
    for row in cursor.fetchall():
        results.append({
            "request": row[0] or "",
            "investigated": row[1] or "",
            "learned": row[2] or "",
            "completed": row[3] or "",
            "next_steps": row[4] or "",
            "notes": row[5] or "",
            "date": row[6] or "",
        })
    return results


def synthesize_memory(observations, summaries, life_name):
    """Produce a memory.md from observations and summaries."""
    today = datetime.now().strftime("%Y-%m-%d")

    # Extract key facts (deduplicated)
    all_facts = []
    seen = set()
    for obs in observations:
        for fact in obs["facts"]:
            normalized = fact.strip().lower()[:100]
            if normalized not in seen:
                seen.add(normalized)
                all_facts.append(fact)

    # Get most recent summary for current focus
    latest_summary = summaries[-1] if summaries else None

    # Build memory
    lines = [
        "---",
        f"life: {life_name}",
        f"last_compressed: {today}",
        f"session_count: {len(summaries)}",
        "migrated_from: claude-mem",
        "---",
        "",
        f"# {life_name} — Life Memory",
        "",
        "## Identity",
        f"Migrated from claude-mem project '{life_name}'.",
        "",
        "## Current Focus",
    ]

    if latest_summary:
        lines.append(latest_summary["request"][:200])
        if latest_summary["next_steps"]:
            lines.append("")
            lines.append("Next steps from last session:")
            lines.append(latest_summary["next_steps"][:300])
    else:
        lines.append("(No session summaries found)")

    lines.extend(["", "## Key Context"])

    # Add top facts (limit to stay within budget)
    fact_budget = 30
    for fact in all_facts[-fact_budget:]:
        lines.append(f"- {fact[:150]}")

    lines.extend(["", "## Preferences", "(Migrated — review and update manually)"])

    return "\n".join(lines)


def synthesize_handover(summaries, life_name):
    """Produce a handover.md from the latest session summary."""
    today = datetime.now().strftime("%Y-%m-%d")
    latest = summaries[-1] if summaries else None

    lines = [
        "---",
        f"life: {life_name}",
        f"last_updated: {today}",
        "---",
        "",
        "# Handover Notes",
        "",
        "## What Was Happening",
    ]

    if latest:
        lines.append(latest.get("completed", "(Unknown)")[:300])
    else:
        lines.append("(No session data — migrated from claude-mem)")

    lines.extend(["", "## Next Steps"])
    if latest and latest.get("next_steps"):
        lines.append(latest["next_steps"][:300])
    else:
        lines.append("(None recorded)")

    lines.extend([
        "",
        "## Pending Decisions",
        "(Review migrated memory for pending items)",
        "",
        "## Key Files Being Worked On",
        "(Not tracked by claude-mem — will be populated in future sessions)",
    ])

    return "\n".join(lines)


def write_life(output_dir, life_name, memory_content, handover_content, dry_run=False):
    """Write the life's memory files."""
    life_dir = output_dir / life_name
    sessions_dir = life_dir / "sessions"
    archive_dir = life_dir / "archive"

    if dry_run:
        print(f"  [DRY RUN] Would create: {life_dir}/")
        print(f"  [DRY RUN] memory.md: {len(memory_content)} chars")
        print(f"  [DRY RUN] handover.md: {len(handover_content)} chars")
        return

    life_dir.mkdir(parents=True, exist_ok=True)
    sessions_dir.mkdir(exist_ok=True)
    archive_dir.mkdir(exist_ok=True)

    # C4 fix: don't overwrite existing memory — backup first
    mem_path = life_dir / "memory.md"
    if mem_path.exists():
        backup = life_dir / "memory.md.pre-migration"
        mem_path.rename(backup)
        print(f"  [BACKUP] Existing memory.md backed up to {backup.name}")
    mem_path.write_text(memory_content)

    ho_path = life_dir / "handover.md"
    if ho_path.exists():
        backup = life_dir / "handover.md.pre-migration"
        ho_path.rename(backup)
    ho_path.write_text(handover_content)

    if not (life_dir / "config.yaml").exists():
        (life_dir / "config.yaml").write_text(
            "life_token_budget: 4000\n"
            "handover_token_budget: 1500\n"
            "compression_threshold_pct: 80\n"
            "decay_session_threshold: 10\n"
        )


def generate_report(projects, mapping, output_dir):
    """Generate a migration report."""
    lines = [
        "# claude-mem Migration Report",
        f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        "",
        "## Project → Life Mapping",
        "",
        "| claude-mem Project | claude-lives Life | Observations | Summaries |",
        "|---|---|---|---|",
    ]

    for proj, data in sorted(projects.items()):
        life = mapping.get(proj, proj)
        lines.append(f"| {proj} | {life} | {data['obs_count']} | {data['sum_count']} |")

    lines.extend([
        "",
        "## Notes",
        "- Memory files contain the most recent facts and latest session summary",
        "- Older observations are available in the claude-mem database if needed",
        "- Run `/compact-memory` in each life to refine the migrated memory",
        "- Review the Identity and Preferences sections — they need manual updates",
    ])

    return "\n".join(lines)


def main():
    db_path = get_db_path()
    output_dir = get_output_dir()
    dry_run = is_dry_run()
    mapping = load_mapping()

    if not db_path.exists():
        print(f"Error: claude-mem database not found at {db_path}")
        sys.exit(1)

    print(f"Reading from: {db_path}")
    print(f"Output to: {output_dir}")
    if dry_run:
        print("Mode: DRY RUN (no files will be written)")
    print()

    conn = sqlite3.connect(str(db_path))

    # Get all projects
    cursor = conn.cursor()
    cursor.execute("SELECT DISTINCT project FROM observations ORDER BY project")
    all_projects = [row[0] for row in cursor.fetchall()]

    projects = {}

    for project in all_projects:
        life_name = mapping.get(project, project).lower().replace(" ", "-")
        print(f"Processing: {project} → {life_name}")

        observations = read_observations(conn, project)
        summaries = read_summaries(conn, project)

        projects[project] = {
            "life_name": life_name,
            "obs_count": len(observations),
            "sum_count": len(summaries),
        }

        memory = synthesize_memory(observations, summaries, life_name)
        handover = synthesize_handover(summaries, life_name)

        write_life(output_dir, life_name, memory, handover, dry_run)
        print(f"  {len(observations)} observations, {len(summaries)} summaries → {life_name}/")

    conn.close()

    # Write report
    report = generate_report(projects, mapping, output_dir)
    report_path = output_dir / "migration-report.md"
    if not dry_run:
        report_path.write_text(report)
        print(f"\nMigration report: {report_path}")
    else:
        print(f"\n[DRY RUN] Would write report to: {report_path}")

    print(f"\nDone. {len(all_projects)} projects migrated to {len(set(p['life_name'] for p in projects.values()))} lives.")


if __name__ == "__main__":
    main()
