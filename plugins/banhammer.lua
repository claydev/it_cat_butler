local function cron()
	local all = db:hgetall('tempbanned')
	if next(all) then
		for unban_time,info in pairs(all) do
			if os.time() > tonumber(unban_time) then
				local chat_id, user_id = info:match('(-%d+):(%d+)')
				api.unbanUser(chat_id, user_id, true)
				api.unbanUser(chat_id, user_id, false)
				db:hdel('tempbanned', unban_time)
				db:srem('chat:'..chat_id..':tempbanned', user_id) --hash needed to check if an user is already tempbanned or not
			end
		end
	end
end

local function get_user_id(msg, blocks)
	if msg.cb then
		return blocks[2]
	elseif msg.reply then
		return msg.reply.from.id
	elseif blocks[2] then
		if msg.mentions then
			return msg.mentions[-1]
		else
			return misc.resolve_user(blocks[2], msg.chat.id)
		end
	end
end

local function get_nick(msg, blocks)
	local admin, target
	--admin
	if msg.from.username then
		admin = misc.getname_link(msg.from.first_name, msg.from.username)
	else
		admin = msg.from.first_name:mEscape()
	end
	--target
	if msg.reply then --kick/ban the replied user
		if msg.reply.from.username then
			target = misc.getname_link(msg.reply.from.first_name, msg.reply.from.username)
		else
			target = msg.reply.from.first_name:mEscape()
		end
	elseif blocks then
		target = misc.getname_link(blocks[2]:gsub('@', ''), blocks[2])
	end
	return admin, target
end

local function check_valid_time(temp)
	temp = tonumber(temp)
	if temp == 0 then
		return false, 1
	elseif temp > 10080 then --1 week
		return false, 2
	else
		return temp
	end
end

local function get_time_reply(minutes)
	local time_string = ''
	local time_table = {}
	time_table.days = math.floor(minutes/(60*24))
	minutes = minutes - (time_table.days*60*24)
	time_table.hours = math.floor(minutes/60)
	time_table.minutes = minutes % 60
	if not(time_table.days == 0) then
		time_string = time_table.days..'d'
	end
	if not(time_table.hours == 0) then
		time_string = time_string..' '..time_table.hours..'h'
	end
	time_string = time_string..' '..time_table.minutes..'m'
	return time_string, time_table
end

