local TEMPLATES = require "widgets/redux/templates"

-- make sure lobby is added to TheNet for any gamemode
-- I really tried to add the component similar to quagmire_network.lua, but generic net doesnt seem to have a hook for that?
-- these didn't work
-- GLOBAL.TheWorld.net:AddComponent("worldcharacterselectlobby")
-- AddGamePostInit(function (inst)
-- AddPrefabPostInit("world", function (inst)
-- AddSimPostInit(function (inst)
-- don't like this solution much, seems like it could prevent the mod working easily with any gamemode
AddPrefabPostInit("forest_network", function (inst)
	inst:AddComponent("worldcharacterselectlobby")
	local MIN_PLAYERS = GetModConfigData("MIN_PLAYERS")
	local ADMIN_MODE = GetModConfigData("ADMIN_MODE")
	inst.components.worldcharacterselectlobby.MIN_PLAYERS = MIN_PLAYERS
	inst.components.worldcharacterselectlobby.ADMIN_MODE = ADMIN_MODE
end)
