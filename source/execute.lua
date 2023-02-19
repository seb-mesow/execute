-- iterates through a table/list as segments of elements in reverse order
-- or returns the previous segment of elements in the table/list
-- The elements in the segments are in order.
-- usage: for i, segment in next_segment(s), table do
-- sl – segment length
local function __prev_segment(sl)
    if sl < 1 then
        tex.error( "__prev_segment: segment length is zero or negative",
                   { "segment length == "..tostring(sl),
                     "I return a useless iterator function." } )
        return function(t, i) end
    end
    -- t – table (state)
    -- i – index of last iteration
    -- If i is nil, returns the first index.
    return function(t, i)
        if not t or type(t) ~= "table" then
            texio.write_nl("__prev_segment iterator impl: state is not a table.")
            texio.write_nl("type(t) == "..type(t))
            return nil
        end
        if #t < 1 then
            return nil
        end
        if not i then
            i = #t - sl + 1
            if i < 1 then
                i = 1
            end
            return i, table.move(t, i, #t, 1, {})
        end
        -- <luacode>
        --     i = i - sl
        --     if i + sl - 1 < 1  then
        -- </luacode>
        -- which is equivalent to
        if i < 2  then
            -- If we would take this index and compute the corresponding end index
            -- this end index would be out of the bounds of the table --> break
            return nil
        end
        -- e – end index of the segment of this iteration
        local e = i - 1
        i = i - sl
        -- guarantee that i is the bounds of the table
        if i < 1 then
            i = 1
        end
        return i, table.move(t, i, e, 1, {} )
    end
end

local relax_cmd         = token.command_id("relax"      )

local left_brace_cmd    = token.command_id("left_brace" )
local right_brace_cmd   = token.command_id("right_brace")
local begin_group_cmd   = token.command_id("begin_group")
local end_group_cmd     = token.command_id("end_group"  )
local after_group_cmd   = token.command_id("after_group")

local spacer_cmd        = token.command_id("spacer"     )
local extension_cmd     = token.command_id("extension"  )
local in_stream_cmd     = token.command_id("in_stream"  )
local read_to_cs_cmd    = token.command_id("read_to_cs" )

local max_non_prefixed_command_cmd = token.command_id("last_item"       )
local max_command_cmd              = token.command_id("set_font_id"     )
local afterassignment_cmd          = token.command_id("after_assignment")

local left_brace_tok  = token.new(string.utfvalue("{"), left_brace_cmd )
local right_brace_tok = token.new(string.utfvalue("}"), right_brace_cmd)

local immediate_tok = token.create("immediate")
local openout_tok   = token.create("openout")
local write_tok     = token.create("write")
local closeout_tok  = token.create("closeout")
local openin_tok    = token.create("openin")
local read_tok      = token.create("read")
local readline_tok  = token.create("readline")
local closein_tok   = token.create("closein")

local immediate_mode = immediate_tok.mode
local openout_mode   = openout_tok.mode
local write_mode     = write_tok.mode
local closeout_mode  = closeout_tok.mode
local openin_mode    = openin_tok.mode
local read_mode      = read_tok.mode
local readline_mode  = readline_tok.mode
local closein_mode   = closein_tok.mode

local __g__max_tokens_for_put_next = 64
local __put_next_token_table_segment_iter = __prev_segment(__g__max_tokens_for_put_next)

local function __put_next_token_table(tt)
    for _, s in __put_next_token_table_segment_iter, tt do
        token.put_next(s)
    end
end

-- argument(s):
-- either a list of tokens or one table of tokens
local function __put_next( tt, ... )
    if type(tt) == "table" then
        __put_next_token_table(tt)
    else
        __put_next_token_table({tt, ...})
    end
end

-- <filler> --> (<empty>|<space token>|\relax|<expandable command>)*
local function __scan_filler()
    local tt = {}
    local t
    while true do
        t = token.scan_token() -- get_x_token()
        if t.command == spacer_cmd or t.command == relax_cmd then
            table.insert(tt, t)
        else
            token.put_next(t)
            break
        end
    end
    return tt
end

-- should behave the same as void scan_left_brace(void) in tex/scanning.c
-- reads guaranteed until and including the next left brace
-- increases the current brace balance
-- arguments:
-- cur_brace_unbalance – current brace (un)balance (a non-negative integer)
-- returns:
-- r1 – new current token
-- <filled left brace> --> <filler>{
local function __scan_left_brace()
    local tt = __scan_filler()
    local t = token.scan_token()
    if t.command ~= left_brace_cmd then
        tex.error( "Missing { inserted" ,
                   { "A left brace was mandatory here, so I've put one in."    ,
                     "You might want to delete and/or insert some corrections" ,
                     "so that I will find a matching right brace soon."        ,
                     "If you're confused by all this, try typing `I}' now."
                   }
                 )
        token.put_next(t) -- same as back_input()
        t = left_brace_tok
    end
    table.insert(tt, t)
    return tt
end

-- tex.quittoks() was introduced with LuaTeX 1.11.*
-- But as of today (2020-01-26) only LuaTeX 1.10.0 is distributed.

-- executes only the provided token on the main input stack.
-- (As far as I know  – and I known many about TeX and its extensions – there is only one input stack.)
-- Note that this function by design leaves any tokens that the execution of the provided token may produced
-- and any following tokens.
-- As the execution of the provided token operates an the main input stack,
-- more following tokens can be scanned during the execution.
local function execute_token(cur_tok)
    -- This function call with the lua_local_call_cmd token is expandable.
    -- Though when get_x_token() is called, this Lua function call gets executed.
    -- There maybe remain some tokens from the Lua function call.
    -- The first remaining token or if the Lua function call did not let some tokens remain then
    -- the first token after the lua_local_call_cmd token,
    -- is then returned by get_x_token().
    tex.runtoks(
        function() -- This function is a closure with cur_tok
            token.get_next()    -- remove the surplus end_local_control token
            token.put_next(cur_tok) -- This is the next token get_x_token() actually returns,
                                    -- after the lua_local_call_cmd token.
                                    -- It is the only token we execute.
            tex.quittoks()  -- decrement the local_level
                            -- --> after the next token got with get_x_token() was executed,
                            --  we stop the local_control()
        end
        -- give control back to get_x_token() and then local_control() with the jump_table
    )
end

-- local g_exec_nest_level = 0

-- arguments:
-- a list of token filter functions to apply
local function execute(...)
    texio.write_nl("(begin execute ")
    -- g_exec_nest_level = g_exec_nest_level + 1
    
    local remaining_toks = {}
    
    -- not defining and not expanding scan tokens to execute
    -- We scan a <general text> as for \detokenize or \write.
    -- Though braces are mandatory.
    __scan_left_brace()
    local cur_brace_balance = 1
    
    while true do
        cur_tok = token.scan_token() -- runs get_x_token()
        -- also brace tokens are feed to the token_filters, except the last right_brace
        if cur_tok.command == left_brace_cmd then
            cur_brace_balance = cur_brace_balance + 1
        end
        if cur_tok.command == right_brace_cmd then
            cur_brace_balance = cur_brace_balance - 1
            if cur_brace_balance == 0 then
                break
            end
        end
        -- write_tok_info(cur_tok)
        -- run token_filters
        for _, token_filter in next, {...} do
            if token_filter(cur_tok, cur_tok.command, cur_tok.mode) then -- token already "used" by a callback
                cur_tok = nil
                break
            end
        end
        if cur_tok then
            table.insert(remaining_toks, cur_tok)
        end
    end
    
    __put_next(remaining_toks)
    
    -- g_exec_nest_level = g_exec_nest_level - 1
    texio.write_nl("end execute)")
end

local function do_relax_token_filter(cur_tok, cur_cmd, cur_mode)
    -- texio.write("R")
    if cur_cmd == relax_cmd then
        execute_token(cur_tok)
        return true
    end
end

local function do_groups_token_filter(cur_tok, cur_cmd, cur_mode)
    -- texio.write("g")
    if     cur_cmd == left_brace_cmd  and cur_tok.csname ~= nil -- \bgroup and not {
        or cur_cmd == begin_group_cmd                           -- \begingroup
        or cur_cmd == right_brace_cmd and cur_tok.csname ~= nil -- \egroup and not }
        or cur_cmd == end_group_cmd                             -- \endgroup
        or cur_cmd == after_group_cmd                           -- \aftergroup
    then
        execute_token(cur_tok)
        return true
    end
end

-- a toks is an assignment if:
-- max_non_prefixed_command < command field <= max_command 
-- and actually also afterassignment and aftergroup, but they don't work with \immediateassignment
local function do_assignments_token_filter(cur_tok, cur_cmd, cur_mode)
    -- texio.write("a")
    if      max_non_prefixed_command_cmd < cur_cmd and cur_cmd <= max_command_cmd
        or  cur_cmd == afterassignment_cmd
    then 
        execute_token(cur_tok)
        return true
    end
end

local function do_writes_token_filter(cur_tok, cur_cmd, cur_mode)
    -- texio.write("w")
    if  cur_cmd == extension_cmd and (
               cur_mode == immediate_mode
            or cur_mode == write_mode
            or cur_mode == openout_mode
            or cur_mode == closeout_mode
        )
    then
        execute_token(cur_tok)
        return true
    end
end


local function do_reads_token_filter(cur_tok, cur_cmd, cur_mode)
    -- texio.write("r")
    -- \read is also an assignment
    -- \readline is also an assignment!
    if     cur_cmd == read_to_cs_cmd and (
               cur_mode == read_mode
            or cur_mode == readline_mode
        )
        or cur_cmd == in_stream_cmd and (
               cur_mode == openin_mode
            or cur_mode == closein_mode
        )
    then
        execute_token(cur_tok)
        return true
    end
end

local function default_execute()
    execute(
        do_assignments_token_filter,
        do_writes_token_filter,
        do_reads_token_filter,
        do_groups_token_filter,
        do_relax_token_filter
    )
end

return {
    execute_token = execute_token,
    
    do_relax_token_filter = do_relax_token_filter,
    do_groups_token_filter = do_groups_token_filter,
    do_assignments_token_filter = do_assignments_token_filter,
    do_writes_token_filter = do_writes_token_filter,
    do_reads_token_filter = do_reads_token_filter,
    
    execute = execute,
    default_execute = default_execute,
}
