local lu = require("luaunit")
TestHandler = require("test.unit.mockable_case"):extend()


function TestHandler:setUp()
  TestHandler.super:setUp()

  package.loaded["resty.openidc"] = nil
  self.module_resty = {openidc = {
    authenticate = function(...) return {}, nil end }
  }
  package.preload["resty.openidc"] = function()
    return self.module_resty.openidc
  end

  self.handler = require("kong.plugins.oidc.handler")()
end

function TestHandler:tearDown()
  TestHandler.super:tearDown()
end

function TestHandler:test_authenticate_ok_no_userinfo()
  self.module_resty.openidc.authenticate = function(opts)
    return { id_token = { sub = "sub"}}, false
  end

  self.handler:access({disable_id_token_header = "yes"})
  lu.assertTrue(self:log_contains("calling authenticate"))
end

function TestHandler:test_authenticate_ok_with_userinfo()
  self.module_resty.openidc.authenticate = function(opts)
    return {user = {sub = "sub"}}, false
  end
  ngx.encode_base64 = function(x)
    return "eyJzdWIiOiJzdWIifQ=="
  end

  local headers = {}
  kong.service.request.set_header = function(name, value) headers[name] = value end

  self.handler:access({userinfo_header_name = 'X-Userinfo'})
  lu.assertTrue(self:log_contains("calling authenticate"))
  lu.assertEquals(ngx.ctx.authenticated_credential.id, "sub")
  lu.assertEquals(headers['X-Userinfo'], "eyJzdWIiOiJzdWIifQ==")
end

function TestHandler:test_authenticate_ok_with_no_accesstoken()
  self.module_resty.openidc.authenticate = function(opts)
    return {id_token = {sub = "sub"}}, true
  end

  local headers = {}
  kong.service.request.set_header = function(name, value) headers[name] = value end

  self.handler:access({disable_id_token_header = "yes"})
  lu.assertTrue(self:log_contains("calling authenticate"))
  lu.assertNil(headers['X-Access-Token'])
end

function TestHandler:test_authenticate_ok_with_accesstoken()
  self.module_resty.openidc.authenticate = function(opts)
    return {id_token = { sub = "sub" } , access_token = "ACCESS_TOKEN"}, false
  end

  local headers = {}
  kong.service.request.set_header = function(name, value) headers[name] = value end

  self.handler:access({access_token_header_name = 'X-Access-Token', disable_id_token_header = "yes"})  
  lu.assertTrue(self:log_contains("calling authenticate"))
  lu.assertEquals(headers['X-Access-Token'], "ACCESS_TOKEN")
end

function TestHandler:test_authenticate_ok_with_no_idtoken()
  self.module_resty.openidc.authenticate = function(opts)
    return {}, false
  end

  local headers = {}
  kong.service.request.set_header = function(name, value) headers[name] = value end

  self.handler:access({})
  lu.assertTrue(self:log_contains("calling authenticate"))
  lu.assertNil(headers['X-ID-Token'])
end

function TestHandler:test_authenticate_ok_with_idtoken()
  self.module_resty.openidc.authenticate = function(opts)
    return {id_token = {sub = "sub"}}, false
  end

  ngx.encode_base64 = function(x)
    return "eyJzdWIiOiJzdWIifQ=="
  end

  local headers = {}
  kong.service.request.set_header = function(name, value) headers[name] = value end

  self.handler:access({id_token_header_name = 'X-ID-Token'})
  lu.assertTrue(self:log_contains("calling authenticate"))
  lu.assertEquals(headers['X-ID-Token'], "eyJzdWIiOiJzdWIifQ==")
end

function TestHandler:test_authenticate_nok_no_recovery()
  self.module_resty.openidc.authenticate = function(opts)
    return nil, true
  end

  self.handler:access({})
  lu.assertTrue(self:log_contains("calling authenticate"))
end

function TestHandler:test_authenticate_nok_deny()
  self.module_resty.openidc.authenticate = function(opts)
    if opts.unauth_action == "deny" then
		  return nil, "unauthorized request"
	  end
	  return {}, true
  end

  self.handler:access({unauth_action = "deny"})
  lu.assertEquals(ngx.status, ngx.HTTP_UNAUTHORIZED)
end

function TestHandler:test_authenticate_nok_with_recovery()
  self.module_resty.openidc.authenticate = function(opts)
    return nil, true
  end

  self.handler:access({recovery_page_path = "x"})
  lu.assertTrue(self:log_contains("recovery page"))
end

function TestHandler:test_introspect_ok_no_userinfo()
  self.module_resty.openidc.introspect = function(opts)
    return false, false
  end
  ngx.req.get_headers = function() return {Authorization = "Bearer xxx"} end

  self.handler:access({introspection_endpoint = "x"})
  lu.assertTrue(self:log_contains("introspect succeeded"))
end

function TestHandler:test_introspect_ok_with_userinfo()
  self.module_resty.openidc.introspect = function(opts)
    return {}, false
  end
  ngx.req.get_headers = function() return {Authorization = "Bearer xxx"} end

  ngx.encode_base64 = function(x)
    return "eyJzdWIiOiJzdWIifQ=="
  end

  local headers = {}
  kong.service.request.set_header = function(name, value) headers[name] = value end

  self.handler:access({introspection_endpoint = "x", userinfo_header_name = "X-Userinfo"})
  lu.assertTrue(self:log_contains("introspect succeeded"))
  lu.assertEquals(headers['X-Userinfo'], "eyJzdWIiOiJzdWIifQ==")
