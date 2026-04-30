#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
MATT_DIR="$HOME/.claude/matt"
BACKUP_DIR="/tmp/claude-skills-backup-$(date +%Y%m%d%H%M%S)"

mkdir -p "$SKILLS_DIR" "$MATT_DIR/features" "$BACKUP_DIR"

# Copy skills (directories containing SKILL.md)
for d in "$REPO_DIR"/*/; do
  [ -f "$d/SKILL.md" ] || continue
  name="$(basename "$d")"
  if [ -d "$SKILLS_DIR/$name" ]; then
    cp -r "$SKILLS_DIR/$name" "$BACKUP_DIR/$name"
    rm -rf "$SKILLS_DIR/$name"
    echo "backup: $name -> $BACKUP_DIR/$name"
  fi
  cp -r "$d" "$SKILLS_DIR/$name"
  echo "installed: $name"
done

# Copy config files
for f in issue-tracker.md triage-labels.md; do
  cp "$REPO_DIR/$f" "$MATT_DIR/$f"
  echo "config: $MATT_DIR/$f"
done

echo "done"
