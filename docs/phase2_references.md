# Phase 2 References

This repo uses the imported upstream corpus as the primary test surface. During the Phase 2 lexer/parser/formatter work, the following read-only references were also used for syntax evidence and implementation direction:

- `~/repos/boon/MIGRATION_COLLECTION_SYNTAX.md`
  - Explains the collection-syntax migration from `TYPE { size, { ... }}` to `TYPE[size] { ... }`.
  - Important caveat: the note says the new syntax was migrated in docs/examples before the upstream compiler/parser was updated, so some imported examples may legitimately stay blocked until the new syntax is handled.
- `~/repos/boon/playground/frontend/typescript/code_editor/boon-parser.ts`
  - Upstream generated TypeScript parser artifact for the editor.
- `~/repos/boon/playground/frontend/typescript/code_editor/boon-language.ts`
  - Upstream editor language wiring and syntax-highlighting rules.
  - Useful for token categories such as keywords, operators, brackets, separators, tagged objects, `TEXT` handling, and semantic highlight heuristics.

These files are inspiration and evidence only. `PLAN.md` remains the source of truth for implementation order, hard gates, and definition of done.
