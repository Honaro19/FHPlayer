# FHPlayer Project Guidelines

## Language Conventions

- **Code**: Write all code, comments, and documentation in **English**
- **Communication**: Respond to user in **German**
- **Examples**: Inline code comments, function docstrings, variable names → all English
- **Exceptions**: Git commit messages may be in German if the developer prefers

## Code Style

- **Python**: Follow PEP 8 conventions
- **JavaScript**: Use consistent formatting (see static/ files for current style)
- **Comments**: Use English for all explanatory comments and docstrings

## Architecture

The project consists of:
- **Backend**: `app.py` (Python Flask/similar application)
- **Frontend**: HTML/CSS/JS in `static/` directory (index.html, styles.css, app.js, playlist-app.js)
- **Build**: Windows build scripts and PyInstaller configuration (FHPlayer.spec)

## Build and Test

- **Build Windows**: `./build_windows.ps1` or `./build_windows.cmd`
- **Run locally**: `python app.py`
- **Dependencies**: See `requirements-build.txt` and project requirements

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
