-- A language server that stands in for `zane lsp` in the tests: run with
-- `nvim --headless -l tests/stub_server.lua LOG [DELAY]`. It writes its
-- working directory to LOG, answers `initialize` with hover support, after
-- DELAY milliseconds when given, answers every hover with the text "stub
-- hover", and exits on `exit`.
local log = assert(arg[1], "usage: stub_server.lua LOG [DELAY]")
local delay = tonumber(arg[2])
local file = assert(io.open(log, "w"))
file:write(vim.uv.cwd(), "\n")
file:close()

local function send(message)
  local body = vim.json.encode(message)
  io.stdout:write(("Content-Length: %d\r\n\r\n%s"):format(#body, body))
  io.stdout:flush()
end

local function handle(message)
  local method = message.method
  if method == "initialize" then
    if delay then
      -- A timer rather than a sleep, so the event loop still handles the
      -- signal a client sends to stop the server meanwhile.
      vim.defer_fn(function()
        send({ jsonrpc = "2.0", id = message.id, result = { capabilities = { hoverProvider = true } } })
      end, delay)
    else
      send({ jsonrpc = "2.0", id = message.id, result = { capabilities = { hoverProvider = true } } })
    end
  elseif method == "textDocument/hover" then
    send({ jsonrpc = "2.0", id = message.id, result = { contents = { kind = "plaintext", value = "stub hover" } } })
  elseif method == "exit" then
    os.exit(0)
  elseif message.id then
    send({ jsonrpc = "2.0", id = message.id, result = vim.NIL })
  end
end

-- Standard input is read through the event loop, never by a blocking read,
-- so the server exits on SIGTERM as a real server does.
local pending = ""
local stdin = assert(vim.uv.new_pipe(false))
stdin:open(0)
stdin:read_start(function(err, chunk)
  if err or not chunk then
    os.exit(1)
  end
  pending = pending .. chunk
  while true do
    local header_end = pending:find("\r\n\r\n", 1, true)
    if not header_end then
      return
    end
    local length = tonumber(pending:sub(1, header_end):match("[Cc]ontent%-[Ll]ength:%s*(%d+)"))
    local body_start = header_end + 4
    if #pending < body_start + length - 1 then
      return
    end
    local body = pending:sub(body_start, body_start + length - 1)
    pending = pending:sub(body_start + length)
    vim.schedule(function()
      handle(vim.json.decode(body))
    end)
  end
end)

-- A client stops a server that has not initialized with SIGTERM.
local term = assert(vim.uv.new_signal())
term:start("sigterm", function()
  os.exit(0)
end)

vim.wait(math.huge, function()
  return false
end)
