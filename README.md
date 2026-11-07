# zane-nvim

[Zane](https://github.com/zane-lang/compiler) support for Neovim:

- `.zn` and `.zane` files get the `zane` filetype;
- Tree-sitter highlighting starts in them, including each use of a
  parameter (through the plugin's `zane-bound?` query predicate);
- the Zane parser is registered with
  [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter), which
  downloads the grammar and highlight queries from `zane-lang/compiler`, builds
  the parser and installs both. The plugin starts that install the first time
  a Zane file is opened without a parser.

The grammar is not part of this plugin: it comes from the compiler, so the
parser and its queries always come from the same compiler version.

## Requirements

- Neovim 0.12 or newer
- nvim-treesitter, `main` branch
- the [Tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/tree/master/crates/cli)
  0.26.1 or newer (nvim-treesitter's minimum), a C compiler, `curl` and `tar`,
  which nvim-treesitter uses to install parsers. Node is not needed: the CLI
  generates the parser with its built-in JavaScript runtime.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "TheLazyCat00/zane-nvim", lazy = false }
```

With Neovim 0.12's built-in `vim.pack`:

```lua
vim.pack.add({ "https://github.com/TheLazyCat00/zane-nvim" })
```

Open a `.zn` file and the parser installs. Don't put `"zane"` in the list you
give to `require("nvim-treesitter").install()`: nvim-treesitter may read that
list before this plugin has registered the parser. `:TSUpdate` (or
`:TSUpdate zane`) fetches the compiler's current grammar and queries again;
restart Neovim afterwards, since a loaded parser is not replaced.

### Moving from a manual install

Remove what the compiler's old instructions had you copy or load, since it
would run alongside the plugin: `zane.lua` (in `plugin/`, or loaded with
`dofile`), `after/queries/zane/highlights.scm`, and `parser/zane.so` and
`queries/zane/` under `~/.config/nvim`. Also remove any `parsers.zane`
registration of your own from an nvim-treesitter `TSUpdate` autocommand.
Then run `:TSUpdate zane`: a parser and queries already copied into
`~/.local/share/nvim/site`, where nvim-treesitter installs, count as
installed, so the plugin would not replace them on its own.

## Options

```lua
require("zane").setup({
  -- Install the parser the first time a Zane file is opened without one.
  -- When false, run :TSInstall zane yourself.
  auto_install = true,
})
```

With lazy.nvim, pass them as `opts`.

`:checkhealth zane` checks the setup.

## Development

The highlight queries, and the arguments `zane-bound?` receives, are generated
in `zane-lang/compiler` (`editors/neovim/queries/highlights.scm`, from
`grammar/tree-sitter.coda`); that repository's highlighting tests run Neovim
with this plugin.

`tests/run.lua` tests the plugin end to end: it installs the parser through
nvim-treesitter, then checks highlighting, parameter uses and
`:checkhealth zane`; `tests/failures.lua` checks what happens without
nvim-treesitter and when an install fails. CI runs both on every pull request and every push to `main`,
and daily against the compiler's `main`. To run it locally, with Neovim, the Tree-sitter
CLI and a C compiler installed:

```sh
git clone --depth 1 https://github.com/nvim-treesitter/nvim-treesitter /tmp/nvim-treesitter
home=$(mktemp -d)
XDG_CONFIG_HOME=$home/config XDG_DATA_HOME=$home/data XDG_STATE_HOME=$home/state XDG_CACHE_HOME=$home/cache \
  NVIM_TREESITTER=/tmp/nvim-treesitter nvim --headless -u NONE -l tests/run.lua
```

Set `ZANE_COMPILER_REVISION` to a compiler commit to install from it instead
of `main`; a pull request does that for the compiler's branch of the same name.
`tests/fixtures/parameters.zn` is a copy of the compiler's
`tests/highlighting/parameters.zn`.
