-- F3 to inspect tree
-- TODO 
-- header value must be single line
local utils = require("rest-nvim.utils")
-- local path = require("plenary.path")
local log = require("plenary.log").new({ plugin = "rest.nvim" })
-- local config = require("rest-nvim.config")

local ts = vim.treesitter
-- local ts_utils = require 'nvim-treesitter.ts_utils'

local parser_name = "http"

local M = {}

local function print_node(title, node)
  print(string.format("%s: type '%s' isNamed '%s' with %d children", title, node:type(), node:named()
    , node:child_count()))
end

-- return the lua script code if any
-- ideally we could have several
local function ts_load_script(qnode)
  log.debug("Loading script")
  -- TODO
  -- load_raw
  print("Looking for script")
  for node, name in qnode:iter_children() do
    -- print("type", node:type(), "NAME: ", name)

    -- wont work, it needs to be "script"
    if node:type() == "script" then
      -- print("type", node:type(), "NAME: ", node:named())
      return node

      -- node:field("internal_script")
      -- local internal_script = node:child(0)
      -- -- TODO there are lots of errors which breaks the stuff
      -- print("number of children ", node:child_count())
      -- print("Internal ?", vim.inspect(internal_script))
      -- print("Internal ?", internal_script)
      -- print_node("found internal script: ", internal_script)
      -- return internal_script
    end
  end
end

M.buf_get_current_request = function(bufnr)
  log.debug("Getting current request")

  -- old implementation
  -- return M.buf_get_request(vim.api.nvim_win_get_buf(0), vim.fn.getcurpos())
  local query_node = M.buf_get_request_at_node(bufnr, vim.treesitter.get_node({
    pos = vim.fn.getcurpos();
  }))
  print("buf_get_current_request", query_node:type())
  if not query_node then
    local msg = "Could not find any query"
    vim.notify(msg)
    log.warn(msg)
  end
  local result = M.ts_build_request_from_node(query_node, 0)
  M.print_request(result)
  return true, result
end

M.buf_get_request_at_node = function(_bufnr, start_node)
  log.debug("buf_get_request_at_node")
  -- local parser = ts.get_parser(0, "http")
  -- local root = parser:parse()[1]:root()

  print("start node type", start_node:type())
  local node = start_node
  while node ~= nil and node:type() ~= "query" do
    print("node before", node:type())
    node = node:parent()

    -- node = ts_utils.get_previous_node(node, true, true)
    -- print("node after", node:type())
  end
  -- print("out of loop node", node:type())
  return node
end

-- buf_get_request returns a table with all the request settings
-- @param bufnr (number|nil) the buffer number
-- @param pos (optional) the cursor position, by default the cursor position
-- @return (boolean, request or string)
M.buf_get_request_at_pos = function(bufnr, pos)
  pos = pos or vim.fn.getcurpos()
  bufnr = bufnr or vim.api.nvim_win_get_buf(0)
  --
  local node = M.get_node_at_pos(bufnr, pos[1] - 1, pos[2], { ignore_injections = false }):type()
  return M.buf_get_request(bufnr, node)

end

-- to remove
M.print_request = function(req)
  print(M.stringify_request(req))
end


local function ts_get_body(bufnr, qnode, vars, _has_json)
  local lines
  -- local body_node
  -- iter direct children
  log.debug("Looking for body")
  for node, _name in qnode:iter_children(qnode) do
    -- print("type", node:type(), "NAME: ", name)
    if node:type() == "body" then
      -- there should be only one child ?
      local body = node:child(0)
      local payload_file_fields = body:field("payload_file")
      -- print("number of children ", body:type())
      -- print("number of fields payload_file ", vim.inspect(body:field("payload_file")))
      if #payload_file_fields > 0 then
        local payload_file_node = payload_file_fields[1]
        print_node("payload file node ?", payload_file_node)
        -- print_node("found payload node: ", node)
        -- replace the filename with variables than load the file
        local raw_filename = vim.treesitter.get_node_text(payload_file_node, bufnr)
        -- local final_filename = utils.replace_vars(raw_filename, vars)
        -- TODO move code ?
        local importfile = load_importfile_name(bufnr, raw_filename, vars)
        if importfile ~= nil then
          if not utils.file_exists(importfile) then
            error("import file " .. importfile .. " not found")
          end
          lines = utils.read_file(importfile)
          -- print("LINES", lines)
          local res = encode_json(table.concat(lines, "\n"),_has_json)
          return res
          -- return lines
        end
      end

    end
  end
end

