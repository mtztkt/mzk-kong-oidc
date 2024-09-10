local M = {}

local function shouldIgnoreRequest(patterns)
  if (patterns) then
    for _, pattern in ipairs(patterns) do
      local isMatching = not (string.find(ngx.var.uri, pattern) == nil)
      if (isMatching) then return true end
    end
  end
  return false
end

function M.shouldProcessRequest(config)
  return not shouldIgnoreRequest(config.filters)
end

local function shouldIgnoreRequestMethod(patterns)
  if (patterns) then
    for _, pattern in ipairs(patterns) do
      local isMatching = not (string.find(ngx.var.request_method, pattern) == nil)
      if (isMatching) then return true end
    end
  end
  return false
end

function M.shouldProcessRequestMethod(config)
  return  shouldIgnoreRequestMethod(config.ignore_request_methods)
end

local function shouldIgnoreServices(patterns)
  if (patterns) then
    local service = kong.router.get_service()
    for _, pattern in ipairs(patterns) do
      local isMatching = service.name == pattern
      if (isMatching) then return true end
    end
  end
  return false
end

function M.shouldProcessServices(config)
  return  shouldIgnoreServices(config.ignore_services)
end

local function shouldIgnoreRoutes(patterns)
  if (patterns) then
    local route = kong.router.get_route()
    for _, pattern in ipairs(patterns) do
      local isMatching = route.name == pattern
      if (isMatching) then return true end
    end
  end
  return false
end

function M.shouldProcessRoutes(config)
  return  shouldIgnoreRoutes(config.ignore_routes)
end


local function shouldIgnoreRequestRegex(patterns)
  if (patterns) then
    for _, pattern in ipairs(patterns) do
      local isMatching = string.match(kong.request.get_path(), pattern)
      if (isMatching) then return true end
    end
  end
  return false
end

function M.shouldProcessRequestRegex(config)
  return  shouldIgnoreRequestRegex(config.ignore_request_regex)
end

return M
