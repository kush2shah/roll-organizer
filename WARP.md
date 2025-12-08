# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Repository state

- At the time of writing, this repository contains only VCS metadata (e.g., the `.git` directory) and no application code, configuration files, or documentation.
- Future instances of Warp should not assume any particular language, framework, or tooling until project files are added.

## How future agents should discover build, lint, and test commands

When project files are added, always infer commands from the repository itself instead of guessing:

1. **Identify the primary toolchain**
   - Look for ecosystem-defining files, for example (non-exhaustive):
     - JavaScript/TypeScript: `package.json`, `pnpm-workspace.yaml`, `turbo.json`, `vite.config.*`, `next.config.*`
     - Python: `pyproject.toml`, `requirements.txt`, `Pipfile`, `tox.ini`, `pytest.ini`/`conftest.py`
     - Go: `go.mod`, `go.work`
     - Rust: `Cargo.toml`
     - Generic build tooling: `Makefile`, `justfile`, `Taskfile.*`, `docker-compose.yml`
   - Once such files exist, read them (and any `README*`) to determine the canonical commands.

2. **Prefer project-defined scripts over raw tool invocations**
   - For Node-based projects, prefer `npm run <script>`, `pnpm <script>`, or `yarn <script>` based on the lockfile and documentation.
   - For Python, look for `make` targets, `tox` environments, or `poetry`/`pipenv` commands defined in config instead of inventing commands.
   - For other ecosystems, follow the conventions implied by their manifest files.

3. **Running tests (including a single test)**
   - Detect the test runner from config and imports (e.g., Jest/Vitest for JS, Pytest for Python, Go test, Cargo test) once code exists.
   - Use the project’s documented patterns for running a *single* test (e.g., Jest/ Vitest `--testNamePattern`, Pytest `path::TestClass::test_name`, Go `-run`), but only after confirming the actual framework.

4. **Keep this file up to date**
   - After build/lint/test tooling is added, update this `WARP.md` with the concrete commands used in this repository (e.g., `npm run build`, `poetry run pytest`, `go test ./...`).
   - Summarize any non-obvious workflows (e.g., monorepo tooling, multi-service setup) here so future agents can be productive quickly.

## Future architecture notes

- Because there is currently no source code, there is no architecture to document.
- Once code is added, future agents should:
  - Identify the main entrypoints (e.g., `src/main.*`, `app/*`, `cmd/*`, or framework-specific entry files).
  - Map out the top-level modules/packages and how they depend on each other.
  - Document any cross-cutting concerns that span multiple files (e.g., shared configuration, domain models, or infrastructure layers) in this section.

Until project files exist, treat this repository as an empty scaffold and rely on user instructions for any language- or tool-specific behavior.