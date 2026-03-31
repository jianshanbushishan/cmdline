# AGENTS.md — cmdline.nvim

Neovim plugin that replaces the built-in cmdline with a floating popup featuring icons and syntax highlighting. Extracted from [noice.nvim](https://github.com/folke/noice.nvim) as a standalone plugin with zero external dependencies (no NUI, no plenary).

Current product scope is intentionally narrow:

- Popup cmdline focused on command `:` and search `/` / `?`
- A single built-in `:lua` special case is kept for Lua code input highlighting
- No general-purpose format registry, view alias system, or custom cmdline mode expansion

## Project Structure

```
plugin/cmdline.lua          # Entry point — loaded guard only
lua/cmdline/
  init.lua                  # Main module: setup(), enable(), disable(), event routing
  config.lua                # Config defaults, popup options, highlight groups
  cmdline.lua               # Cmdline event handler & formatter (command/search + minimal :lua special case)
  view.lua                  # Popup view lifecycle (show/hide/render) for the single popup view
  popup.lua                 # Floating window creation (native nvim_open_win, no NUI)
  block.lua                 # Text block container (multi-line rendering)
  line.lua                  # Single line of text segments
  text.lua                  # Text segment with extmark/syntax/virtual text support
  message.lua               # Message block subclass (singleton used by init.lua)
  class.lua                 # Minimal OOP system (create/extend with inheritance)
  syntax.lua                # Vim-syntax fallback highlighting
  treesitter.lua            # Treesitter-based syntax highlighting
  util.lua                  # Helpers: protect/try, redraw, layout math, termcodes
```

## Build / Lint / Test

This project has **no build step and no linter config**.

- **No `.stylua`**, `.luacheckrc`, `selene.toml`, or `Makefile` present.
- **No formal test framework or CI configuration.**
- **A minimal headless smoke script exists at `tests/smoke.lua`.**

### Manual verification

```vim
" Install locally for testing
" In your Neovim config:
lua require("cmdline").setup()

" Reload after changes
:lua package.loaded["cmdline"] = nil; require("cmdline").setup()
```

To check for Lua syntax errors:
```bash
luac -p lua/cmdline/init.lua
luac -p lua/cmdline/cmdline.lua
# Or from within Neovim:
:luafile lua/cmdline/init.lua
```

Minimal headless verification:
```bash
nvim --headless -u NONE -i NONE -n -S tests/smoke.lua
```

## Code Style Guidelines

### Module Pattern

Every module follows the standard Neovim Lua pattern:

```lua
--- Module description (triple-dash for LuaDoc)
local Dependency = require("cmdline.dependency")

local M = {}

-- ... functions ...

return M
```

### Imports / Requires

- All `require()` calls at the **top of the file**, before any logic.
- Module path: `require("cmdline.module_name")` (no relative paths).
- Order: external dependencies first (none currently), then internal modules.

### Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Modules | `lowercase` | `cmdline`, `config`, `util` |
| Classes / Types | `PascalCase`, prefixed with `Cmdline` | `CmdlinePopup`, `CmdlineFormat`, `CmdlineInstance` |
| Functions | `snake_case` | `on_show()`, `get_format()`, `setup_highlights()` |
| Local variables | `snake_case` | `local message`, `local view`, `local border_style` |
| Private fields | `_prefix` underscore | `self._popup`, `self._visible`, `self._lines` |
| Constants | `UPPER_SNAKE_CASE` | `M.SPECIAL`, `M.CR`, `M.ESC`, `M.BS` |
| Boolean guards | `_prefix` past-tense | `M._attached`, `M._setup_done` |

### Type Annotations (EmmyLua / LuaDoc)

Extensive use of type annotations — **always add them** for new functions and classes:

```lua
---@class CmdlineFormat
---@field name "cmdline"|"search_down"|"search_up"
---@field kind CmdlineKind
---@field conceal boolean
---@field icon string

---@param opts? CmdlineConfig
function M.setup(opts)
  ...
end
```

- Use `---` (triple-dash) for LuaDoc lines.
- Use `?` suffix for optional parameters/fields: `---@param opts? CmdlineConfig`.
- Use `---@type` for variable annotations, `---@cast` for type narrowing.
- Use `---@diagnostic disable-next-line:` to suppress specific warnings when necessary (e.g., `deprecated`, `redundant-parameter`, `invisible`).

### OOP / Class System

- Use `class.lua` for new class hierarchies: `Class.create("Name")` and `SubClass:extend("Name")`.
- For lightweight objects without inheritance, use direct metatables: `setmetatable({}, M)`.
- Constructor pattern: `function M.new(opts)` returning a metatable instance.

### Error Handling

- **Always wrap Neovim API calls** that may fail in `pcall()`:
  ```lua
  pcall(vim.api.nvim_win_close, winid, true)
  ```
- Use `Util.protect(fn)` or `Util.try(fn, ...)` for user-facing callbacks (provides notification on error).
- Use `pcall()` defensively around window/buffer validity checks.
- **Never** use bare `pcall` without handling or silencing being intentional — these are safety wrappers.

### String Quoting

- **Double quotes** for all strings: `"cmdline"`, `"rounded"`, `"CmdlinePopup"`.
- Single quotes not used in this codebase.

### Indentation & Formatting

- **2-space indentation** (no tabs).
- Blank lines between function definitions.
- Group related local variables together at the top of a scope.

### Vim API Usage

- `vim.api.nvim_*` for buffer/window operations.
- `vim.fn.*` for Vimscript functions (`strlen`, `screenpos`, `has`).
- `vim.go.*` for global options, `vim.bo[buf]` for buffer-local, `vim.wo[win]` for window-local.
- `vim.tbl_deep_extend("force", ...)` for deep-merging option tables (used pervasively).
- `vim.deepcopy()` when passing opts to avoid mutation.
- `vim.schedule()` for deferred operations.
- `vim.api.nvim_create_augroup` / `nvim_create_autocmd` for autocommands (not Vimscript `autocmd`).

### Key Patterns to Follow

1. **Singleton modules**: View, Message, Config — created once, accessed via `Module.get()` or module-level variable.
2. **Option normalization**: Always `vim.deepcopy(opts)` before mutation. Use `vim.tbl_deep_extend("force", defaults, user_opts)` for merging.
3. **Guard conditions**: Early returns for validity checks (`if not self._popup then return end`).
4. **Platform compatibility**: Guard Neovim version features with `vim.fn.has("nvim-0.10")` / `has("nvim-0.11")`.
5. **Loading guards**: Use `self._.loading` boolean to prevent re-entrant mount/unmount operations.
6. **Namespace**: All extmarks use `Config.ns` (created once via `nvim_create_namespace("cmdline")`).
7. **Feature scope**: Keep cmdline classification fixed to command, search, and the built-in `:lua` special case. Do not reintroduce generic pattern-driven format registries unless explicitly requested.

### Things to Avoid

- **Do not** introduce external dependencies (no plenary, no NUI). This plugin is intentionally standalone.
- **Do not** use `vim.cmd("...")` for logic that has a Lua API equivalent.
- **Do not** mutate opts tables passed as parameters without deepcopying first.
- **Do not** use `vim.schedule_wrap` when `vim.schedule(function() ... end)` suffices.
- **Do not** add `vim.validate()` argument checking — not used in this codebase.
