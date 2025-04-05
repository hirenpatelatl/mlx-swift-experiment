# MLX Swift Project Guide

## Build & Run Commands
- Build: `xcodebuild -configuration Release -scheme [scheme-name]`
- Run CLI tools: `./mlx-run [tool-name] [arguments]` or `./mlx-run --debug [tool-name] [arguments]`
- Run specific test: `./mlx-run [test-tool-name] --test [test-name]`
- Format code: `swift-format format --in-place --recursive Libraries Tools Applications`

## Code Style Guidelines
- Use Swift Concurrency with `StrictConcurrency` enabled
- Follow naming conventions: CamelCase for types, lowerCamelCase for variables
- Organize imports with MLX packages first, then standard libraries
- Format with swift-format (pre-commit hook available)
- Error handling: Use Swift's built-in error handling with do/catch blocks
- Documentation: Include comprehensive docstrings for public APIs
- Follow existing code patterns when creating new components
- Ensure type safety throughout the codebase
- Avoid force unwrapping optionals

## Project Structure
- Libraries/: Core functionality split by domain (LLM, VLM, etc.)
- Applications/: Example apps showing library usage
- Tools/: Command-line tools for model training/evaluation
- Data/: Training and evaluation datasets