local action = function(msg, blocks, ln)
	if msg.chat.type ~= 'private' then
		if roles.is_admin_cached(msg) then
			--commands that don't need a target user
			if blocks[1] == 'kickme' then
				api.sendReply(msg, _("I can't kick or ban an admin", msg.ln), true)
				return
			end
		    
		    --commands that need a target user
		    
		    if not msg.reply_to_message and not blocks[2] and not msg.cb then
		        api.sendReply(msg, _("Reply to someone", msg.ln)) return
		    end
		    if msg.reply and msg.reply.from.id == bot.id then return end
		 	
		 	local res
		 	local chat_id = msg.chat.id
		 	
		 	if blocks[1] == 'tempban' then
				if not msg.reply then
					api.sendReply(msg, _("Reply to someone", msg.ln))
					return
				end
				local user_id = msg.reply.from.id
				local temp, code = check_valid_time(blocks[2])
				if not temp then
					if code == 1 then
						api.sendReply(msg, _("For this, you can directly use /ban", msg.ln))
					else
						api.sendReply(msg, _("The time limit is one week (10 080 minutes)", msg.ln))
					end
					return
				end
				local val = msg.chat.id..':'..user_id
				local unban_time = os.time() + (temp * 60)
				
				--try to kick
				local res, motivation = api.banUser(chat_id, user_id, is_normal_group, msg.ln)
		    	if not res then
		    		if not motivation then
		    			motivation = _("I can't kick this user.\n"
								.. "Probably I'm not an Amdin, or the user is an Admin iself", msg.ln)
		    		end
		    		api.sendReply(msg, motivation, true)
		    	else
		    		misc.saveBan(user_id, 'tempban') --save the ban
		    		db:hset('tempbanned', unban_time, val) --set the hash
					local time_reply = get_time_reply(temp)
					local banned_name = misc.getname(msg.reply)
					local is_already_tempbanned = db:sismember('chat:'..chat_id..':tempbanned', user_id) --hash needed to check if an user is already tempbanned or not
					local text
					if is_already_tempbanned then
						text = _("Ban time updated for %s. Ban expiration: %s", msg.ln):format(banned_name, time_reply)
					else
						text = _("User %s banned. Ban expiration: %s", msg.ln):format(banned_name, time_reply)
						db:sadd('chat:'..chat_id..':tempbanned', user_id) --hash needed to check if an user is already tempbanned or not
					end
					api.sendMessage(chat_id, text)
				end
			end
		 	
		 	--get the user id, send message and break if not found
		 	local user_id = get_user_id(msg, blocks)
		 	if not user_id then
		 		api.sendReply(msg, _("I've never seen this user before.\n"
						.. "If you want to teach me who is he, forward me a message from him", msg.ln), true)
		 		return
		 	end
		 	
		 	if blocks[1] == 'kick' then
		    	local res, motivation = api.kickUser(chat_id, user_id, msg.ln)
		    	if not res then
		    		if not motivation then
		    			motivation = _("I can't kick this user.\n"
								.. "Probably I'm not an Amdin, or the user is an Admin iself", msg.ln)
		    		end
		    		api.sendReply(msg, motivation, true)
		    	else
		    		local kicker, kicked = get_nick(msg, blocks)
		    		misc.saveBan(user_id, 'kick')
		    		api.sendMessage(msg.chat.id, _("%s kicked %s!", msg.ln):format(kicker, kicked), true)
		    	end
	    	end
	   		if blocks[1] == 'ban' then
	   			local res, motivation = api.banUser(chat_id, user_id, msg.normal_group, msg.ln)
		    	if not res then
		    		if not motivation then
		    			motivation = _("I can't kick this user.\n"
								.. "Probably I'm not an Amdin, or the user is an Admin iself", msg.ln)
		    		end
		    		api.sendReply(msg, motivation, true)
		    	else
		    		--save the ban
		    		misc.saveBan(user_id, 'ban')
		    		--add to banlist
		    		local nick = get_nick(msg, blocks) --banned user
		    		local why
		    		if msg.reply then
		    			why = msg.text:input()
		    		else
		    			why = msg.text:gsub(config.cmd..'ban @[%w_]+%s?', '')
		    		end
		    		local banner, banned = get_nick(msg, blocks)
					local keyboard = {inline_keyboard = {{{text = _("Unban"), callback_data = 'unban:'..user_id}}}}
		    		api.sendKeyboard(msg.chat.id, _("%s banned %s!", msg.ln):format(banner, banned), keyboard, true)
		    	end
    		end
   			if blocks[1] == 'unban' then
   				local status = misc.getUserStatus(chat_id, user_id)
   				if not(status == 'kicked') and not(msg.chat.type == 'group') then
   					api.sendReply(msg, _("The user is not banned", msg.ln), true)
   					return
   				end
   				local res = api.unbanUser(chat_id, user_id, msg.normal_group)
   				local text
   				if not res and msg.chat.type == 'group' then
   					text = _("The user is not banned", msg.ln)
   				else
   					--misc.remBanList(msg.chat.id, user_id)
   					text = _("User unbanned by %s!", msg.ln):format(misc.getname_link(msg.from.first_name, msg.from.username) or msg.from.first_name:mEscape())
   				end
   				--send reply if normal message, edit message if callback
   				if not msg.cb then
   					api.sendReply(msg, text, true)
   				else
   					api.editMessageText(msg.chat.id, msg.message_id, text..'\n`[user_id: '..user_id..']`', false, true)
   				end
   			end
		else
			if blocks[1] == 'kickme' then
				api.kickUser(msg.chat.id, msg.from.id, msg.ln)
			end
			if msg.cb then --if the user tap on 'unban', show the pop-up
				api.answerCallbackQuery(msg.cb_id, _("You are *not* an admin", msg.ln):mEscape_hard())
			end
		end
	end
end

return {
	action = action,
	cron = cron,
	triggers = {
		config.cmd..'(kickme)%s?',
		config.cmd..'(kick) (@[%w_]+)',
		config.cmd..'(kick)',
		config.cmd..'(ban) (@[%w_]+)',
		config.cmd..'(ban)',
		config.cmd..'(tempban) (%d+)',
		config.cmd..'(unban) (@[%w_]+)',
		config.cmd..'(unban)',
		
		'^###cb:(unban):(%d+)$',
		'^###cb:(banlist)(-)$',
	}
}
