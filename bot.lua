curl = require('cURL')
URL = require('socket.url')
JSON = require('dkjson')
redis = require('redis')
clr = require 'term.colors'
db = Redis.connect('127.0.0.1', 6379)
serpent = require('serpent')

function bot_init(on_reload) -- The function run when the bot is started or reloaded.
	
	config = dofile('config.lua') -- Load configuration file.
	assert(not (config.bot_api_key == "" or not config.bot_api_key), clr.red..'Insert the bot token in config.lua -> bot_api_key'..clr.reset)
	assert(#config.superadmins > 0, clr.red..'Insert your Telegram ID in config.lua -> superadmins'..clr.reset)
	assert(config.log.admin, clr.red..'Insert your Telegram ID in config.lua -> log.admin'..clr.reset)
	
	db:select(config.db or 0) --select the redis db
	
	misc, roles, users = dofile('utilities.lua') -- Load miscellaneous and cross-plugin functions.
	locale = dofile('languages.lua')
	api = require('methods')
	
	bot = api.getMe().result -- Get bot info
	bot.version = io.popen('git rev-parse --short HEAD'):read()

	plugins = {} -- Load plugins.
	for i,v in ipairs(config.plugins) do
		local p = dofile('plugins/'..v)
		if p.triggers then
			for funct, triggers in pairs(p.triggers) do
				if not p[funct] then
					p.triggers[funct] = nil
					print(clr.red..funct..' triggers ignored in '..v..': '..funct..' function not defined'..clr.reset)
				end
			end
		end
		table.insert(plugins, p)
	end
	if config.bot_settings.multipurpose_mode then
		for i,v in ipairs(config.multipurpose_plugins) do
			local p = dofile('plugins/multipurpose/'..v)
			table.insert(plugins, p)
		end
	end

	print('\n'..clr.blue..'BOT RUNNING:'..clr.reset, clr.red..'[@'..bot.username .. '] [' .. bot.first_name ..'] ['..bot.id..']'..clr.reset..'\n')
	
	-- Generate a random seed and "pop" the first random number. :)
	math.randomseed(os.time())
	math.random()

	last_update = last_update or 0 -- Set loop variables: Update offset,
	last_cron = last_cron or os.time() -- the time of the last cron job,
	is_started = true -- whether the bot should be running or not.
	
	if on_reload then
		return #plugins
	else
		api.sendAdmin(_("*Bot *@%s* started!*\n_%s_\n%d plugins loaded"):format(bot.username:escape(), os.date('!%c UTC'), #plugins), true)
		start_timestamp = os.time()
		current = {h = 0}
		last = {h = 0}
	end
end

-- for resolve username
local function extract_usernames(msg)
	if msg.from then
		if msg.from.username then
			db:hset('bot:usernames', '@'..msg.from.username:lower(), msg.from.id)
		end
		db:sadd(string.format('chat:%d:members', msg.chat.id), msg.from.id)
	end
	if msg.forward_from and msg.forward_from.username then
		db:hset('bot:usernames', '@'..msg.forward_from.username:lower(), msg.forward_from.id)
	end
	if msg.forward_from_chat and msg.forward_from_chat.username then
		db:hset('bot:usernames', '@'..msg.forward_from_chat.username:lower(), msg.forward_from_chat.id)
		end
	if msg.new_chat_member then
		if msg.new_chat_member.username then
			db:hset('bot:usernames', '@'..msg.new_chat_member.username:lower(), msg.new_chat_member.id)
	end
		db:sadd(string.format('chat:%d:members', msg.chat.id), msg.new_chat_member.id)
		end
	if msg.left_chat_member then
		if msg.left_chat_member.username then
			db:hset('bot:usernames', '@'..msg.left_chat_member.username:lower(), msg.left_chat_member.id)
		end
		db:srem(string.format('chat:%d:members', msg.chat.id), msg.left_chat_member.id)
	end
	if msg.reply then
		extract_usernames(msg.reply)
	end
	if msg.pinned_message then
		extract_usernames(msg.pinned_message)
	end
end

local function collect_stats(msg)
	
	--count the number of messages
	db:hincrby('bot:general', 'messages', 1)

	extract_usernames(msg)
	
	if msg.chat.type ~= 'private' and msg.chat.type ~= 'inline' and msg.from then
		db:hset('chat:'..msg.chat.id..':userlast', msg.from.id, os.time()) --last message for each user
		db:hset('bot:chats:latsmsg', msg.chat.id, os.time()) --last message in the group
	end
	
	--user stats
	if msg.from then
		db:hincrby('user:'..msg.from.id, 'msgs', 1)
	end
end

local function match_triggers(triggers, text)
  	if text and triggers then
  		text = text:gsub('@'..bot.username, '')
		for i, trigger in pairs(triggers) do
    	local matches = {}
	    	matches = { string.match(text, trigger) }
    	if next(matches) then
	    		return matches, trigger
			end
		end
  	end
end

local function on_msg_receive(msg, callback) -- The fn run whenever a message is received.
	--vardump('PARSED', msg)
	if not msg then
		return
	end
	
	if msg.chat.type ~= 'group' then --do not process messages from normal groups
		
	if msg.date < os.time() - 7 then return end -- Do not process old messages.
	if not msg.text then msg.text = msg.caption or '' end
	
	--[[if msg.text:match('^/start .+') then
		msg.text = '/' .. msg.text:input()
	end]]
	
	locale.language = db:get('lang:'..msg.chat.id) or 'en' --group language
	if not config.available_languages[locale.language] then
		locale.language = 'en'
	end

	collect_stats(msg)

	local continue = true
	local onm_success
	for i, plugin in pairs(plugins) do
			if plugin.onEveryMessage then
				onm_success, continue = xpcall(plugin.onEveryMessage, debug.traceback, msg)
				if not onm_success then
					print(continue)
					api.sendAdmin('An #error occurred (preprocess).\n'..tostring(continue)..'\n'..locale.language..'\n'..msg.text)
				end
			end
			if not continue then return end
	end
	
	for i,plugin in pairs(plugins) do
		if plugin.triggers then
				local blocks, trigger = match_triggers(plugin.triggers[callback], msg.text)
					if blocks then
						
					if msg.chat.type ~= 'private' and msg.chat.type ~= 'inline'and not db:exists('chat:'..msg.chat.id..':settings') and not msg.service then --init agroup if the bot wasn't aware to be in
							misc.initGroup(msg.chat.id)
						end
						
						if config.bot_settings.stream_commands then --print some info in the terminal
						print(clr.reset..clr.blue..'['..os.date('%F %T')..']'..clr.red..' '..trigger..clr.reset..' '..msg.from.first_name..' ['..msg.from.id..'] -> ['..msg.chat.id..']')
      					end
						
					--if not check_callback(msg, callback) then goto searchaction end
					local success, result = xpcall(plugin[callback], debug.traceback, msg, blocks) --execute the main function of the plugin triggered
						
						if not success then --if a bug happens
							print(result)
							if config.bot_settings.notify_bug then
								api.sendReply(msg, _("Sorry, a *bug* occurred"), true)
							end
          					api.sendAdmin('An #error occurred.\n'..result..'\n'..locale.language..'\n'..msg.text)
							return
						end
						
						if type(result) == 'string' then --if the action returns a string, make that string the new msg.text
							msg.text = result
					elseif not result then --if the action returns true, then don't stop the loop of the plugin's actions
							return
						end
					end

		end
		end
	end
end

local function parseMessageFunction(update)

	local msg, function_key
	
	if update.message then
		msg = update.message
		function_key = 'onTextMessage'
		if msg.text then
		elseif msg.photo then
	msg.media = true
			msg.media_type = 'photo'
	elseif msg.audio then
			msg.media = true
		msg.media_type = 'audio'
	elseif msg.document then
			msg.media = true
			msg.media_type = 'document'
		if msg.document.mime_type == 'video/mp4' then
			msg.media_type = 'gif'
		end
	elseif msg.sticker then
			msg.media = true
		msg.media_type = 'sticker'
		elseif msg.video then
			msg.media = true
			msg.media_type = 'video'
		elseif msg.voice then
			msg.media = true
			msg.media_type = 'voice'
	elseif msg.contact then
			msg.media = true
		msg.media_type = 'contact'
		elseif msg.venue then
			msg.media = true
			msg.media_type = 'venue'
		elseif msg.location then
			msg.media = true
			msg.media_type = 'location'
	elseif msg.game then
			msg.media = true
		msg.media_type = 'game'
		elseif msg.left_chat_member then
			msg.service = true
			if msg.left_chat_member.id == bot.id then
				msg.text = '###left_chat_member:bot'
			else
				msg.text = '###left_chat_member'
			end
		elseif msg.new_chat_member then
			msg.service = true
			if msg.new_chat_member.id == bot.id then
				msg.text = '###new_chat_member:bot'
			else
				msg.text = '###new_chat_member'
			end
		elseif msg.new_chat_photo then
			msg.service = true
			msg.text = '###new_chat_photo'
		elseif msg.delete_chat_photo then
			msg.service = true
			msg.text = '###delete_chat_photo'
		elseif msg.group_chat_created then
    		msg.service = true
    		msg.text = '###group_chat_created'
		elseif msg.supergroup_chat_created then
			msg.service = true
			msg.text = '###supergroup_chat_created'
		elseif msg.channel_chat_created then
			msg.service = true
			msg.text = '###channel_chat_created'
		elseif msg.migrate_to_chat_id then
			msg.service = true
			msg.text = '###migrate_to_chat_id'
		elseif msg.migrate_from_chat_id then
			msg.service = true
			msg.text = '###migrate_from_chat_id'
	else
			--callback = 'onUnknownType'
			print('Unknown update type') return
	end
	
	if msg.entities then
			for i, entity in pairs(msg.entities) do
			if entity.type == 'text_mention' then
				msg.mentions = msg.mentions or {}
				msg.mentions[entity.user.id] = true
				if entity.user.username then
					db:hset('bot:usernames', '@'..entity.user.username:lower(), entity.user.id)
				end
			end
		   if entity.type == 'mention' and entity.offset == 0 then
				-- FIXME: cut the username taking into consideration length of unicode characters
				local username = msg.text:sub(entity.offset + 1, entity.offset + entity.length)
				local user_id = misc.resolve_user(username, msg.chat.id)
				if user_id then
					msg.mentions = msg.mentions or {}
					msg.mentions[user_id] = true
				end
			end
			if entity.type == 'url' or entity.type == 'text_link' then
				if msg.text:match('[Tt][Ee][Ll][Ee][Gg][Rr][Aa][Mm]%.[Mm][Ee]') then
					msg.media_type = 'TGlink'
				else
					msg.media_type = 'link'
				end
				msg.media = true
			end
		end
	end
	if msg.reply_to_message then
		msg.reply = msg.reply_to_message
	if msg.reply.caption then
		msg.reply.text = msg.reply.caption
	end
		end
	--[[elseif update.edited_message then
		msg = update.edited_message
		function_key = 'onEditedMessage'
	elseif update.inline_query then
		msg = update.inline_query
		msg.inline = true
		msg.chat = {id = msg.from.id, type = 'inline', title = 'inline'}
		msg.date = os.time()
		msg.text = '###inline:'..msg.query
		function_key = 'onInlineQuery'
	elseif update.chosen_inline_result then
		msg = update.chosen_inline_result
		msg.text = '###chosenresult:'..msg.query
		msg.chat = {type = 'inline', id = msg.from.id, title = msg.from.first_name}
		msg.message_id = msg.inline_message_id
	msg.date = os.time()
		function_key = 'onChosenInlineQuery']]
	elseif update.callback_query then
		msg = update.callback_query
	msg.cb = true
		msg.text = '###cb:'..msg.data
		if msg.message then
			msg.original_text = msg.message.text
			msg.original_date = msg.message.date
	msg.message_id = msg.message.message_id
	msg.chat = msg.message.chat
		else --when the inline keyboard is sent via the inline mode
			msg.chat = {type = 'inline', id = msg.from.id, title = msg.from.first_name}
			msg.message_id = msg.inline_message_id
		end
		msg.date = os.time()
		msg.cb_id = msg.id
	msg.message = nil
		msg.target_id = msg.data:match('(-?%d+)$') --callback datas often (always) ship IDs. Create a shortcut
		function_key = 'onCallbackQuery'
	else
		--function_key = 'onUnknownType'
		print('Unknown update type') return
	end
	
	return on_msg_receive(msg, function_key)
end

bot_init() -- Actually start the script. Run the bot_init function.

while is_started do -- Start a loop while the bot should be running.
	local res = api.getUpdates(last_update+1) -- Get the latest updates
	if res then
		clocktime_last_update = os.clock()
		for i, msg in ipairs(res.result) do -- Go through every new message.
			last_update = msg.update_id
			current.h = current.h + 1
			parseMessageFunction(msg)
		end
	else
		print('Connection error')
	end
	if last_cron ~= os.date('%M') then -- Run cron jobs every minute.
		last_cron = os.date('%M')
		for i,v in ipairs(plugins) do
			if v.cron then -- Call each plugin's cron function, if it has one.
				local res, err = xpcall(v.cron, debug.traceback)
				if not res then
					print(err)
          			api.sendLog('An #error occurred (cron).\n'..err)
					return
				end
			end
		end
	end
end

print('Halted.\n')
