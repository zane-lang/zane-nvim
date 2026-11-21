-- A language server that stands in for `zane lsp` in the tests: run with
-- `nvim --headless -l tests/stub_server.lua LOG`. It writes its working
-- directory to LOG, answers `initialize` with hover support and every hover
-- with the text "stub hover", and exits on `exit`.
local log = assert(arg[1], "usage: stub_server.lua LOG")
local file = assert(io.open(log, "w"))
file:write(vim.uv.cwd(), "\n")
file:close()

local function send(message)
  local body = vim.json.encode(message)
  io.stdout:write(("Content-Length: %d\r\n\r\n%s"):format(#body, body))
  io.stdout:flush()
end

while true do
  local length
  while true do
    local line = io.stdin:read("*l")
    if not line then
      os.exit(1)
    end
    line = line:gsub("\r$", "")
    if line == "" then
      break
    end
    length = tonumber(line:match("^[Cc]ontent%-[Ll]ength:%s*(%d+)")) or length
  end
  local message = vim.json.decode(io.stdin:read(length))
  local method = message.method
  if method == "initialize" then
    send({ jsonrpc = "2.0", id = message.id, result = { capabilities = { hoverProvider = true } } })
  elseif method == "textDocument/hover" then
    send({ jsonrpc = "2.0", id = message.id, result = { contents = { kind = "plaintext", value = "stub hover" } } })
  elseif method == "exit" then
    os.exit(0)
  elseif message.id then
    send({ jsonrpc = "2.0", id = message.id, result = vim.NIL })
  end
end
