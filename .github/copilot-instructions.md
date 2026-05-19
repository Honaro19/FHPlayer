# FHPlayer Project Guidelines

## Language Conventions

- **Code**: Write all code, comments, and documentation in **English**
- **Communication**: Respond to user in **German**
- **Examples**: Inline code comments, function docstrings, variable names → all English
- **Exceptions**: Git commit messages may be in German if the developer prefers

## Code Style

- **Dart/Flutter**: Follow standard Flutter formatting and linting
- **PowerShell**: Keep scripts strict, explicit, and readable
- **Comments**: Use English for all explanatory comments and docstrings

## Architecture

The project consists of:
- **App**: `fhplayer_flutter/` shared Flutter app for Windows and Android
- **Build**: Windows and Android PowerShell build/release scripts
- **Release**: Local release preparation scripts under `scripts/` and `release/`

## Build and Test

- **Build Windows**: `./build_windows.ps1` or `./build_windows.cmd`
- **Run locally (Windows)**: `Set-Location fhplayer_flutter; flutter run -d windows`
- **Run tests**: `./scripts/test_flutter.ps1`
- **Analyze**: `Set-Location fhplayer_flutter; flutter analyze`

## When Suggesting Changes

1. Write all code in English
2. Explain suggestions in German
3. Include English comments in code examples

- [x] Verify that the copilot-instructions.md file in the .github directory is created.
- [x] Clarify Project Requirements
- [x] Scaffold the Project
- [x] Customize the Project
- [x] Compile the Project
- [x] Ensure Documentation is Complete
