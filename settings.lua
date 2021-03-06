----------------------------------------
--
-- Copyright (c) 2015, 128 Technology, Inc.
--
-- author: Hadriel Kaplan <hadriel@128technology.com>
--
-- This code is licensed under the MIT license.
--
-- Version: 1.0
--
------------------------------------------

-- prevent wireshark loading this file as a plugin
if not _G['protbuf_dissector'] then return end


local inspect = require "inspect"
local debug   = require "debug"

local __DIR__           = protbuf_dissector.__DIR__
local __DIR_SEPARATOR__ = protbuf_dissector.__DIR_SEPARATOR__

local WIRESHARK_PROTOBUF_DEBUG_LEVEL = os.getenv("WIRESHARK_PROTOBUF_DEBUG_LEVEL")

--------------------------------------------------------------------------------
-- our Settings
local Settings = {

    -- a table of directories to load - all proto files in these directories
    -- will be loaded; NOTE: the directory names need to be a full absolute path
    proto_dirs = {
        __DIR__ .. __DIR_SEPARATOR__ .. "files",
        -- __DIR__ .. __DIR_SEPARATOR__ .. "test",
    },

    -- a table of protobuf '.proto' files to load, if not in
    -- the directories above
    proto_files = {
        -- example:
        -- "foo.proto", "bar.proto"
    },

    -- debug levels
    dlevel = {
        DISABLED = 0,
        LEVEL_1  = 1,
        LEVEL_2  = 2
    },

    -- current debug level; default disabled
    debug_level = 0,

    -- debug printers for different debug levels, by default they
    -- do nothing; but this will be updated later
    dprint  = function() end,
    dprint2 = function() end,

    -- to handle passing arguments to dprint/dassert/derror/etc., we need
    -- something that would never naturally be in the variable list of
    -- arguments; so we use these tables as those arguements, since a table
    -- instance in Lua is a pointer and can be compared and will be unique
    add_stacktrace = {},

}

if WIRESHARK_PROTOBUF_DEBUG_LEVEL and WIRESHARK_PROTOBUF_DEBUG_LEVEL ~= "" then
    Settings.debug_level = tonumber(WIRESHARK_PROTOBUF_DEBUG_LEVEL)
end

----------------------------------------

local inspect_filter = inspect.makeFilter({ ".<metatable>", ".cursor" })

local function generateOutput(t)
    local out = {}

    for _, value in ipairs(t) do
        local vt = type(value)
        if vt == 'string' then
            out[#out+1] = value
        elseif vt == 'table' then
            if value == Settings.add_stacktrace then
                out[#out+1] = debug.traceback("", 3)
            else
                if type(value.getType) == 'function' then
                    vt = value:getType()
                end
                if vt == 'CURSOR' or vt == 'TOKEN' then
                    out[#out+1] = value:getDebugOutput()
                else
                    out[#out+1] = inspect(value, { filter = inspect_filter })
                end
            end
        else
            out[#out+1] = tostring(value)
        end
    end
    return table.concat(out, " ")
end


local function resetDebugLevel()
    if Settings.debug_level > Settings.dlevel.DISABLED then
        Settings.dprint = function(...)
            info( generateOutput( { "Protobuf-Debug:", ... } ) )
        end

        if Settings.debug_level > Settings.dlevel.LEVEL_1 then
            Settings.dprint2 = Settings.dprint
        else
            Settings.dprint2 = function() end
        end
    else
        Settings.dprint = function() end
        Settings.dprint2 = function() end
    end
end
-- call it now
resetDebugLevel()


--------------------------------------------------------------------------------
-- the public functions of the module

function Settings:processCmdLine(args)
    -- allow the command line to specify file names, debug level
    for _, n in ipairs(args) do
        if n:find("=") then
            local level = n:match("debug%s*=%s*(%d)")
            if not level then
                error("Bad argument given to protobuf.lua: " .. n)
            end
            self.debug_level = tonumber(level)
        else
            self.proto_files[#self.proto_files + 1] = n
        end
    end
    resetDebugLevel()
end


function Settings:getProtoFileNames()
    local names = {}
    local t = {}

    -- get all proto files in the directories
    for _, dir_name in ipairs(self.proto_dirs) do
        assert(Dir.exists(dir_name), "Protobuf ERROR: could not find proto directory: " .. dir_name)
        for filename in Dir.open(dir_name, ".proto") do
            local fullname = dir_name .. __DIR_SEPARATOR__ .. filename
            t[#t+1] = fullname
            names[fullname] = true
        end
    end

    -- and add all explicit files too
    for _, filename in ipairs(self.proto_files) do
        assert(file_exists(filename), "Protobuf ERROR: could not find proto file: " .. filename)
        if not names[filename] then
            t[#t+1] = filename
            names[filename] = true
        end
    end

    return t
end


function Settings:getDebugLevel()
    return self.debug_level
end


-- like Lua's 'assert()', except it takes an arbitrary number of arguments
-- which it will concatenate into an error string if the first argument is
-- false; this way we avoid the performance penalty of generating strings
-- for non-false assertions
function Settings.dassert(check, ...)
    if check then return check end
    error( generateOutput({ "Protobuf ERROR:\n", ... }), 2 )
end


function Settings.derror(...)
    error( generateOutput({ "Protobuf ERROR:\n", ... }), 2 )
end


-- XXX for debugging/understanding
local function summary(k, v, sofar, indent)
    if sofar == nil then sofar = {} end
    if indent == nil then indent = "" end

    local first = {"name", "label", "ttype"}
    local ignore = {file_text=true, pfield=true, raw=true}
    local literal = {}
    local stopat = {frequency=true}

    local vt = type(v)
    local s
    if vt == "boolean" or vt == "number" or vt == "string" or literal[k] then
        if vt == "string" then
            local vf = v
            if vf:len() > 48 then
                vf = vf:sub(0, 48) .. "..."
            end
            s = k .. ": (" .. v:len() .. ") "  .. vf
        elseif vt == "boolean" then
            s = k .. ": " .. tostring(v)
        else
            s = k .. ": " .. v
        end
    else
        s = k .. ": (" .. vt .. ")"
    end
    sofar[#sofar+1] = indent .. s

    indent = indent .. "  "

    if false and vt == "table" then
        local vm = getmetatable(v)
        if vm then
            sofar = summary("metatable", vm, sofar, indent)
        end
    end

    if vt == "table" and not stopat[k] then
        local tab = v

        local done = {}
        for _, k in ipairs(first) do
            if type(tab[k]) ~= nil and tab[k] ~= nil then
                sofar = summary(k, tab[k], sofar, indent)
            end
            done[k] = true
        end

        for k, v in pairs(tab) do
            if not done[k] and not ignore[k] then
                sofar = summary(k, v, sofar, indent)
            end
        end
    end

    return sofar
end

function Settings.dsummary(func, name, value)
    Settings.dprint(func .. "\n" .. table.concat(summary(name, value), "\n"))
end

return Settings
