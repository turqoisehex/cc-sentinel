# Contributing to cc-sentinel

This is a side project maintained in spare time. Contributions are welcome — but please be patient with response times.

## Development Setup

### Prerequisites

- **Bash** 4.0+ (macOS ships 3.2 — use `brew install bash`)
- **jq** for JSON processing (`brew install jq` / `apt install jq` / `choco install jq`)
- **Git** 2.x+
- **Python 3** (only needed for the sprint-pipeline module)

### Clone and Explore

```bash
git clone https://github.com/turqoisehex/cc-sentinel.git
cd cc-sentinel
```

### Running Tests

Each module has its own test suite under `modules/<name>/tests/`:

```bash
# Run all tests
for f in modules/*/tests/test_*.sh; do bash "$f"; done

# Run a specific module's tests
bash modules/core/tests/test_anti_deferral.sh
bash modules/verification/tests/test_stop_task_check.sh

# Python tests (sprint-pipeline module)
python3 -m pytest modules/sprint-pipeline/tests/
```

### Project Structure

```
modules/              # 7 independent modules
  core/               # Anti-deferral, state management, context loss prevention
  context-awareness/  # Visual context window meter
  verification/       # Up-to-5-agent verification squad
  commit-enforcement/ # Test gating, auto-format, diff review
  sprint-pipeline/    # Structured /1-/5 workflow phases
  governance-protection/ # Protected files, authorization markers
  notification/       # Platform-native desktop alerts
modules.json          # Module manifest (dependencies, hooks, files)
install.sh            # Unix installer
install.ps1           # Windows PowerShell installer
templates/            # .claudeignore templates per framework
```

## How to Contribute

### Reporting Bugs

Use the [Bug Report](https://github.com/turqoisehex/cc-sentinel/issues/new?template=bug_report.yml) issue template. Include reproduction steps, expected vs actual behavior, and your environment.

### Suggesting Features

Use the [Feature Request](https://github.com/turqoisehex/cc-sentinel/issues/new?template=feature_request.yml) issue template. Describe the problem you're solving, not just the solution.

### Submitting Code

1. Fork the repo
2. Create a branch from `master`: `git checkout -b feat/your-feature`
3. Make changes with clear commits (conventional commits preferred):
   - `feat:` new feature
   - `fix:` bug fix
   - `docs:` documentation
   - `refactor:` code restructuring
   - `test:` test improvements
4. Ensure tests pass: `for f in modules/*/tests/test_*.sh; do bash "$f"; done`
5. Submit a PR against `master`

### Branch Naming

`feat/`, `fix/`, `docs/`, `refactor/`, `test/`

### Writing Tests

cc-sentinel tests are self-contained bash scripts that:
- Create temp directories with mock fixtures
- Pipe mock JSON stdin to hooks
- Assert exit codes and stdout content
- Clean up after themselves

Look at any existing `test_*.sh` file for the pattern.

## Recognition

All contributors are recognized. We value docs, bug reports, and community support — not just code.

## Questions?

Open a [Discussion](https://github.com/turqoisehex/cc-sentinel/discussions) in the Q&A category or comment on a relevant issue.
