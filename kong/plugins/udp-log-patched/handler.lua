local BasePlugin = require "kong.plugins.base_plugin"
local serializer = require "kong.plugins.log-serializers.runscope"
local cjson = require "cjson"

local timer_at = ngx.timer.at
local udp = ngx.socket.udp

local string_find = string.find
local req_read_body = ngx.req.read_body
local req_get_headers = ngx.req.get_headers
local req_get_body_data = ngx.req.get_body_data

local UdpLogHandlerPatched = BasePlugin:extend()

UdpLogHandlerPatched.PRIORITY = 8

local function log(premature, conf, str)
  if premature then
    return
  end

  local sock = udp()
  sock:settimeout(conf.timeout)

  local ok, err = sock:setpeername(conf.host, conf.port)
  if not ok then
    ngx.log(ngx.ERR, "[udp-log] could not connect to ", conf.host, ":", conf.port, ": ", err)
    return
  end

  ok, err = sock:send(str)
  if not ok then
    ngx.log(ngx.ERR, " [udp-log] could not send data to ", conf.host, ":", conf.port, ": ", err)
  else
    ngx.log(ngx.DEBUG, "[udp-log] sent: ", str)
  end

  ok, err = sock:close()
  if not ok then
    ngx.log(ngx.ERR, "[udp-log] could not close ", conf.host, ":", conf.port, ": ", err)
  end
end

function UdpLogHandlerPatched:new()
  UdpLogHandlerPatched.super.new(self, "udp-log-patched")
end

function UdpLogHandlerPatched:log(conf)
  UdpLogHandlerPatched.super.log(self)

  local ok, err = timer_at(0, log, conf, cjson.encode(serializer.serialize(ngx)))
  if not ok then
    ngx.log(ngx.ERR, "[udp-log] could not create timer: ", err)
  end
end

function UdpLogHandlerPatched:access(conf)
  UdpLogHandlerPatched.super.access(self)

  local req_body, res_body = "", ""
  local req_post_args = {}

  req_read_body()
  req_body = req_get_body_data()


  -- keep in memory the bodies for this request
  ngx.ctx.runscope = {
    req_body = req_body,
    res_body = res_body,
    req_post_args = req_post_args
  }
end

function UdpLogHandlerPatched:body_filter(conf)
  UdpLogHandlerPatched.super.body_filter(self)

  local chunk = ngx.arg[1]
  local runscope_data = ngx.ctx.runscope or {res_body = ""} -- minimize the number of calls to ngx.ctx while fallbacking on default value
  runscope_data.res_body = runscope_data.res_body .. chunk
  ngx.ctx.runscope = runscope_data

end

return UdpLogHandlerPatched
