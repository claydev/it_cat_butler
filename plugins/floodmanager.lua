local function do_keyboard_flood(chat_id)
    --no: enabled, yes: disabled
    local status = db:hget('chat:'..chat_id..':settings', 'Flood') or config.chat_settings['settings']['Flood'] --check (default: disabled)
    if status == 'on' then
        status = _("✅ | ON")
    elseif status == 'off' then
        status = _("❌ | OFF")
    end
    
    local hash = 'chat:'..chat_id..':flood'
    local action = (db:hget(hash, 'ActionFlood')) or config.chat_settings['flood']['ActionFlood']
    if action == 'kick' then
        action_label = _("⚡️ kick")
    elseif action == 'ban' then
        action_label = _("⛔ ️ban")
	elseif action == 'tempban' then
		action_label = _("🔑 tempban")
    end
    local num = (db:hget(hash, 'MaxFlood')) or config.chat_settings['flood']['MaxFlood']
    local keyboard
	if action ~= 'tempban' then
		keyboard = {
			inline_keyboard = {
				{
					{text = status, callback_data = 'flood:status:'..chat_id},
					{text = action_label, callback_data = 'flood:action:'..chat_id},
				},
				{
					{text = '➖', callback_data = 'flood:dim:'..chat_id},
					{text = num, callback_data = 'flood:alert:num'},
					{text = '➕', callback_data = 'flood:raise:'..chat_id},
				},
			}
		}
	else
		local ban_duration = db:hget(hash, 'TempBanDuration') or tostring(config.chat_settings.flood['TempBanDuration'])
		keyboard = {
			inline_keyboard = {
				{
					{text = status, callback_data = 'flood:status:'..chat_id},
					{text = action_label, callback_data = 'flood:action:'..chat_id},
				},
				{
					{text = _("Duration"), callback_data = 'flood:alert:num'},
					{text = '➖', callback_data = 'flood:reduce:'..chat_id},
					{text = ban_duration, callback_data = 'flood:alert:num'},
					{text = '➕', callback_data = 'flood:increase:'..chat_id},
				},
				{
					{text = _("Sensitivity"), callback_data = 'flood:alert:num'},
					{text = '➖', callback_data = 'flood:dim:'..chat_id},
					{text = num, callback_data = 'flood:alert:num'},
					{text = '➕', callback_data = 'flood:raise:'..chat_id},
				},
			}
		}
	end
    
	local order = { 'text', 'forward', 'image', 'gif', 'sticker', 'video' }
    local exceptions = {
		text = _("Texts"),
		forward = _("Forward"),
        sticker = _("Stickers"),
        image = _("Images"),
        gif = _("GIFs"),
        video = _("Videos"),
    }
    local hash = 'chat:'..chat_id..':floodexceptions'
    for i, media in pairs(order) do
		translation = exceptions[media]
        --ignored by the antiflood-> yes, no
        local exc_status = (db:hget(hash, media)) or config.chat_settings['floodexceptions'][media]
        if exc_status == 'yes' then
            exc_status = '✅'
        else
            exc_status = '❌'
        end
        local line = {
            {text = translation, callback_data = 'flood:alert:voice'},
            {text = exc_status, callback_data = 'flood:exc:'..media..':'..chat_id},
        }
        table.insert(keyboard.inline_keyboard, line)
    end
    
    --back button
    table.insert(keyboard.inline_keyboard, {{text = '🔙', callback_data = 'config:back:'..chat_id}})
    
    return keyboard
end

function step(count, direction)
	if 20 < count and count < 60 then
		return count + 10 * direction
	elseif 60 < count and count < 240 then
		return count + 30 * direction
	elseif 240 < count and count < 720 then
		return count + 60 * direction
	elseif 720 < count then
		return count + 720 * direction
	else
		local ex = {1, 2, 3, 5, 7, 10, 15, 20, 30, 50, 60, 90, 210, 240, 300, 660, 720, 1440}
		local index
		for i, v in pairs(ex) do
			if v == count then
				index = i
				break
			end
		end
		if index then
			return ex[index + direction]
		else
			return 10
		end
	end
end