-- Build a rest.nvim request from a treesitter query
-- @param node a treeitter node of type "query" TODO assert/check
-- @param bufnr
M.ts_build_request_from_node = function(reqnode, bufnr)
  assert(reqnode:type() == "query")

  -- log.debug('building request_from_node')
  local vars = utils.read_variables()

  -- named_child(0)
  -- local reqnode = tsnode:child(0)
  -- local id = "toto"
  print_node("reqnode", reqnode)

  -- Returns a table of the nodes corresponding to the {name} field.
  local methodfields = reqnode:field("request")
  local methodnode = methodfields[1]:field("method")[1]
  local urlnode = methodfields[1]:field('url')[1]
  print("url content ?", vim.treesitter.get_node_text(urlnode, bufnr))
  local url = vim.treesitter.get_node_text(urlnode, bufnr)
  url = utils.replace_vars(url, vars)

  -- TODO splice header variables/pass variables
  local headers = M.ts_get_headers(reqnode, bufnr)
  local headers_spliced = {}
  for name, value in pairs(headers) do
    headers_spliced[name] = utils.replace_vars(value, vars)
  end

  -- if not utils.contains_comments(header_name) then
  --   headers[header_name] = utils.replace_vars(header_value)
  -- end

  -- HACK !!!
  -- Because we have trouble catching the body through tree-sitter
  -- we just look set the end_line to the (beginning -1) line of the next request
  -- or the last line if there are no other requests
  local end_line = vim.fn.line("$")

  -- TODO look for next_sibling of same type query
  local nextreq = reqnode:next_sibling()
  while nextreq and nextreq:type() ~= "query" do
    nextreq = nextreq:next_sibling()
  end

  -- print_node("reqnode ", reqnode)
  -- print_node("next query", nextreq)
  if nextreq then
    -- print("Found another sibling", nextreq:id())
    -- print_node("final nextreq", nextreq)
    end_line = nextreq:start() - 1
  else
    print("found no other sibling")
  end

  --
  -- local curl_args, body_start = get_curl_args(bufnr, headers_end, end_line)
  local script_str
  local script_node = ts_load_script(reqnode)
  if script_node then
    script_str = vim.treesitter.get_node_text(script_node, bufnr)

    -- THIS IS A HACK until I can retrieve internal_script properly !
    script_str = script_str:match("{%%(.-)%%}")
    print("using SCRIPT_STR:", script_str)

    log.debug("Using script_str", script_str)
  end

  -- sounds like a bug, it should be + 1 ?
  -- local headers_end = reqnode:end_() + 2

  -- TODO wip
  local body = ts_get_body(
    bufnr,
    reqnode,
    vars,
    -- TODO assume json for now but we should look at headers ctype
    true
  )

  -- load the body
  -- if script_node then
  --   script_str = vim.treesitter.get_node_text(script_node, bufnr)
  -- end

  -- local body = get_body(
  --   bufnr,
  --   vars,
  --   headers_end,
  --   end_line,
  --   true -- assume json for now
  --   -- content_type:find("application/[^ ]*json")
  -- )

  print("RETURNED BODY", body)

  -- local script_str = get_response_script(bufnr,headers_end, end_line)

  return {
    method = vim.treesitter.get_node_text(methodnode, bufnr),
    url = url,
    -- TODO found from parse_url but should use ts as well:
    -- methodnode:field('http_version')[1],
    http_version = nil,
    headers = headers_spliced,
    -- TODO build curl_args from 'headers'
    -- I dont really care about that so I left it
    raw = nil,
    -- TODO check if body is full string ?
    body = body,
    bufnr = bufnr,
    start_line = reqnode:start(),
    -- le end line is computed
    end_line = end_line,
    -- todo
    script_str = script_str

  }
end

-- TODO we should return headers for query
M.ts_get_headers = function(qnode, bufnr)
  -- local parser = ts.get_parser(bufnr, "http")
  -- print("PARSER", parser)
  local query = [[
      (header) @headers
  ]]

  local parsed_query = ts.query.parse(parser_name, query)
  -- print(vim.inspect(parsed_query))
  -- local start_row, _, end_row, _ = qnode:range()
  -- print("start row", start_row, "end row", end_row)

  local headers = {}
  for _id, headernode, _metadata in parsed_query:iter_captures(qnode, bufnr) do
    -- local name = parsed_query.captures[id] -- name of the capture in the query
    -- M.ts_build_request_from_node(tsnode, bufnr)
    -- print_node("header node", headernode)
    -- Returns a table of the nodes corresponding to the {name} field.

    local hnamenode = headernode:field("name")[1]
    local hname = vim.treesitter.get_node_text(hnamenode, bufnr)
    local valuenode = headernode:field("value")[1]
    local value = vim.treesitter.get_node_text(valuenode, bufnr)
    -- TODO splice value variables !
    headers[hname] = value
  end
  return headers
end

M.buf_get_requests = function(bufnr)
  bufnr = bufnr or 0

  print("GET REQUESTS for buffer ", bufnr)
  -- local parser = ts.get_parser(bufnr, "http")
  -- print("PARSER", parser)
  local query = [[
      (query) @queries
  ]]
  -- parse returns a list of ts trees
  -- root is a node
  -- local root = parser:parse()[1]:root()
  -- local start_row, _, end_row, _ = root:range()

  -- local start_node = root
  -- find upstream replacement
  local start_node = ts_utils.get_node_at_cursor()
  -- print_node("Node at cursor", start_node)
  -- print("sexpr: " .. start_node:sexpr())
  local parsed_query = ts.query.parse(parser_name, query)
  -- print(vim.inspect(parsed_query))
  -- print("start row", start_row, "end row", end_row)
  -- print_node("root", root)
  local requests = {}
  -- , start_row, end_row
  for _id, tsnode, _metadata in parsed_query:iter_captures(start_node, bufnr) do
    -- local name = parsed_query.captures[id] -- name of the capture in the query

    requests[#requests] = M.ts_build_request_from_node(tsnode, bufnr)
  end

  return requests
end

