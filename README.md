# Copilot Instructions (readme_copilot)

This repository includes a Copilot instruction file at `.github/copilot.yml`. The contents and essential rules are reproduced here so that the guidance is visible in the repository README.

## Purpose

- Ensure Copilot follows workspace-specific guidelines, coding standards, and best practices every time it generates or changes code.

## Key guidelines

- Follow best practices: idiomatic Go, modular design, small functions, and clear comments.
- All Go source files live under /src and imports may include '/src' in the path. Do not move source files outside /src.
- When adding or modifying Go code, include unit tests, benchmarks, and examples in the same package.
- Use the newest supported Go syntax (go 1.25) and prefer generic and idiomatic patterns.
- Run the repository checks script after any generated or modified code: `.github/scripts/run_copilot_checks.sh`.
- Do not introduce harmful, copyrighted, or irrelevant content.
- Keep changes short and focused.

## Enforcement

- Copilot must run the check script `.github/scripts/run_copilot_checks.sh` after any code generation or change.

## Local checks script

- The repository contains `.github/scripts/run_copilot_checks.sh`. This script:
  - runs `go work sync` and `go mod tidy` to ensure dependencies and create `go.sum`;
  - verifies benchmarks and examples exist for packages with Go files;
  - runs `go test ./... -coverprofile=coverage.out` and writes the overall coverage percentage to `.coverage_current`;
  - compares coverage to `.coverage_baseline` and exits non-zero if coverage decreased.

For full rules, see `.github/copilot.yml` in the repository root.
