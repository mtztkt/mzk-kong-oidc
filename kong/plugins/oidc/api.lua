local handler = require "kong.plugins.oidc.handler"
local openidc = require "kong.plugins.oidc.openidc"
local http = require("resty.http")
local cjson = require("cjson")
local cjson_s = require("cjson.safe")
local function find_plugin()
    for plugin, err in kong.db.plugins:each() do
      if err then
        return nil, err
      end
  
      if plugin.name == "oidc" and plugin.enabled == true  and (plugin.service == nil or plugin.service.id == nil) then
        return plugin
      end
    end
  end

  local function openidc_parse_json_response(response, ignore_body_on_success)
    local ignore_body_on_success = ignore_body_on_success or false
  
    local err
    local res
  
    -- check the response from the OP
    if response.status ~= 200 then
      err = "response indicates failure, status=" .. response.status .. ", body=" .. response.body
    else
      if ignore_body_on_success then
        return nil, nil
      end
  
      -- decode the response and extract the JSON object
      res = cjson_s.decode(response.body)
  
      if not res then
        err = "JSON decoding failed"
      end
    end
  
    return res, err
  end

  return {
    ["/token"] = {
      POST = function(self)
        local plugin, err = find_plugin()
        if err then
          return kong.response.exit(500, { message = err })
        elseif not plugin then
          kong.log.err('Plugin not found')
          return kong.response.exit(404)
        end
  
        local conf = plugin.config

        local discovery_doc, err = openidc.get_discovery_doc(conf)
        if err then
          kong.log.err('Discovery document retrieval for Bearer JWT verify failed')
          return kong.response.exit(404)
        end
       
        local body = {
            grant_type = "password",
            client_id = conf.client_id,
            client_secret = conf.client_secret,
            username = tostring(self.params.username),
            password = tostring(self.params.password),
            scope = (self.params.scope and tostring(self.params.scope)) or (conf.scope and conf.scope) or "openid email profile",
          }
        
        local headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
          }

        local httpc = http.new()
        local res, err = httpc:request_uri(discovery_doc.token_endpoint,  {
            method = "POST",
            body = ngx.encode_args(body),
            headers = headers,
            ssl_verify = (conf.ssl_verify ~= "no"),
            keepalive = (conf.keepalive ~= "no")
          })
          if not res then
            err = "accessing  endpoint (" .. discovery_doc.token_endpoint .. ") failed: " .. err
            kong.log.err( err)
            return kong.response.exit(404)
          end
          local parseResponse,parseError = openidc_parse_json_response(res)
          if parseError then 
              kong.log.err( parseError)
              return kong.response.exit(res.status)
          end
        return kong.response.exit(res.status,   parseResponse)
      end,
    }
  }
