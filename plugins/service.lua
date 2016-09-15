local function is_locked(chat_id, param)
  	local hash = 'chat:'..chat_id..':settings'
  	local current = db:hget(hash, param)
  	if current == 'off' then
  		return true
  	else
  		return false
  	end
end

local function gsub_custom_inform(msg, custom)
	local user = msg.added or msg.removed
	local name = user.first_name:escape():gsub('%%', '')
	local id = user.id
	local username
	local title = msg.chat.title:escape():gsub('%%', '')
	if user.username then
		username = '@'..user.username:escape()
	else
		username = '(no username)'
	end
	return custom:gsub('$name', name):gsub('$username', username):gsub('$id', id):gsub('$title', title)
end

local function get_welcome(msg)
	if is_locked(msg.chat.id, 'Welcome') then
		return false
	end
	local type = (db:hget('chat:'..msg.chat.id..':welcome', 'type')) or config.chat_settings['welcome']['type']
	local content = (db:hget('chat:'..msg.chat.id..':welcome', 'content')) or config.chat_settings['welcome']['content']
	if type == 'media' then
		local file_id = content
		api.sendDocumentId(msg.chat.id, file_id)
		return false
	elseif type == 'custom' then
		return gsub_custom_inform(msg, content)
	else
		return _("Hi %s, and welcome to *%s*!"):format(msg.added.first_name:escape_hard(), msg.chat.title:escape_hard())
	end
end

local function get_goodbye(msg)
	if is_locked(msg.chat.id, 'Goodbye') then
		return false
	end
	local type = db:hget('chat:'..msg.chat.id..':goodbye', 'type') or 'custom'
	local content = db:hget('chat:'..msg.chat.id..':goodbye', 'content')
	if type == 'media' then
		local file_id = content
		api.sendDocumentId(msg.chat.id, file_id)
		return false
	elseif type == 'custom' then
		if not content then
			local name = msg.removed.first_name
			if msg.removed.username then
				name = name..' (@'..msg.removed.username..')'
			end
			return _("Goodbye, %s!"):format(name:escape_hard())
		end
		return gsub_custom_inform(msg, content)
	end
end

local action = function(msg, blocks)
	
	--avoid trolls
	if not msg.service then return end
	
	--if the bot join the chat
	if blocks[1] == 'botadded' then
		
		if db:hget('bot:general', 'adminmode') == 'on' and not roles.is_superadmin(msg.adder.id) then
			api.sendMessage(msg.chat.id, '_Admin mode is on: only the bot admin can add me to a new group_', true)
			api.leaveChat(msg.chat.id)
			return
		end
		if misc.is_blocked_global(msg.adder.id) then
			api.sendMessage(msg.chat.id, '_You ('..msg.adder.first_name:escape()..', '..msg.adder.id..') are in the blocked list_', true)
			api.leaveChat(msg.chat.id)
			return
		end
		
		misc.initGroup(msg.chat.id)
	end
	
	--if someone join the chat
	if blocks[1] == 'added' then
		
		if msg.added.username then
			local username = msg.added.username:lower()
			if username:find('bot', -3) then
				local antibot_status = db:hget('chat:'..msg.chat.id..':settings', 'Antibot')
				if antibot_status and antibot_status == 'on' and msg.from and not roles.is_admin_cached(msg) then
					api.banUser(msg.chat.id, msg.added.id)
				end
				return
			end
		end
		
		local text = get_welcome(msg)
		if text then
			api.sendMessage(msg.chat.id, text, true)
		end
		--if not text: welcome is locked or is a gif/sticker
	end
	
	--if the bot is removed from the chat
	if blocks[1] == 'botremoved' then
		
		--remove the group settings
		misc.remGroup(msg.chat.id)
		
		--save stats
        db:hincrby('bot:general', 'groups', -1)
	end
	
	if blocks[1] == 'removed' then
		if msg.remover and msg.removed then
			if msg.remover.id ~= msg.removed.id and msg.remover.id ~= bot.id then
				local action
				if msg.chat.type == 'supergroup' then
					action = 'ban'
				elseif msg.chat.type == 'group' then
					action = 'kick'
				end
				misc.saveBan(msg.removed.id, action)
			end
		end

		if msg.removed.username and msg.removed.username:lower():find('bot', -3) then return end
		local text = get_goodbye(msg)
		if text then
			api.sendMessage(msg.chat.id, text, true)
		end
	end
end

return {
	action = action,
	triggers = {
		'^###(botadded)',
		'^###(added)',
		'^###(botremoved)',
		'^###(removed)'
	}
}