end

function TestHandler:test_bearer_only_with_good_token()
  self.module_resty.openidc.introspect = function(opts)
    return {sub = "sub"}, false
  end
  ngx.req.get_headers = function() return {Authorization = "Bearer xxx"} end

  ngx.encode_base64 = function(x)
    return "eyJzdWIiOiJzdWIifQ=="
  end

  local headers = {}
  kong.service.request.set_header = function(name, value) headers[name] = value end

  self.handler:access({introspection_endpoint = "x", bearer_only = "yes", realm = "kong", userinfo_header_name = "X-Userinfo"})
  lu.assertTrue(self:log_contains("introspect succeeded"))
  lu.assertEquals(headers['X-Userinfo'], "eyJzdWIiOiJzdWIifQ==")
end

function TestHandler:test_bearer_only_with_bad_token()
  self.module_resty.openidc.introspect = function(opts)
    return {}, "validation failed"
  end
  ngx.req.get_headers = function() return {Authorization = "Bearer xxx"} end

  self.handler:access({introspection_endpoint = "x", bearer_only = "yes", realm = "kong", userinfo_header_name = 'X-Userinfo'})

  lu.assertEquals(ngx.header["WWW-Authenticate"], 'Bearer realm="kong",error="validation failed"')
  lu.assertEquals(ngx.status, ngx.HTTP_UNAUTHORIZED)
  lu.assertFalse(self:log_contains("introspect succeeded"))
end

function TestHandler:test_introspect_bearer_token_and_property_mapping()
  self.module_resty.openidc.bearer_jwt_verify = function(opts)
    return {foo = "bar"}, false
  end
  ngx.req.get_headers = function() return {Authorization = "Bearer xxx"} end

  ngx.encode_base64 = function(x) return "x" end

  local headers = {}
  kong.service.request.set_header = function(name, value) headers[name] = value end

  self.handler:access({introspection_endpoint = "x", bearer_only = "yes", use_jwks = "yes", disable_userinfo_header = "yes", header_names = {'X-Foo', 'present'}, header_claims = {'foo', 'not'}})
  lu.assertEquals(headers["X-Foo"], 'bar')
  lu.assertNil(headers["present"])
end

function TestHandler:test_introspect_bearer_token_and_incorrect_property_mapping()
  self.module_resty.openidc.bearer_jwt_verify = function(opts)
    return {foo = "bar"}, false
  end
  ngx.req.get_headers = function() return {Authorization = "Bearer xxx"} end

  ngx.encode_base64 = function(x) return "x" end

  local headers = {}
  kong.service.request.set_header = function(name, value) headers[name] = value end

  self.handler:access({introspection_endpoint = "x", bearer_only = "yes", use_jwks = "yes", disable_userinfo_header = "yes", header_names = {'X-Foo'}, header_claims = {'foo', 'incorrect'}})
  lu.assertNil(headers["X-Foo"])
end

function TestHandler:test_introspect_bearer_token_and_scope_nok()
  self.module_resty.openidc.bearer_jwt_verify = function(opts)
    return {scope = "foo"}, false
  end
  ngx.req.get_headers = function() return {Authorization = "Bearer xxx"} end

  ngx.encode_base64 = function(x) return "x" end

  self.handler:access({introspection_endpoint = "x", bearer_only = "yes", use_jwks = "yes", userinfo_header_name = "X-Userinfo", validate_scope = "yes", scope = "bar"})
  lu.assertEquals(ngx.status, ngx.HTTP_FORBIDDEN)
end

function TestHandler:test_introspect_bearer_token_and_empty_scope_nok()
  self.module_resty.openidc.bearer_jwt_verify = function(opts)
    return {foo = "bar"}, false
  end
  ngx.req.get_headers = function() return {Authorization = "Bearer xxx"} end

  ngx.encode_base64 = function(x) return "x" end

  self.handler:access({introspection_endpoint = "x", bearer_only = "yes", use_jwks = "yes", userinfo_header_name = "X-Userinfo", validate_scope = "yes", scope = "bar"})
  lu.assertEquals(ngx.status, ngx.HTTP_FORBIDDEN)
end

function TestHandler:test_introspect_bearer_token_and_scope_ok()
  self.module_resty.openidc.bearer_jwt_verify = function(opts)
    return {scope = "foo bar"}, false
  end
  ngx.req.get_headers = function() return {Authorization = "Bearer xxx"} end

  ngx.encode_base64 = function(x) return "x" end

  self.handler:access({introspection_endpoint = "x", bearer_only = "yes", use_jwks = "yes", userinfo_header_name = "X-Userinfo", validate_scope = "yes", scope = "bar"})
  lu.assertNotEquals(ngx.status, ngx.HTTP_FORBIDDEN)
  lu.assertNotEquals(ngx.status, ngx.HTTP_INTERNAL_SERVER_ERROR)
end

lu.run()
