local llm = require("kong.llm")
local helpers = require "spec.helpers"
local cjson = require "cjson"
local http_mock = require "spec.helpers.http_mock"
local pl_path = require "pl.path"

local PLUGIN_NAME = "ai-request-transformer"

local FORMATS = {
  openai = {
    __key__ = "ai-request-transformer",
    route_type = "llm/v1/chat",
    model = {
      name = "gpt-4",
      provider = "openai",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        __upstream_path = "/chat/openai",
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer openai-key",
    },
  },
  cohere = {
    __key__ = "ai-request-transformer",
    route_type = "llm/v1/chat",
    model = {
      name = "command",
      provider = "cohere",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        __upstream_path = "/chat/cohere",
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer cohere-key",
    },
  },
  anthropic = {
    __key__ = "ai-request-transformer",
    route_type = "llm/v1/chat",
    model = {
      name = "claude-2.1",
      provider = "anthropic",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        __upstream_path = "/chat/anthropic",
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer anthropic-key",
    },
  },
  azure = {
    __key__ = "ai-request-transformer",
    route_type = "llm/v1/chat",
    model = {
      name = "gpt-4",
      provider = "azure",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        __upstream_path = "/chat/azure",
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer azure-key",
    },
  },
  llama2 = {
    __key__ = "ai-request-transformer",
    route_type = "llm/v1/chat",
    model = {
      name = "llama2",
      provider = "llama2",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        __upstream_path = "/chat/llama2",
        llama2_format = "raw",
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer llama2-key",
    },
  },
  mistral = {
    __key__ = "ai-request-transformer",
    route_type = "llm/v1/chat",
    model = {
      name = "mistral",
      provider = "mistral",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        __upstream_path = "/chat/mistral",
        mistral_format = "ollama",
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer mistral-key",
    },
  },
}

local OPENAI_NOT_JSON = {
  route_type = "llm/v1/chat",
  __key__ = "ai-request-transformer",
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      __upstream_path = "/not-json",
    },
  },
  auth = {
    header_name = "Authorization",
    header_value = "Bearer openai-key",
  },
}

local REQUEST_BODY = [[
  {
    "persons": [
      {
        "name": "Kong A",
        "age": 31
      },
      {
        "name": "Kong B",
        "age": 42
      }
    ]
  }
]]

local EXPECTED_RESULT = {
  persons = {
    [1] = {
      age = 62,
      name = "Kong A"
    },
    [2] = {
      age = 84,
      name = "Kong B"
    },
  }
}

-- patches model.options.upstream_url once the base_url is
-- known at setup time
local function set_upstream_url(conf, base_url)
  local options = conf.model and conf.model.options
  if options and options.__upstream_path then
    options.upstream_url = base_url .. options.__upstream_path
    options.__upstream_path = nil
  end
end

local SYSTEM_PROMPT = "You are a mathematician. "
    .. "Multiply all numbers in my JSON request, by 2. Return me the JSON output only"


describe(PLUGIN_NAME .. ": (unit)", function()
  local mock
  local ai_proxy_fixtures_dir = pl_path.abspath("spec/fixtures/ai-proxy/")

  lazy_setup(function()
    local mock_port = helpers.get_available_port()

    local mock_base_url = "http://" .. helpers.mock_upstream_host .. ":" .. mock_port
    set_upstream_url(OPENAI_NOT_JSON, mock_base_url)
    for _, conf in pairs(FORMATS) do
      set_upstream_url(conf, mock_base_url)
    end

    mock = http_mock.new(mock_port, {
      ["~/chat/(?<provider>[a-z0-9]+)"] = {
        content = string.format([[
              local base_dir = "%s/"
              ngx.header["Content-Type"] = "application/json"

              local pl_file = require "pl.file"
              local json = require("cjson.safe")
              ngx.req.read_body()
              local body, err = ngx.req.get_body_data()
              body, err = json.decode(body)

              local token = ngx.req.get_headers()["authorization"]
              local token_query = ngx.req.get_uri_args()["apikey"]

              if token == "Bearer " .. ngx.var.provider .. "-key" or token_query == "$1-key" or body.apikey == "$1-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if err or (body.messages == ngx.null) then
                  ngx.status = 400
                  ngx.say(pl_file.read(base_dir .. ngx.var.provider .. "/llm-v1-chat/responses/bad_request.json"))
                else
                  ngx.status = 200
                  ngx.say(pl_file.read(base_dir .. ngx.var.provider .. "/request-transformer/response-in-json.json"))
                end

              else
                ngx.status = 401
                ngx.say(pl_file.read(base_dir .. ngx.var.provider .. "/llm-v1-chat/responses/unauthorized.json"))
              end
            ]], ai_proxy_fixtures_dir),
      },
      ["~/not-json"] = {
        content = string.format([[
              local base_dir = "%s/"
              local pl_file = require "pl.file"
              ngx.header["Content-Type"] = "application/json"
              ngx.print(pl_file.read(base_dir .. "openai/request-transformer/response-not-json.json"))
            ]], ai_proxy_fixtures_dir),
      },
    })

    assert(mock:start())
  end)

  lazy_teardown(function()
    assert(mock:stop())
  end)


  for name, format_options in pairs(FORMATS) do
    describe(name .. " transformer tests, exact json response", function()
      it("transforms request based on LLM instructions", function()
        local llmdriver = llm.new_driver(format_options, {})
        assert.truthy(llmdriver)

        local result, err = llmdriver:ai_introspect_body(
          REQUEST_BODY,      -- request body
          SYSTEM_PROMPT,     -- conf.prompt
          {},                -- http opts
          nil                -- transformation extraction pattern
        )

        assert.is_nil(err)

        result, err = cjson.decode(result)
        assert.is_nil(err)

        assert.same(EXPECTED_RESULT, result)
      end)
    end)
  end

  describe("openai transformer tests, pattern matchers", function()
    it("transforms request based on LLM instructions, with json extraction pattern", function()
      local llmdriver = llm.new_driver(OPENAI_NOT_JSON, {})
      assert.truthy(llmdriver)

      local result, err = llmdriver:ai_introspect_body(
        REQUEST_BODY,         -- request body
        SYSTEM_PROMPT,        -- conf.prompt
        {},                   -- http opts
        "\\{((.|\n)*)\\}"     -- transformation extraction pattern (loose json)
      )

      assert.is_nil(err)

      result, err = cjson.decode(result)
      assert.is_nil(err)

      assert.same(EXPECTED_RESULT, result)
    end)

    it("transforms request based on LLM instructions, but fails to match pattern", function()
      local llmdriver = llm.new_driver(OPENAI_NOT_JSON, {})
      assert.truthy(llmdriver)

      local result, err = llmdriver:ai_introspect_body(
        REQUEST_BODY,      -- request body
        SYSTEM_PROMPT,     -- conf.prompt
        {},                -- http opts
        "\\#*\\="          -- transformation extraction pattern (loose json)
      )

      assert.is_nil(result)
      assert.is_not_nil(err)
      assert.same("AI response did not match specified regular expression", err)
    end)     -- it
  end)
end)
