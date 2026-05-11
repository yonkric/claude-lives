# Contributing to claude-lives

Thanks for your interest in contributing! This guide covers how to get set up and submit changes.

## Development Setup

```bash
git clone https://github.com/yonkric/claude-lives
cd claude-lives

# Install in dry-run mode to see what would happen
./install.sh --dry-run

# Install for real
./install.sh
```

### Requirements

- bash (4.0+)
- Python 3.8+ (for hook registration and claude-mem migration)
- git
- Claude Code

## Running Tests

```bash
# Run full test suite (329 tests)
bash tests/run_all.sh

# Run a specific test file
bash tests/test_phase1.sh
bash tests/test_snapshots.sh
```

All tests must pass before submitting a PR.

## Project Structure

```
commands/        — Slash command markdown files (the user-facing interface)
hooks/           — Shell scripts registered as Claude Code hooks
lib/             — Shared bash utilities
templates/       — File templates for life creation
migration/       — claude-mem migration script (Python)
.claude-plugin/  — Plugin manifest and marketplace descriptor
tests/           — Test scripts
```

## Code Style

- **Shell scripts**: Use `snake_case` naming, `set -euo pipefail` where appropriate
- **Slash commands**: Lowercase with hyphens (e.g., `save-session.md`)
- **Memory content**: Telegraphic compression style (no articles, short phrases)
- Keep shell scripts POSIX-compatible where possible, or explicitly require bash

## Submitting Changes

1. Fork the repo and create a feature branch
2. Make your changes
3. Run `bash tests/run_all.sh` and ensure all tests pass
4. Submit a pull request with a clear description of what changed and why

## Security

If you find a security vulnerability, please report it privately rather than opening a public issue. Memory files are user-controlled content injected into CLAUDE.md, so injection prevention is critical.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
