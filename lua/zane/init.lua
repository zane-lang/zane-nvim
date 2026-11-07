-- Zane support for Neovim: filetype detection, Tree-sitter highlighting, the
-- `zane-bound?` query predicate, and the parser's registration with
-- nvim-treesitter, which downloads the grammar and queries from
-- zane-lang/compiler and builds the parser.
local M = {}

M.config = {
  -- Install the parser through nvim-treesitter the first time a Zane file is
  -- opened without one.
  auto_install = true,
}

-- Where nvim-treesitter gets the parser and the queries Neovim reads.
M.install_info = {
  url = "https://github.com/zane-lang/compiler",
  location = "editors/tree-sitter-zane",
  generate = true,
  generate_from_json = false,
  queries = "editors/neovim/queries",
}

local configured = false
local installing = false
local notified = {}

local function notify_once(key, message, level)
  if not notified[key] then
    notified[key] = true
    vim.notify(message, level or vim.log.levels.WARN, { title = "zane" })
  end
end

-- Registers the parser with nvim-treesitter (`main` branch), which fires
-- `User TSUpdate` before it reads its parser table.
local function register()
  local ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if ok then
    parsers.zane = { install_info = vim.deepcopy(M.install_info) }
  end
end

-- The query passes the grammar's binders and the node types that can hold one
-- as space-separated arguments; each distinct string is split once. A query
-- without them (one left over from a manual install) matches nothing.
local sets = {}
local function set(words)
  words = words or ""
  local result = sets[words]
  if not result then
    result = {}
    for word in words:gmatch("%S+") do
      result[word] = true
    end
    sets[words] = result
  end
  return result
end

-- (#zane-bound? @name "binders" "containers") holds when a binder of the
-- captured name is a child of one of the name's ancestors. Zane forbids a
-- local from shadowing a parameter, so that binder is the one the name refers
-- to.
--
-- The walk goes down from the root rather than up from the name: finding a
-- node's parent searches from the root each time, and a binder's siblings are
-- only scanned in a container, never in a long statement list.
local function bound(match, _, source, predicate)
  local binders, containers = set(predicate[3]), set(predicate[4])
  for _, node in ipairs(match[predicate[2]] or {}) do
    local name = vim.treesitter.get_node_text(node, source)
    local found = false
    local scope = node:tree():root()
    while scope and not scope:equal(node) and not found do
      if containers[scope:type()] then
        for child in scope:iter_children() do
          local binder = binders[child:type()] and child:named_child(0)
          if binder and vim.treesitter.get_node_text(binder, source) == name then
            found = true
            break
          end
        end
      end
      scope = scope:child_with_descendant(node)
    end
    if not found then
      return false
    end
  end
  return true
end

local function start(buf)
  return vim.treesitter.highlighter.active[buf] ~= nil or pcall(vim.treesitter.start, buf, "zane")
end

-- Installs the parser through nvim-treesitter, then starts highlighting in
-- every open Zane buffer.
function M.install()
  local ok, ts = pcall(require, "nvim-treesitter")
  if not ok or not ts.install then
    notify_once("no-ts", "Installing the Zane parser needs nvim-treesitter (main branch).", vim.log.levels.ERROR)
    return
  end
  if installing then
    return
  end
  installing = true
  vim.notify("Installing the Zane parser...", vim.log.levels.INFO, { title = "zane" })
  ts.install({ "zane" }):await(function(err, done)
    vim.schedule(function()
      installing = false
      if err or not done then
        local reason = err and (": " .. tostring(err)) or "; see :TSLog"
        vim.notify("Installing the Zane parser failed" .. reason, vim.log.levels.ERROR, { title = "zane" })
        return
      end
      -- nvim-treesitter's install directory may not have existed at startup:
      -- then it is either missing from 'runtimepath' or missing from Neovim's
      -- cache of its directories. Setting it again fixes both.
      local dir = vim.fs.dirname(require("nvim-treesitter.config").get_install_dir("parser"))
      vim.opt.runtimepath:remove(dir)
      vim.opt.runtimepath:prepend(dir)
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "zane" then
          start(buf)
        end
      end
    end)
  end)
end

local function attach(buf)
  if start(buf) then
    return
  end
  -- With a parser present, installing would not help: say what failed.
  -- language.add raises when it finds a parser it cannot load (a different
  -- ABI, a broken file), and returns nil when it finds none.
  local found, loaded = pcall(vim.treesitter.language.add, "zane")
  if not found then
    notify_once("load", "The Zane parser does not load: " .. tostring(loaded) .. "\nRun :TSUpdate zane, then restart Neovim.", vim.log.levels.ERROR)
    return
  end
  if loaded then
    local _, err = pcall(vim.treesitter.start, buf, "zane")
    notify_once("start", "Zane highlighting did not start: " .. tostring(err) .. "\nRun :checkhealth zane.", vim.log.levels.ERROR)
    return
  end
  if M.config.auto_install then
    M.install()
  else
    notify_once("missing", "No Zane parser is installed. Run :TSInstall zane.")
  end
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  if configured then
    return
  end
  configured = true

  vim.filetype.add({ extension = { zn = "zane", zane = "zane" } })
  vim.treesitter.query.add_predicate("zane-bound?", bound, { force = true })

  local group = vim.api.nvim_create_augroup("zane", { clear = true })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "TSUpdate", callback = register })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "zane",
    callback = function(args)
      attach(args.buf)
    end,
  })
end

return M
