-- load modpath
local MP = minetest.get_modpath(minetest.get_current_modname())

local censor = {

    -- some settings for default behaviour of mod
    kick_enable = minetest.settings:get_bool('censor.kick_enable',true),
    warn_enable = minetest.settings:get_bool('censor.warn_enable',true),
    caps_enable = minetest.settings:get_bool('censor.caps_enable',true),
    name_enable = minetest.settings:get_bool('censor.name_enable',true),
    links_enable = minetest.settings:get_bool('censor.links_enable',true),
    warn_cost = minetest.settings:get('censor.warn_cost') or 3,
    caps_cost = minetest.settings:get('censor.caps_cost') or 2,
    violation_limit = minetest.settings:get('censor.violation_limit') or 12,
    caps_limit = minetest.settings:get('censor.violation_limit') or 50,
    -- substr_match is quite strict, either drop its support or allow some way of blacklisting
    substr_match = minetest.settings:get_bool('censor.substr_match',true),
    -- fun mode refers to substituting a bad word with a fun word
    fun_mode = minetest.settings:get_bool('censor.fun_mode',false),
    -- stores violation of online players
    violations = {}, fun_words={}, bad_words = {}, bad_en_words = {},whitelist = {},
    lang = {"en","zh","fil","fr","de","hi","ja","pl","ru","es","th"},
}
local colors = {
    warn = "#ff0000",
    info = "#ffff00"
}

-- check if file exists
local function file_exists(file)
    local f = io.open(file,"rb")
    if f then f:close() end
    return f~=nil
end

-- populate bad_list and bad_en_list
local dirname = MP .. "/wordlist"
for _,f in pairs(censor.lang) do
    local fname = dirname.. "/" .. f
    if file_exists(fname) then
        -- append file content to the dictionary bad_words
        for line in io.lines(fname) do
            if f == "en" then
                table.insert(censor.bad_en_words,line)
            end
            table.insert(censor.bad_words,line)
        end
    end
end

-- populate fun list
local fun_file = dirname .. "/fun"
if file_exists(fun_file) then
    for line in io.lines(fun_file) do
        table.insert(censor.fun_words, line)
    end
end

-- populate whitelist list
local whitelist_file = dirname .. "/white"
if file_exists(whitelist_file) then
    for line in io.lines(whitelist_file) do
        table.insert(censor.whitelist, line)
    end
end

-- function to check if word is whitelisted or not
function censor.contains(list,x)
    for _,v in pairs(list) do
	if v == x then return true end
    end
    return false
end

-- onprejoin changes by mod
minetest.register_on_prejoinplayer(function(name)
    for _,v in pairs(censor.bad_words) do
        if not censor.contains(censor.whitelist,name) and string.find(string.lower(name),string.lower(v)) then
            -- print on console
            print("[censor]: Blocked user " ..name.. " from joining because their name contains word : " .. v)
            return "Your name contained a blocked word :"..v..", Please try again with better name."
        end
    end
end)

-- onjoin changes by mod
minetest.register_on_joinplayer(function(player)
    -- set violations for each new player as 0
    censor.violations[player:get_player_name()] = 0
end)

-- censor warn
function censor.warn(name)
    if not censor.warn_enable then return end
    local vbalance = ""
    if censor.violations[name] and censor.kick_enable then
        vbalance = vbalance ..  "Violation Status: ".. censor.violations[name] .. "/"..censor.violation_limit
    end
    local warnmsg = minetest.colorize(
        colors["warn"],"Your last message will be reported to server staff! " .. vbalance )
    minetest.chat_send_player(name,warnmsg)
end

-- censor caps check a message
function censor.caps(name,msg)

    if not censor.caps_enable then return end
    if msg:len() > 256 then
        -- Add 3 cost for long messages
        censor.violations[name] = (censor.violations[name] or 0) + censor.caps_cost
        minetest.chat_send_player(name,minetest.colorize(colors["info"],"Long messages are considered as SPAM."))
        censor.warn(name)
    end

    -- no need to check short messages for caps
    if msg:len() > 8 then
        local caps = 0
        for i = 1,#msg do
            local c = msg:sub(i,i)
            -- replace everything that isn't a letter with smaller ones
            c = c:gsub('%A','a')
            if c == c:upper() then
                caps = caps + 1
            end
        end
        -- now we know caps
        if (caps*100/msg:len()) >= censor.caps_limit then
            -- Add some cost
            censor.violations[name] = (censor.violations[name] or 0) + censor.caps_cost
            minetest.chat_send_player(name,minetest.colorize(colors["info"],"CAPS ALERT"))
            censor.warn(name)
        end
    end
