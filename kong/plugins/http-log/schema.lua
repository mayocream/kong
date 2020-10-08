local typedefs = require "kong.db.schema.typedefs"
local null = ngx.null

return {
  name = "http-log",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          -- NOTE: any field added here must be also included in the handler's get_queue_id method
          { http_endpoint = typedefs.url({ required = true }) },
          { method = { type = "string", default = "POST", one_of = { "POST", "PUT", "PATCH" }, }, },
          { content_type = { type = "string", default = "application/json", one_of = { "application/json" }, }, },
          { timeout = { type = "number", default = 10000 }, },
          { keepalive = { type = "number", default = 60000 }, },
          { retry_count = { type = "integer", default = 10 }, },
          { queue_size = { type = "integer", default = 1 }, },
          { flush_timeout = { type = "number", default = 2 }, },
          { header_name = typedefs.header_name({ default = "Authorization"}), },
          { header_value = { type = "string" }, },
        },
        entity_checks = {
          -- header_name is required when header value is given
          { conditional = {
            if_field = "header_value", if_match = { ne = null },
            then_field = "header_name", then_match = { required = true },
          }, }, },
    }, },
  },
}
