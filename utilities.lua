-- utilities.lua
-- Functions shared among plugins.

local misc, roles, users = {}, {}, {}

function misc.get_word(s, i) -- get the indexed word in a string

	s = s or ''
	i = i or 1

	local t = {}
	for w in s:gmatch('%g+') do
		table.insert(t, w)
	end

	return t[i] or false

end

function string:input() -- Returns the string after the first space.
	if not self:find(' ') then
		return false
	end
	return self:sub(self:find(' ')+1)
end

function string:mEscape() -- Remove the markdown.
	self = self:gsub('*', '\\*'):gsub('_', '\\_'):gsub('`', '\\`'):gsub('%]', '\\]'):gsub('%[', '\\[')
	return self
end

function string:mEscape_hard() -- Remove the markdown.
	self = self:gsub('*', ''):gsub('_', ''):gsub('`', ''):gsub('%[', ''):gsub('%]', '')
	return self
end

function roles.is_bot_owner(user_id, real_owner) --if real owner is true, the function will return true only if msg.from.id == config.admin.owner
	if user_id == config.admin.owner then
		return true
	end
	if not real_owner then
		if user_id and config.admin.admins[user_id] then
			return true
		end
	end
	return false
end

function roles.bot_is_admin(chat_id)
	local status = api.getChatMember(chat_id, bot.id).result.status
	if not(status == 'administrator') then
		return false
	else
		return true
	end
end

function roles.is_admin(msg)
	if config.admin.admins[msg.from.id] then
		-- Bot owners always are considered as moderators
		return true, true
	end
	local res = api.getChatMember(msg.chat.id, msg.from.id)
	if not res then
		return false, false
	end
	local status = res.result.status
	if status == 'creator' or status == 'administrator' then
		return true, true
	else
		return false, true
	end
end

function roles.is_admin_cached(msg)
	local hash = 'cache:chat:'..msg.chat.id..':admins'
	if not db:exists(hash) then
		misc.cache_adminlist(msg.chat.id, res)
	end
	return db:sismember(hash, msg.from.id)
end

function roles.is_admin2(chat_id, user_id)
	local res = api.getChatMember(chat_id, user_id)
	if not res then
		return false, false
	end
	local status = res.result.status
	if status == 'creator' or status == 'administrator' then
		return true, true
	else
		return false, true
	end
end

function roles.is_owner(msg)
	local status = api.getChatMember(msg.chat.id, msg.from.id).result.status
	if status == 'creator' then
		return true
	else
		return false
	end
end

function roles.is_owner2(chat_id, user_id)
	local status = api.getChatMember(chat_id, user_id).result.status
	if status == 'creator' then
		return true
	else
		return false
	end
end

function misc.cache_adminlist(chat_id)
	local res, code = api.getChatAdministrators(chat_id)
	if not res then
		return false, code
	end
	local hash = 'cache:chat:'..chat_id..':admins'
	for _, admin in pairs(res.result) do
		db:sadd(hash, admin.user.id)
	end
	db:expire(hash, config.bot_settings.cache_time.adminlist)
	return true
end

function misc.is_banned(chat_id, user_id)
	--useful only for normal groups
	local hash = 'chat:'..chat_id..':banned'
	local res = db:sismember(hash, user_id)
	if res then
		return true
	else
		return false
	end
end

function misc.is_blocked_global(id)
	if db:sismember('bot:blocked', id) then
		return true
	else
		return false
	end
end

function string:trim() -- Trims whitespace from a string.
	local s = self:gsub('^%s*(.-)%s*$', '%1')
	return s
end

function load_data(filename) -- Loads a JSON file as a table.

	local f = io.open(filename)
	if not f then
		return {}
	end
	local s = f:read('*all')
	f:close()
	local data = JSON.decode(s)

	return data

end

function save_data(filename, data) -- Saves a table to a JSON file.

	local s = JSON.encode(data)
	local f = io.open(filename, 'w')
	f:write(s)
	f:close()

end

function vardump(value)
  print(serpent.block(value, {comment=false}))
end

function vtext(value)
  return serpent.block(value, {comment=false})
end

local function per_away(text)
	local text = tostring(text):gsub('%%', '£&£')
	return text
end

local function create_folder(name)
	local cmd = io.popen('sudo mkdir '..name)
    cmd:read('*all')
    cmd = io.popen('sudo chmod -R 775 '..name)
    cmd:read('*all')
    cmd:close()
end

function misc.write_file(path, text, mode)
	if not mode then
		mode = "w"
	end
	file = io.open(path, mode)
	if not file then
		create_folder('logs')
		file = io.open(path, mode)
		if not file then
			return false
		end
	end
	file:write(text)
	file:close()
	return true
