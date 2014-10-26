local Mock = {}

local subscriber

function handleMockCalls(callback, thunk)
  subscriber = callback
  thunk()
  subscriber = nil
end

function mockCalled(m, name, args)
  return subscriber(m, name, args)
end

local ExpectedCall = {}

local ExpectedCallApi = {}
ExpectedCallApi.__index = ExpectedCallApi

function ExpectedCall.create(f, required, args)
  local o = {
    _f = f,
    _ordered = false,
    _required = required,
    _args = args,
    _return = {}
  }

  setmetatable(o, ExpectedCallApi)

  return o
end

function ExpectedCallApi:functionMatches(f)
  return f == self._f
end

function ExpectedCallApi:argsMatch(args)
  if #self._args ~= #args then return false end

  for k in ipairs(self._args) do
    if self._args[k] ~= args[k] then return false end
  end

  return true
end

function ExpectedCallApi:setReturnValues(...)
  self._return = table.pack(...)
end

function ExpectedCallApi:getReturnValues(...)
  return table.unpack(self._return)
end

function ExpectedCallApi:fixOrder()
  self._ordered = true
end

function ExpectedCallApi:hasFixedOrder()
  return self._ordered
end

function ExpectedCallApi:isRequired()
  return self._required
end

local MockExpectation = {}

local MockExpectationApi = {}
MockExpectationApi.__index = MockExpectationApi

function MockExpectation.create(m)
  local o = {
    _m = m,
    _callSpecified = false,
    _calls = {}
  }

  setmetatable(o, MockExpectationApi)

  return o
end

function MockExpectationApi:andWillReturn(...)
  if not self._callSpecified then
    error('cannot set return value for an unspecified call', 2)
  end

  self._calls[#self._calls]:setReturnValues(...)

  return self
end

function MockExpectationApi:when(thunk)
  if not self._callSpecified then
    error('incomplete expectation', 2)
  end

  local function called(m, name, args)
    assert(#self._calls > 0, 'unexpected call')

    local validFunctionFound = false

    for i, call in ipairs(self._calls) do
      if call:functionMatches(m) then
        validFunctionFound = true

        if call:argsMatch(args) then
          if call:hasFixedOrder() and i > 1 then
            self._calls[i - 1]:fixOrder()
          end

          return table.remove(self._calls, i):getReturnValues()
        end
      end

      if call:hasFixedOrder() then break end
    end

    if not validFunctionFound then
      error('unexpected function call ' .. name .. '(' .. table.concat(args, ', ') .. ')', 2)
    else
      error('unexpected arguments (' .. table.concat(args, ', ') .. ') provided to function ' .. name, 2)
    end
  end

  handleMockCalls(called, thunk)

  for _, call in pairs(self._calls) do
    if call:isRequired() then
      error('not all calls occurred', 2)
    end
  end
end

function MockExpectationApi:after(thunk)
  if not self._callSpecified then
    error('incomplete expectation', 2)
  end

  self:when(thunk)
end

function MockExpectationApi:andThen(other)
  self._calls[#self._calls]:fixOrder()

  for _, call in ipairs(other._calls) do
    table.insert(self._calls, call)
  end

  return self
end

function MockExpectationApi:andAlso(other)
  for _, call in ipairs(other._calls) do
    table.insert(self._calls, call)
  end

  return self
end

function MockExpectationApi:shouldBeCalledWith(...)
  if self._callSpecified == true then
    error('call already specified', 2)
  end

  self._callSpecified = true
  table.insert(self._calls, ExpectedCall.create(self._m, true, table.pack(...)))
  return self
end

function MockExpectationApi:shouldBeCalled()
  if self._callSpecified == true then
    error('call already specified', 2)
  end

  return self:shouldBeCalledWith()
end

function MockExpectationApi:mayBeCalledWith(...)
  if self._callSpecified == true then
    error('call already specified', 2)
  end

  self._callSpecified = true
  table.insert(self._calls, ExpectedCall.create(self._m, false, table.pack(...)))
  return self
end

function MockExpectationApi:mayBeCalled()
  if self._callSpecified == true then
    error('call already specified', 2)
  end

  return self:mayBeCalledWith()
end

function MockExpectationApi:multipleTimes(times)
  for i = 1, times - 1 do
    table.insert(self._calls, self._calls[#self._calls])
  end

  return self
end

function Mock.mockFunction(name)
  name = name or '<anonymous>'
  local f = {}

  function fCall(_, ...)
    return mockCalled(f, name, table.pack(...))
  end

  setmetatable(f, {__call = fCall})

  return f
end

function Mock.mockMethod(name)
  name = name or '<anonymous>'
  local m = {}

  function mCall(_, _, ...)
    local args = table.pack(...)
    return mockCalled(m, name, args)
  end

  setmetatable(m, {__call = mCall})

  return m
end

function isCallable(x)
  local isFunction = type(x) == 'function'
  local hasCallMetamethod = type((debug.getmetatable(x) or {}).__call) == 'function'
  return isFunction or hasCallMetamethod
end

function Mock.mockTable(t, name)
  name = name or '<anonymous>'
  local mocked = {}

  for k, v in pairs(t) do
    if isCallable(v) then
      mocked[k] = Mock.mockFunction(name .. '.' .. tostring(k))
    end
  end

  return mocked
end

function Mock.mockObject(o, name)
  name = name or '<anonymous>'
  local mocked = {}

  for k, v in pairs(o) do
    if isCallable(v) then
      mocked[k] = Mock.mockMethod(name .. ':' .. tostring(k))
    end
  end

  return mocked
end

setmetatable(Mock, { __call = function(_, ...) return MockExpectation.create(...) end })

return Mock
