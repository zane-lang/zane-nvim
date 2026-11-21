-- The language server client: run with `nvim --headless -u NONE -l tests/lsp.lua`
-- from the repository root. A stub server stands in for `zane lsp`, so the
-- test needs neither zane nor nvim-treesitter.
local root = vim.fn.getcwd()
vim.opt.runtimepath:append(root)
vim.cmd("runtime! plugin/**/*.lua")
vim.cmd("filetype on")
vim.notify = function(message)
  io.stdout:write(message .. "\n")
end

local function step(name)
  io.stdout:write("== " .. name .. "\n")
end

local dir = vim.fn.tempname()
local project = dir .. "/project"
vim.fn.mkdir(project .. "/bin/app", "p")
vim.fn.writefile({ "zane-version v0.1" }, project .. "/zane.coda")
vim.fn.writefile({ "package app;" }, project .. "/bin/app/main.zn")
vim.fn.writefile({ "package loose;" }, dir .. "/loose.zn")
project = vim.uv.fs_realpath(project)
local log = dir .. "/server.log"
local stub = { vim.v.progpath, "--headless", "-u", "NONE", "-l", root .. "/tests/stub_server.lua", log }

local function clients(buf)
  return vim.lsp.get_clients({ bufnr = buf, name = "zane" })
end

local function wait_attached(buf)
  assert(vim.wait(10000, function() return #clients(buf) > 0 end, 50), "the server did not attach")
  return clients(buf)[1]
end

step("a Zane file in a project starts the server at the project's root")
require("zane").setup({ auto_install = false, lsp = { cmd = stub } })
vim.cmd.edit(project .. "/bin/app/main.zn")
local buf = vim.api.nvim_get_current_buf()
local client = wait_attached(buf)
assert(client.root_dir == project, "root_dir is " .. tostring(client.root_dir))
assert(vim.wait(5000, function() return vim.fn.filereadable(log) == 1 end), "the server wrote no log")
assert(vim.fn.readfile(log)[1] == project, "the server runs in " .. vim.fn.readfile(log)[1])
local result = client:request_sync("textDocument/hover", vim.lsp.util.make_position_params(0, client.offset_encoding), 5000, buf)
assert(result and result.result.contents.value == "stub hover", vim.inspect(result))

step("a Zane file outside every project gets a server with no root")
vim.cmd.edit(dir .. "/loose.zn")
local loose = wait_attached(vim.api.nvim_get_current_buf())
assert(loose.root_dir == nil, "root_dir is " .. tostring(loose.root_dir))

local function all_clients()
  return vim.lsp.get_clients({ name = "zane", _uninitialized = true })
end

local function stop_all()
  for _, c in ipairs(all_clients()) do
    c:stop(true)
  end
  assert(vim.wait(10000, function() return #all_clients() == 0 end, 50), "a server still runs")
end

-- Opens main.zn with a server whose initialize answer comes after a delay,
-- and returns once that server's client exists, still initializing.
local slow_log = dir .. "/slow.log"
local slow = { vim.v.progpath, "--headless", "-u", "NONE", "-l", root .. "/tests/stub_server.lua", slow_log, "3000" }
local function open_with_slow_server()
  stop_all()
  vim.cmd("silent! %bwipeout!")
  require("zane").setup({ lsp = { cmd = slow } })
  vim.cmd.edit(project .. "/bin/app/main.zn")
  assert(vim.wait(5000, function() return #all_clients() == 1 end, 20), "no server started")
  assert(not all_clients()[1].initialized, "the slow server answered at once")
end

step("lsp = false stops a server that is still initializing")
open_with_slow_server()
require("zane").setup({ lsp = false })
assert(vim.wait(2000, function() return #all_clients() == 0 end, 20), "the initializing server still runs")
vim.wait(3500)
assert(#all_clients() == 0, "the initializing server attached after lsp = false")

step("a new command replaces a server that is still initializing")
open_with_slow_server()
vim.fn.delete(log)
require("zane").setup({ lsp = { cmd = stub } })
local replaced = wait_attached(vim.api.nvim_get_current_buf())
assert(vim.wait(5000, function() return vim.fn.filereadable(log) == 1 end), "the new command did not start")
vim.wait(3500)
assert(#all_clients() == 1 and all_clients()[1].id == replaced.id, "the old server is still running")

step("a later setup call drops the options of an earlier one")
stop_all()
vim.cmd("silent! %bwipeout!")
require("zane").setup({ lsp = { cmd = stub, cmd_cwd = dir } })
require("zane").setup({ lsp = { cmd = stub } })
vim.fn.delete(log)
vim.cmd.edit(project .. "/bin/app/main.zn")
wait_attached(vim.api.nvim_get_current_buf())
assert(vim.wait(5000, function() return vim.fn.filereadable(log) == 1 end), "the server wrote no log")
assert(vim.fn.readfile(log)[1] == project, "the server runs in " .. vim.fn.readfile(log)[1])
require("zane").setup({ lsp = { cmd = stub } })

step("lsp = false stops the server and starts none for the next file")
require("zane").setup({ lsp = false })
assert(vim.wait(10000, function() return #vim.lsp.get_clients({ name = "zane" }) == 0 end, 50), "the server still runs")
vim.cmd.edit(project .. "/bin/app/main.zn")
vim.wait(500)
assert(#clients(vim.api.nvim_get_current_buf()) == 0, "a server started with lsp = false")
vim.cmd("checkhealth zane")
local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(report:find("the language server is off", 1, true), report)
vim.cmd("bwipeout")

step("a missing command starts no server, and :checkhealth zane warns about it")
require("zane").setup({ lsp = { cmd = { "zane-not-installed", "lsp" } } })
vim.cmd.edit(project .. "/bin/app/main.zn")
vim.wait(500)
assert(#vim.lsp.get_clients({ name = "zane" }) == 0, "a server started without its command")
vim.cmd("checkhealth zane")
report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(report:find("zane-not-installed not found, so the language server does not start", 1, true), report)

vim.fn.delete(dir, "rf")
io.stdout:write("== all passed\n")