end

function misc.save_log(action, arg1, arg2, arg3, arg4)
	if action == 'send_msg' then
		local text = os.date('[%A, %d %B %Y at %X]')..'\n'..arg1..'\n\n'
		local path = "./logs/msgs_errors.txt"
		local res = misc.write_file(path, text, "a")
		if not res then
			create_folder('logs')
			misc.write_file(path, text, "a")
		end
    elseif action == 'errors' then
    	--error, from, chat, text
    	local path = "./logs/errors.txt"
    	local text = os.date('[%A, %d %B %Y at %X]')..'\nERROR: '..arg1
    	if arg2 then
    		text = text..'\nFROM: '..arg2
    	end
 		if arg3 then
 			text = text..'\nCHAT: '..arg3
 		end
 		if arg4 then
 			text = text..'\nTEXT: '..arg4
 		end
 		text = text..'\n\n'
 		local res = misc.write_file(path, text, "a")
    	if not res then
			create_folder('logs')
			misc.write_file(path, text, "a")
		end
    end
end

function misc.clone_table(t) --doing "table1 = table2" in lua = create a pointer to table2
  local new_t = {}
  local i, v = next(t, nil)
  while i do
    new_t[i] = v
    i, v = next(t, i)
  end
  return new_t
end

function misc.remove_duplicates(t)
	if type(t) ~= 'table' then
		return false, 'Table expected, got '..type(t)
	else
		local kv_table = {}
		for i, element in pairs(t) do
			if not kv_table[element] then
				kv_table[element] = true
			end
		end
		
		local k_table = {}
		for key, boolean in pairs(kv_table) do
			k_table[#k_table + 1] = key
		end
		
		return k_table
	end
end

function misc.get_date(timestamp)
	if not timestamp then
		timestamp = os.time()
	end
	return os.date('%d/%m/%y')
end

function misc.resolve_user(username, chat_id)
	username = username:lower()

	if chat_id then
		local hash = string.format('bot:usernames:%d', chat_id)
		local stored = db:hget(hash, username)
		if stored then return tonumber(stored) end
	end

	local stored = db:hget('bot:usernames', username)
	if stored then return tonumber(stored) end

	return false
end

function misc.is_lang_supported(code)
	return config.available_languages[code:lower()] ~= nil
end

function misc.create_folder(name)
	local cmd = io.popen('sudo mkdir '..name)
    cmd:read('*all')
    cmd = io.popen('sudo chmod -R 775 '..name)
    cmd:read('*all')
    cmd:close()
end

function misc.write_file(path, text, mode)
	if not mode then
		mode = "w"
	end
	file = io.open(path, mode)
	if not file then
		misc.create_folder('logs')
		file = io.open(path, mode)
		if not file then
			return false
		end
	end
	file:write(text)
	file:close()
	return true
end

function misc.save_br(code, text)
	text = os.date('[%A, %d %B %Y at %X]')..', code: '..code..'\n'..text
	local path = "./logs/msgs_errors.txt"
	local res = misc.write_file(path, text, "a")
	if not res then
		create_folder('logs')
		misc.write_file(path, text, "a")
	end
end

function misc.get_media_type(msg)
	if msg.photo then
		return 'image'
	elseif msg.video then
		return 'video'
	elseif msg.audio then
		return 'audio'
	elseif msg.voice then
		return 'voice'
	elseif msg.document then
		if msg.document.mime_type == 'video/mp4' then
			return 'gif'
		else
			return 'file'
		end
	elseif msg.sticker then
		return 'sticker'
	elseif msg.contact then
		return 'contact'
	end
	return false
end

function misc.get_media_id(msg)
	if msg.photo then
		if msg.photo[3] then
			return msg.photo[3].file_id, 'photo'
		else
			if msg.photo[2] then
				return msg.photo[2].file_id, 'photo'
			else
				if msg.photo[1] then
					return msg.photo[1].file_id, 'photo'
				else
					return msg.photo.file_id, 'photo'
				end
			end
		end
	elseif msg.document then
		return msg.document.file_id
	elseif msg.video then
		return msg.video.file_id, 'video'
	elseif msg.audio then
		return msg.audio.file_id
	elseif msg.voice then
		return msg.voice.file_id, 'voice'
	elseif msg.sticker then
		return msg.sticker.file_id
	else
		return false, 'The message has not a media file_id'
	end
end

function misc.migrate_chat_info(old, new, on_request)
	if not old or not new then
		print('A group id is missing')
		return false
	end
	
	local about = db:get('chat:'..old..':about')
	if about then
		db:set('chat:'..new..':about', about)
	end
	
	local rules = db:get('chat:'..old..':rules')
	if rules then
		db:set('chat:'..new..':rules', rules)
	end
	
	for set, default in pairs(config.chat_settings) do
		local old_t = db:hgetall('chat:'..old..':'..set)
		for field, val in pairs(old_t) do
			db:hset('chat:'..new..':'..set, field, val)
		end
	end
	
	local extra = db:hgetall('chat:'..old..':extra')
	for trigger, response in pairs(extra) do
		db:hset('chat:'..new..':extra', trigger, response)
	end
	
	if on_request then
		api.sendReply(msg, 'Should be done')
	end
end

function div()
	print('XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX')
	print('XXXXXXXXXXXXXXXXXX BREAK XXXXXXXXXXXXXXXXXXX')
	print('XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX')
end

function misc.to_supergroup(msg)
	local old = msg.chat.id
	local new = msg.migrate_to_chat_id
	misc.migrate_chat_info(old, new, false)
	misc.remGroup(old, true)
	api.sendMessage(new, '(_service notification: migration of the group executed_)', true)
end

function misc.getname(msg)
    local name = msg.from.first_name
	if msg.from.username then name = name..' (@'..msg.from.username..')' end
    return name
end

function misc.getname_id(msg)
    return msg.from.first_name..' ('..msg.from.id..')'
end

function misc.getname_link(name, username)
	if not name or not username then return false end
	username = username:gsub('@', '')
	return '['..name..'](https://telegram.me/'..username..')'
end

function misc.bash(str)
	local cmd = io.popen(str)
    local result = cmd:read('*all')
    cmd:close()
    return result
end

function misc.download_to_file(url, file_path)--https://github.com/yagop/telegram-bot/blob/master/bot/utils.lua
  --print("url to download: "..url)

  local respbody = {}
  local options = {
    url = url,
    sink = ltn12.sink.table(respbody),
    redirect = true
  }
  -- nil, code, headers, status
  local response = nil
    options.redirect = false
    response = {HTTPS.request(options)}
  local code = response[2]
  local headers = response[3]
  local status = response[4]
  if code ~= 200 then return false, code end

  print("Saved to: "..file_path)

  file = io.open(file_path, "w+")
  file:write(table.concat(respbody))
  file:close()
  return file_path, code
end

function misc.telegram_file_link(res)
	--res = table returned by getFile()
	return "https://api.telegram.org/file/bot"..config.bot_api_key.."/"..res.result.file_path
end

function misc.is_silentmode_on(chat_id)
	local hash = 'chat:'..chat_id..':settings'
	local res = db:hget(hash, 'Silent')
	if res and res == 'on' then
		return true
	else
		return false
	end
end

function misc.getAbout(chat_id)
	local hash = 'chat:'..chat_id..':info'
	local about = db:hget(hash, 'about')
    if not about then
        return _("*No description* for this group.")
    else
       	return about
    end
end

function misc.getRules(chat_id)
	local hash = 'chat:'..chat_id..':info'
	local rules = db:hget(hash, 'rules')
    if not rules then
        return _("*-empty-*")
    else
       	return rules
    end
end

function users.get_link(user)
	if user.username then
		return string.format('https://telegram.me/%s', user.username)
	end
	return false
end

function users.full_name(user, without_link)
	local result = user.first_name:mEscape_hard()
	if user.last_name then
		result = result .. ' ' .. user.last_name:mEscape_hard()
	end
	if not without_link and user.username then
		result = string.format('[%s](%s)', result, users.get_link(user))
	end
	return result
end

function misc.format_adminlist(chat_id, from_id, ln, msg)
	--- ???
	local list, code = api.getChatAdministrators(chat_id)
	if not list then
		if code == 107 then
			--- what is it?
			return false, code
		else
			return false, false
		end
	end

	local creator, adminlist = nil, {}
	for i, admin in pairs(list.result) do
		if admin.status == 'administrator' and admin.user.id ~= bot.id then
			table.insert(adminlist, users.full_name(admin.user))
		end
		if admin.status == 'creator' then
			creator = users.full_name(admin.user)
		end
	end

	local lines, count = {}, 1
	if creator then
		table.insert(lines, _("*Creator*:"))
		table.insert(lines, string.format('*1*. %s', creator))
		count = count + 1
	end
	if #adminlist ~= 0 then
		table.insert(lines, _("*Admins*:"))
		for i, admin in pairs(adminlist) do
			table.insert(lines, string.format('*%d*. %s', count, admin))
			count = count + 1
		end
	end

	if not roles.bot_is_admin(chat_id) then
		if #lines == 0 then
			assert(#list.result == 0)
			return _("_No administrators in the group_")
		elseif roles.is_admin_cached(msg) then
			table.insert(lines, _("*I'm not an admin*. I can't fully perform "
					.. "my functions until group creator hasn't made me admin. "
					.. "See [this post](https://telegram.me/GroupButler_ch/104) "
					.. "for to learn how to make a bot administrator."))
		else
			table.insert(lines, _("*I'm not an admin* 😞"))
		end
	elseif #lines == 0 then
		assert(#list.result == 1)
		return _("_I'm the only administrator in the group_")
	end

	return table.concat(lines, '\n')
end

function misc.getExtraList(chat_id)
	local hash = 'chat:'..chat_id..':extra'
	local commands = db:hkeys(hash)
	local text = ''
	if commands[1] == nil then
		return _("No commands set!")
	else
	    for k,v in pairs(commands) do
	    	text = text..v..'\n'
	    end
		return _("List of *custom commands*:\n") .. text
	end
end

function misc.getSettings(chat_id)
    local hash = 'chat:'..chat_id..':settings'
        
    local message = _("Current settings for *the group*:\n\n")
			.. _("*Language*: `%s`\n"):format(ln)
        
    --build the message
	local strings = {
		Welcome = _("Welcome message"),
		Goodbye = _("Goodbye message"),
		Extra = _("Extra"),
		Flood = _("Anti-flood"),
		Silent = _("Silent mode"),
		Rules = _("/rules"),
		Arab = _("Arab"),
		Rtl = _("RTL"),
	}
    for key, default in pairs(config.chat_settings['settings']) do
        
        local off_icon, on_icon = '🚫', '✅'
        if misc.is_info_message_key(key) then
        	off_icon, on_icon = '👤', '👥'
        end
        
        local db_val = db:hget(hash, key)
        if not db_val then db_val = default end
        
        local text
        if db_val == 'off' then
            text = '`'..strings[key]..'`: '..off_icon..'\n'
        else
            text = '`'..strings[key]..'`: '..on_icon..'\n'
        end
        message = message..text --concatenete the text
    end
    
    --build the char settings lines
    hash = 'chat:'..chat_id..':char'
    off_icon, on_icon = '🚫', '✅'
    for key, default in pairs(config.chat_settings['char']) do
    	db_val = db:hget(hash, key)
        if not db_val then db_val = default end
    	if db_val == 'off' then
            message = message..'`'..strings[key]..'`: '..off_icon..'\n'
        else
            message = message..'`'..strings[key]..'`: '..on_icon..'\n'
        end
    end
    	
    --build the "welcome" line
    hash = 'chat:'..chat_id..':welcome'
    local type = db:hget(hash, 'type')
    if type == 'media' then
		message = message .. _("*Welcome type*: `GIF / sticker`\n")
	elseif type == 'custom' then
		message = message .. _("*Welcome type*: `custom message`\n")
	elseif type == 'no' then
		message = message .. _("*Welcome type*: `default message`\n")
	end
    
    local warnmax_std = (db:hget('chat:'..chat_id..':warnsettings', 'max')) or config.chat_settings['warnsettings']['max']
    local warnmax_media = (db:hget('chat:'..chat_id..':warnsettings', 'mediamax')) or config.chat_settings['warnsettings']['mediamax']
    
    return message .. _("`Warn (standard)`: *%s*\n"):format(warnmax_std)
			.. _("`Warn (media)`: *%s*\n\n"):format(warnmax_media)
			.. _("✅ = _enabled / allowed_\n")
			.. _("🚫 = _disabled / not allowed_\n")
			.. _("👥 = _sent in group (always for admins)_\n")
			.. _("👤 = _sent in private_")
end

function misc.changeSettingStatus(chat_id, field)
	local disabled = {
		welcome = _("Welcome message won't be displayed from now"),
		extra = _("#extra commands are now available only for moderator"),
		flood = _("Anti-flood is now off"),
		rules = _("`/rules` will reply in private (for users)"),
	}
	local enabled = {
		welcome = _("Welcome message will be displayed"),
		extra = _("Extra # commands are now available for all"),
		flood = _("Anti-flood is now on"),
		rules = _("`/rules` will reply in the group (with everyone)"),
	}

	local hash = 'chat:'..chat_id..':settings'
	local now = db:hget(hash, field)
	if now == 'on' then
		db:hset(hash, field, 'off')
		return disabled[field:lower()]
	else
		db:hset(hash, field, 'on')
		return enabled[field:lower()]
	end
end

function misc.changeFloodSettings(chat_id, screm)
	local hash = 'chat:'..chat_id..':flood'
	if type(screm) == 'string' then
		if screm == 'kick' then
			db:hset(hash, 'ActionFlood', 'ban')
			return _("Now flooders will be banned")
        elseif screm == 'ban' then
			db:hset(hash, 'ActionFlood', 'tempban')
			return _("Now flooders will be temporary banned")
		elseif screm == 'tempban' then
        	db:hset(hash, 'ActionFlood', 'kick')
			return _("Now flooders will be kicked")
        end
    elseif type(screm) == 'number' then
    	local old = tonumber(db:hget(hash, 'MaxFlood')) or 5
    	local new
    	if screm > 0 then
    		new = db:hincrby(hash, 'MaxFlood', 1)
    		if new > 25 then
    			db:hincrby(hash, 'MaxFlood', -1)
				return _("%d is not a valid value!\n"):format(new)
						.. ("The value should be *higher* than 3 and *lower* then 26")
    		end
    	elseif screm < 0 then
    		new = db:hincrby(hash, 'MaxFlood', -1)
    		if new < 4 then
    			db:hincrby(hash, 'MaxFlood', 1)
				return _("%d is not a valid value!\n"):format(new)
						.. ("The value should be *higher* than 3 and *lower* then 26")
    		end
    	end
		return string.format('%d → %d', old, new)
    end 	
end

function misc.changeMediaStatus(chat_id, media, new_status)
	local old_status = db:hget('chat:'..chat_id..':media', media)
	local new_status_icon
	if new_status == 'next' then
		if not old_status then
			new_status = 'ok'
			new_status_icon = '✅'
		elseif old_status == 'ok' then
			new_status = 'notok'
			new_status_icon = '❌'
		elseif old_status == 'notok' then
			new_status = 'ok'
			new_status_icon = '✅'
		end
	end
	db:hset('chat:'..chat_id..':media', media, new_status)
	return _("New status = %s"):format(new_status_icon), true
end

function misc.sendStartMe(chat_id, text)
    local keyboard = {}
    keyboard.inline_keyboard = {
    	{
			{text = _("Start me"), url = 'https://telegram.me/'..bot.username}
	    }
    }
	api.sendKeyboard(chat_id, text, keyboard, true)
end

function misc.initGroup(chat_id)
	
	for set, setting in pairs(config.chat_settings) do
		local hash = 'chat:'..chat_id..':'..set
		for field, value in pairs(setting) do
			db:hset(hash, field, value)
		end
	end
	
	misc.cache_adminlist(chat_id, api.getChatAdministrators(chat_id)) --init admin cache
	
	--save group id
	db:sadd('bot:groupsid', chat_id)
	--remove the group id from the list of dead groups
	db:srem('bot:groupsid:removed', chat_id)
	
	--save stats
	hash = 'bot:general'
    db:hincrby(hash, 'groups', 1)
end

function misc.remGroup(chat_id, full)
	--remove group id
	db:srem('bot:groupsid', chat_id)
	--add to the removed groups list
	db:sadd('bot:groupsid:removed', chat_id)
	
	for set,field in pairs(config.chat_settings) do
		db:del('chat:'..chat_id..':'..set)
	end
	
	db:del('cache:chat:'..chat_id..':admins') --delete the cache
	
	if full then
		for i, set in pairs(config.chat_custom_texts) do
			db:del('chat:'..chat_id..':'..set)
		end
		db:del('lang:'..chat_id)
	end
end

function misc.getUserStatus(chat_id, user_id)
	local res = api.getChatMember(chat_id, user_id)
	if res then
		return res.result.status
	else
		return false
	end
end

function misc.saveBan(user_id, motivation)
	local hash = 'ban:'..user_id
	return db:hincrby(hash, motivation, 1)
end

function misc.is_info_message_key(key)
    if key == 'Extra' or key == 'Rules' then
        return true
    else
        return false
    end
end

function misc.table2keyboard(t)
	local keyboard = {inline_keyboard = {}}
    for i, line in pairs(t) do
        if type(line) ~= 'table' then return false, 'Wrong structure (each line need to be a table, not a single value)' end
        local new_line ={}
        for k,v in pairs(line) do
            if type(k) ~= 'string' then return false, 'Wrong structure (table of arrays)' end
            local button = {}
            button.text = k
            button.callback_data = v
            table.insert(new_line, button)
        end
        table.insert(keyboard.inline_keyboard, new_line)
    end
    
    return keyboard
end

return misc, roles, users
