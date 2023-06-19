name = "Pre-game lobby"
description = "Want all players to start a world at the same time? \n"..
"Prevents anyone from spawning before all players are ready. \n"..
"Can also be controlled by an administrator. \n"..
"Or be set to require a minimum number of players. \n"
author = "camerontenten"
version = "1.0"
forumthread = ""
api_version_dst = 10
all_clients_require_mod = true
client_only_mod = false
dst_compatible = true
icon_atlas = "modicon.xml"
icon = "modicon.tex"
server_filter_tags = {"Lobby"}


local numbers = {}
for i = 1, 64 do
	-- tostring() not available? hack it with concatenation
	numbers[i] = {description = ""..i, data = i}
end

configuration_options =
{
	{
		name = "ADMIN_MODE",
		label = "Starting Condition",
		hover = "How to decide when the game can start",
		options =
		{
			-- All players must be ready, and there must be more than the minimum number of players
			{description = "All Ready", data = "ALL"},
			-- Minimum number of players must be ready, but extra players don't have to be
			{description = "Minimum Ready", data = "MIN"},
			-- Admin gets a start button, players can still ready but it means nothing
			{description = "Admin Controlled", data = "ADMIN"},
		},
		default = "ALL"
	},
	{
		name = "MIN_PLAYERS",
		label = "Minimum players",
		hover = "How many players are required before a game can start",
		options = numbers,
		default = 2
	},
	{
		name = "LATE_JOIN",
		label = "Allow Late Join",
		hover = "Can new players join after the game has started",
		options = {
			{description = "Yes", data = true},
			{description = "No", data = false},
		},
		default = true,
	}
}
