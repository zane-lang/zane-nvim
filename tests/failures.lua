-- The plugin's failure paths: run like tests/run.lua, with fresh XDG
-- directories and NVIM_TREESITTER naming an nvim-treesitter checkout.
local root = vim.fn.getcwd()
vim.opt.runtimepath:append(root)
vim.cmd("runtime! plugin/**/*.lua")
vim.cmd("filetype on")

local notices = {}
-- Recorded and printed, not passed on: in a script, an error-level notice
-- would raise and abort the command that caused it.
vim.notify = function(message)
  table.insert(notices, message)
  io.stdout:write(message .. "\n")
end
local function noticed(text)
  return vim.iter(notices):any(function(m) return m:find(text, 1, true) ~= nil end)
end

local fixture = root .. "/tests/fixtures/parameters.zn"

io.stdout:write("== without nvim-treesitter, opening a Zane file says it is needed\n")
vim.cmd.edit(fixture)
assert(noticed("needs nvim-treesitter"), vim.inspect(notices))

io.stdout:write("== a failed install is reported, and the next Zane file tries again\n")
vim.opt.runtimepath:append(assert(vim.env.NVIM_TREESITTER, "NVIM_TREESITTER is not set"))
vim.cmd("runtime! plugin/nvim-treesitter.lua")
-- A compiler commit that does not exist, so the download fails.
vim.api.nvim_create_autocmd("User", {
  pattern = "TSUpdate",
  callback = function()
    require("nvim-treesitter.parsers").zane.install_info.revision = string.rep("0", 40)
  end,
})
for attempt = 1, 2 do
  notices = {}
  vim.cmd("bwipeout!")
  vim.cmd.edit(fixture)
  assert(noticed("Installing the Zane parser..."), ("attempt %d did not install: %s"):format(attempt, vim.inspect(notices)))
  assert(vim.wait(120000, function() return noticed("Installing the Zane parser failed") end, 200), ("attempt %d: %s"):format(attempt, vim.inspect(notices)))
  assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "highlighting started without a parser")
end

io.stdout:write("== all passed\n")
