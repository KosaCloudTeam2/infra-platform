$ErrorActionPreference = "Stop"

pnpm exec marp docs/presentation/presentation.md --pdf --allow-local-files
