# Python Feature + Bugfix Workflow

Use for Python application changes that combine implementation and debugging.

## Scope
- New feature delivery
- Refactor with behavior preservation
- Bugfix with tests
- CLI/service/module updates

## Workflow
1. Confirm runtime and dependency context:
   - Python version
   - environment manager (`venv`, `poetry`, `uv`, etc.)
2. Reproduce issue or define feature acceptance criteria.
3. Implement focused changes with clear module boundaries.
4. Run quality gates:
   - tests (`pytest`)
   - lint (`ruff`/`flake8`)
   - format check (`black`/`ruff format --check`)
   - type check (`mypy`/`pyright`) when configured
5. Add/update tests:
   - happy path
   - edge/error path
6. Verify no temporary debug files/artifacts remain unless requested.

## Debug patterns
- Import/env mismatch: interpreter and `PYTHONPATH` verification.
- Data bugs: explicit schema/type checks at boundaries.
- Async bugs: event-loop ownership and cancellation handling.
- Performance issues: hotspot identification before optimizing.

## Output contract
- `Behavior change`
- `Files touched`
- `Test/quality results`
- `Residual risks`