local function action(msg, blocks)
	local header = _([[
You can manage the group flood settings from here.

*1st row*
• *ON/OFF*: the current status of the anti-flood
• *Kick/Ban*: what to do when someone is flooding

*2nd row*
• you can use *+/-* to change the current sensitivity of the antiflood system
• the number it's the max number of messages that can be sent in _5 seconds_
• max value: _25_, min value: _4_

*3rd row* and below
You can set some exceptions for the antiflood:
• ✅: the media will be ignored by the anti-flood
• ❌: the media won\'t be ignored by the anti-flood
• *Note*: in "_texts_" are included all the other types of media (file, audio...)
]])

    
    if not msg.cb and msg.chat.type == 'private' then return end
    
    local chat_id = msg.target_id or msg.chat.id
    
    local text, keyboard
    
    if blocks[1] == 'antiflood' then
        if not roles.is_admin_cached(msg) then return end
        if blocks[2]:match('%d%d?') then
            if tonumber(blocks[2]) < 4 or tonumber(blocks[2]) > 25 then
				local text = _("`%s` is not a valid value!\nThe value should be *higher* than `3` and *lower* then `26`")
				api.sendReply(msg, text:format(blocks[1]), true)
			else
	    	    local new = tonumber(blocks[2])
	    	    local old = tonumber(db:hget('chat:'..msg.chat.id..':flood', 'MaxFlood')) or config.chat_settings['flood']['MaxFlood']
	    	    if new == old then
	            	api.sendReply(msg, _("The max number of messages is already %d"):format(new), true)
	    	    else
	            	db:hset('chat:'..msg.chat.id..':flood', 'MaxFlood', new)
					local text = _("The *max number* of messages (in *5 seconds*) changed _from_  %d _to_  %d")
	            	api.sendReply(msg, text:format(old, new), true)
	    	    end
            end
            return
        end
    else
        if not msg.cb then return end --avaoid trolls
        
        if blocks[1] == 'config' then
            keyboard = do_keyboard_flood(chat_id)
            api.editMessageText(msg.chat.id, msg.message_id, header, keyboard, true)
            return
        end
        
        if blocks[1] == 'alert' then
            if blocks[2] == 'num' then
                text = _("⚖ Current sensitivity. Tap on the + or the -")
            elseif blocks[2] == 'voice' then
                text = _("⚠️ Tap on an icon!")
            end
            api.answerCallbackQuery(msg.cb_id, text)
            return
        end
        
        if blocks[1] == 'exc' then
            local media = blocks[2]
            local hash = 'chat:'..chat_id..':floodexceptions'
            local status = (db:hget(hash, media)) or 'no'
            if status == 'no' then
                db:hset(hash, media, 'yes')
                text = _("❎ [%s] will be ignored by the anti-flood"):format(media)
            else
                db:hset(hash, media, 'no')
                text = _("🚫 [%s] won't be ignored by the anti-flood"):format(media)
            end
        end
        
        local action
        if blocks[1] == 'action' or blocks[1] == 'dim' or blocks[1] == 'raise' then
            if blocks[1] == 'action' then
                action = (db:hget('chat:'..chat_id..':flood', 'ActionFlood')) or 'kick'
            elseif blocks[1] == 'dim' then
                action = -1
            elseif blocks[1] == 'raise' then
                action = 1
            end
            text = misc.changeFloodSettings(chat_id, action):escape_hard()
		elseif blocks[1] == 'increase' then
			local hash = string.format('chat:%d:flood', chat_id)
			local old = tonumber(db:hget(hash, 'TempBanDuration')) or config.chat_settings.flood['TempBanDuration']
			local new = step(old, 1)
			db:hset(hash, 'TempBanDuration', new)
			text = string.format('📈 %dm → %dm', old, new)
		elseif blocks[1] == 'reduce' then
			local hash = string.format('chat:%d:flood', chat_id)
			local old = tonumber(db:hget(hash, 'TempBanDuration')) or config.chat_settings.flood['TempBanDuration']
			if old <= 1 then
				text = _("⚠️ Value must been positive")
			else
				local new = step(old, -1)
				db:hset(hash, 'TempBanDuration', new)
				text = string.format('📉 %dm → %dm', old, new)
			end
        end
        
        if blocks[1] == 'status' then
            local status = db:hget('chat:'..chat_id..':settings', 'Flood') or config.chat_settings['settings']['Flood']
            text = misc.changeSettingStatus(chat_id, 'Flood'):escape_hard()
        end
        
        keyboard = do_keyboard_flood(chat_id)
        api.editMessageText(msg.chat.id, msg.message_id, header, keyboard, true)
        api.answerCallbackQuery(msg.cb_id, text)
    end
end

return {
    action = action,
    triggers = {
        config.cmd..'(antiflood) (%d%d?)$',
        
        '^###cb:flood:(alert):(%w+)$',
        '^###cb:flood:(status):(-%d+)$',
        '^###cb:flood:(action):(-%d+)$',
        '^###cb:flood:(dim):(-%d+)$',
        '^###cb:flood:(raise):(-%d+)$',
		'^###cb:flood:(reduce):(-%d+)$',
		'^###cb:flood:(increase):(-%d+)$',
        '^###cb:flood:(exc):(%a+):(-%d+)$',
        
        '^###cb:(config):antiflood:'
    }
}