end

function censor.links(name,msg)
    -- check setting
    if not censor.links_enable then return msg end
    local pattern = 'https?://(([%w_.~!*:@&+$/?%%#-]-)(%w[-.%w]*%.)(%w+)(:?)(%d*)(/?)([%w_.~!*:@&+$/?%%#=-]*))'
    if not string.find(msg,pattern) then return msg end
    minetest.chat_send_player(name,minetest.colorize(colors["info"],"Links are not allowed in chat!"))
    return string.gsub(msg,pattern,"")
    -- detect links in the chat-message and remove them
end

-- kick on violation limit exceded
function censor.kick(name)
    -- check if enabled kick
    if not censor.kick_enable then return false end
    -- local player = minetest.get_player_by_name(name)
    if minetest.check_player_privs(name,"server") then
        return false
    end
    if censor.violations[name] >= censor.violation_limit then
        minetest.kick_player(name, "Violations Limits Excedded")
        minetest.chat_send_all(name .. minetest.colorize(colors["warn"]," has been kicked due to violations limits."))
        print("[censor]: " .. name .. " was kicked due to violations limits.")
        return true
    end
end

function censor.mentioned(name,msg)
    name, msg = name:lower(), msg:lower()

    -- Direct Mention
    local mention = msg:find(name,1,true)

    return mention
end

-- fixing message
function censor.fix_message(name,message)
    -- Censor Code
    -- "Lua is sexy" -> "Lua is ****"
    local mes = ""
    for w in message:gmatch("%S+") do
        for _,v in pairs(censor.bad_words) do
            if v:len() >= 5 and censor.substr_match then
                -- do contains operation
            if string.find(string.lower(w), string.lower(v)) and not censor.contains(censor.whitelist,w) then
                local pat = string.rep("*",v:len())
                if censor.fun_mode then
                    pat = censor.fun_words[math.random(1,#censor.fun_words)]
                end
                w = pat
            end
            else
                -- do match operation
            if string.lower(w) == string.lower(v) and not censor.contains(censor.whitelist,w) then
                local pat = string.rep("*",v:len())
                if censor.fun_mode then
                    pat = censor.fun_words[math.random(1,#censor.fun_words)]
                end
                w = pat
            end
            end
        end
        mes = mes .. w .. " "
    end
    -- remove last " "
    mes = mes:sub(1,-2)

    --Censor Code v2
    -- "Lua is sexy" -> "Lua is ***y"
    --[[
    local mes = string.lower(message)
    for _,v in pairs(bad_words) do
        -- Apply fun word substitution
        local pat = string.rep("*",v:len())
        if censor.fun_mode then
            pat = censor.fun_words[math.random(1,#censor.fun_words)] .. " "
        end
        mes = mes:gsub(v,pat)
    end
    --]]

    -- warn the offender
    if string.lower(mes) ~= string.lower(message) then
        print("[censor]: ".. name .. " sent censored message :"..message)
        censor.violations[name] = (censor.violations[name] or 0) + censor.warn_cost
        censor.warn(name)
    end
    return mes
end

-- main msg checking function
minetest.register_on_chat_message(function(name, message)

    -- Before sending message check shout privs
    if not minetest.check_player_privs(name, "shout") then
        return
    end

    censor.caps(name,message)
    -- Remove all links from the message
    message = censor.links(name,message)
    -- main censoring function
    -- #########
    message = censor.fix_message(name,message)

    -- if player kicked then no need to broadcast their message
    if censor.kick(name) then
        return true
    end

    -- send the manipulated message to everyone
    for _,player in pairs(minetest.get_connected_players()) do
        -- reciever is everyone
        local rname = player:get_player_name()
        local color = "#ffffff"

        -- add feature of mention highlight
        -- #######
	if censor.mentioned(rname,message) then
	    color = "#00ff00"
	end
	if name == rname then
	    color = "#ffffff"
	end

        local send = name .. ": ".. minetest.colorize(color,message)
        minetest.chat_send_player(rname,send)
    end

    -- return true to override default chat functionality
    return true
end)

-- console print mod status
print("[censor] OK")
