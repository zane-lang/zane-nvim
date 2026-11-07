-- :checkhealth zane
local M = {}

function M.check()
  local health = vim.health
  health.start("zane")

  -- nvim-treesitter's main branch needs Neovim 0.12.
  if vim.fn.has("nvim-0.12") == 1 then
    health.ok("Neovim 0.12 or newer")
  else
    health.error("Neovim 0.12 or newer is required")
  end

  if pcall(require, "nvim-treesitter.config") then
    health.ok("nvim-treesitter (main branch) installs the parser")
  else
    health.error("nvim-treesitter (main branch) not found", { "It downloads, builds and installs the Zane parser." })
  end

  for _, tool in ipairs({ "tree-sitter", "curl", "tar" }) do
    local path = vim.fn.exepath(tool)
    if path == "" then
      health.warn(tool .. " not on PATH", { "nvim-treesitter needs it to install the Zane parser." })
    elseif tool == "tree-sitter" then
      -- nvim-treesitter's minimum, which generates with the built-in JavaScript runtime.
      local out = vim.system({ path, "--version" }, { text = true }):wait().stdout or ""
      local version = vim.version.parse(out:match("%d+%.%d+%.%d+") or "")
      if version and vim.version.ge(version, { 0, 26, 1 }) then
        health.ok(("tree-sitter %s: %s"):format(tostring(version), path))
      else
        health.warn(("tree-sitter at %s is %s; 0.26.1 or newer is needed"):format(path, version and tostring(version) or "an unknown version"))
      end
    else
      health.ok(tool .. ": " .. path)
    end
  end

  -- add returns nil and a message when no parser is found, and raises when
  -- one is found but cannot be loaded (for example a different ABI).
  local ok, loaded, err = pcall(vim.treesitter.language.add, "zane")
  if not ok then
    health.error("the Zane parser does not load: " .. tostring(loaded), { "Run :TSUpdate zane." })
    return
  elseif not loaded then
    health.error("no Zane parser installed" .. (err and (": " .. err) or ""), { "Open a .zn file, or run :TSInstall zane." })
    return
  end
  health.ok("Zane parser loads")

  local found, query = pcall(vim.treesitter.query.get, "zane", "highlights")
  if found and query then
    health.ok("highlight queries load")
  else
    health.error("highlight queries do not load: " .. tostring(query), {
      "The parser and queries may come from different compiler versions. Run :TSUpdate zane.",
    })
  end
end

return M
