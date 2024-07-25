--[[
 Use the source, Luke!
 Copyright (C) 2014-2023 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {
   'luke.platforms',
   'std.functional',
   LUAVERSION = string.gsub(_VERSION, '[^0-9%.]+', ''),
}



local env_mt = {
   __index = function(self, varname)
      return dropuntil(self, function(env)
         local value = env[varname]
         if value ~= nil then
            self[varname] = value
            return value
         end
      end)
   end,
}


local function interpolate_with(pattern, env, s)
   local r = ''
   while r ~= s do
      r = s
      s = gsub(r, pattern, function(varname)
         return env[varname] or ''
      end)
   end
   return r
end


local function isenv(t)
   return getmetatable(t) == env_mt
end


---Execute a command and handle errors
-- This add stderr support to io.popen, 
-- i tried many but none worked

-- cmd:str shell command
-- mask_stdout: if true redirect to a maygiver pipe  so stdout is masked
-- mask_stderr: if true  redirect to a maygiver pipe so stderr is masked 
--
--returns  output, err   where output is stdout and err is stderr message
local function luarock_execute(cmd , mask_stdout, mask_stderr)
  
    local out, err
    local _stdout, _stderr
    local file_stdout=tmpname()
    local file_stderr=tmpname()
     
    if mask_stdout then  out=' > '..file_stdout else out='' end
    if mask_stderr then err= ' 2> '..file_stderr else err='' end
  
    exe,err =  popen(cmd.. out.. err)
    
    out=nil
    
    if not exe then
        rm(file_stdout)
        rm(file_stderr)
        return nil, "Could execute: "..err 
    else
        
        if mask_stdout then
            _stdout,err=open(file_stdout,"r")
            if not _stdout then 
                rm(file_stdout)
                rm(file_stderr)
                return nil,"Could not open stdout: "..err
            else
                out=tostring(_stdout:read("*all"))
                close(_stdout)
                rm(file_stdout)
            end
        else
            rm(file_stdout)
        end
        
        if mask_stderr then
            _stderr,err=open(file_stderr,"r")
            if not _stderr then 
                rm(file_stderr)
                return nil, "Could not open stderr: "..err
            else
                err=tostring(_stderr:read("*all"))
                close(_stderr)
                rm(file_stderr)
                if err ~= "" then
                    --string.find("not found", err)  does not work
                    if gmatch(err,"not found") then
                        err=gsub(gsub(err,'^(sh: 1:)', ""),'[:]', "")
                        return nil, "Could not execute command:"..err 
                    end
                end
            end
        end
        
        if out ~= nil then
            output=out
        else
            output=exe:read("*all")
        end
        close(exe)
        return output, err
        
    end

end


---Grab the prefix from the luarock config
-- Depends on luarock binary that should be on the path
-- scope: str  --local or --global 
-- debug: bool true to show errors, else false to hide them
-- Return the prefix or ''
local function luarock_prefix(scope,debug)
    
    local output, err 
    output, err = luarock_execute('luarocks config', false,true)
    local pos=0
    
    if output ~= nil and output ~="" then
        -- scope=string.gsub(scope,"-","")
        --print('extracting prefix from output <['..output.."]>" )
        for line in gmatch(output,"[^\r\n]+") do --output:gmatch("[^\r\n]+")
            if pos ==2 then
                if find(scope,'--global') then
                    line, pos= gsub(line, '[%s,"]', "")
                    return line
                else
                    return '"'..scope..'"'
                end
            end
            if pos ==1 then
                if find(scope,'--local') then
                    line, pos= gsub(line, '[%s,"]', "")
                    return line
                end
                pos = 2
            end
            if find(line, "rocks_trees") then
                pos = 1
            end
        end
    else
        if debug then
            print("luarock_prefix failed:"..err)
        end
        return ''
    end
end

return {
   CONFIGENV = {
      compile    = '$CC -c $CFLAGS $CPPFLAGS',
      libs       = '',
      link       = '$CC $CFLAGS $CPPFLAGS $LDFLAGS',
   },

   DEFAULTENV = filter_platforms {
      LUAVERSION    = LUAVERSION,

      PREFIX        = luarock_prefix(tostring(getenv('PREFIX')))or'/usr/local',
      INST_LIBDIR   = '$PREFIX/lib/lua/$LUAVERSION',
      INST_LUADIR   = '$PREFIX/share/lua/$LUAVERSION',

      LIB_EXTENSION = 'so',
      OBJ_EXTENSION = 'o',

      INSTALL       = 'cp',
      MAKEDIRS      = 'mkdir -p',

      CFLAGS        = '-O2',
      platforms     = {
         macosx        = {
            LIBFLAG       = '-fPIC -bundle -undefined dynamic_lookup -all_load',
         },
         LIBFLAG    = '-shared -fPIC',
      },
   },

   SHELLENV = setmetatable({}, {
      __index = function(_, v)
         return getenv(v)
      end,
   }),

   expand = bind(interpolate_with, {'@([^@]+)@'}),
   interpolate = bind(interpolate_with, {'%$([%w_]+)'}),

   makeenv = function(...)
      local env = reduce(except(list(...), nil), function(r, t)
         if isenv(t) then
            map(t, bind(append, {r}))
         else
            append(r, t)
         end
      end)

      return setmetatable(env, env_mt)
   end,
}
