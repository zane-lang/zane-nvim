-- End-to-end test: run with `nvim --headless -u NONE -l tests/run.lua` from the
-- repository root, with NVIM_TREESITTER naming an nvim-treesitter (main)
-- checkout, the Tree-sitter CLI and a C compiler on PATH, and fresh XDG
-- directories. ZANE_COMPILER_REVISION, when set, is the zane-lang/compiler
-- commit to install the parser from instead of its main branch.
local root = vim.fn.getcwd()
vim.opt.runtimepath:append(assert(vim.env.NVIM_TREESITTER, "NVIM_TREESITTER is not set"))
vim.opt.runtimepath:append(root)
vim.cmd("runtime! plugin/**/*.lua")
vim.cmd("filetype on")

local revision = vim.env.ZANE_COMPILER_REVISION
if revision and revision ~= "" then
  -- Registered after the plugin's, so it runs second.
  vim.api.nvim_create_autocmd("User", {
    pattern = "TSUpdate",
    callback = function()
      require("nvim-treesitter.parsers").zane.install_info.revision = revision
    end,
  })
end

local notices = {}
local notify = vim.notify
vim.notify = function(message, ...)
  table.insert(notices, message)
  return notify(message, ...)
end

local function step(name)
  io.stdout:write("== " .. name .. "\n")
end

local fixture = root .. "/tests/fixtures/parameters.zn"

step("with auto_install off, a missing parser is reported and nothing installs")
require("zane").setup({ auto_install = false })
vim.cmd.edit(fixture)
assert(vim.bo.filetype == "zane", "filetype detection failed")
assert(vim.tbl_contains(notices, "No Zane parser is installed. Run :TSInstall zane."), vim.inspect(notices))
assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "highlighting started without a parser")
assert(not vim.tbl_contains(notices, "Installing the Zane parser..."), "auto_install = false still installed")

step("with auto_install on, opening a Zane file installs the parser and starts highlighting")
require("zane").setup({ auto_install = true })
vim.cmd("bwipeout!")
vim.cmd.edit(fixture)
local buf = vim.api.nvim_get_current_buf()
local done = vim.wait(300000, function()
  return vim.treesitter.highlighter.active[buf] ~= nil
    or vim.iter(notices):any(function(m) return m:find("failed", 1, true) ~= nil end)
end, 500)
assert(done and vim.treesitter.highlighter.active[buf], "highlighting did not start: " .. vim.inspect(notices))

step("parameter uses are highlighted through zane-bound?")
local tree = assert(vim.treesitter.get_parser(buf, "zane"):parse()[1])
assert(not tree:root():has_error(), "the fixture does not parse")
local identifiers = {}
local function collect(node)
  if node:type() == "identifier" then
    table.insert(identifiers, node)
  end
  for child in node:iter_children() do
    collect(child)
  end
end
collect(tree:root())
local checked = 0
for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  local code, expected = line:match("^(.-)%s*// params:(.*)$")
  if code then
    local want = vim.split(vim.trim(expected), "%s+", { trimempty = true })
    local got = {}
    for _, node in ipairs(identifiers) do
      local srow, scol = node:start()
      if srow == row - 1 and scol < #code then
        for _, capture in ipairs(vim.treesitter.get_captures_at_pos(buf, srow, scol)) do
          if capture.capture == "variable.parameter" then
            table.insert(got, vim.treesitter.get_node_text(node, buf))
            break
          end
        end
      end
    end
    assert(vim.deep_equal(got, want), ("line %d: expected parameters %s, got %s"):format(row, vim.inspect(want), vim.inspect(got)))
    checked = checked + 1
  end
end
assert(checked >= 6, "too few annotated lines checked")

step("a zane-bound? call without arguments, as an old query has, matches nothing")
local old = vim.treesitter.query.parse("zane", "((name_expr . (identifier) @p .) (#zane-bound? @p))")
for _ in old:iter_captures(tree:root(), buf) do
  error("zane-bound? without arguments matched")
end

step(":checkhealth zane reports no errors or warnings")
vim.cmd("checkhealth zane")
local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
io.stdout:write(report .. "\n")
assert(not report:find("ERROR", 1, true) and not report:find("WARNING", 1, true), "checkhealth reported a problem")
assert(report:find("Zane parser loads", 1, true), "checkhealth did not check the parser")

io.stdout:write("== all passed\n")
