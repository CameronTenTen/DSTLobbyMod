# DSTLobbyMod
 DST Mod that turns the character select screen into a lobby.  
 This was created by modifying the klei lobby implementation used for forge and gorge.  

### Configuration
- Mode
  - ALL = Game starts when all connected players are ready and there must be more than the minimum number connected
  - MIN = Game starts when the minimum number of players are ready
  - ADMIN = Admin gets a start button, game starts when they click it
- Minimum players
  - Minimum number of players required for the game to start, admin mode doesn't use this
- Late join
  - Can new players join after the game has started

Admin can force start the game with this command:  
`require "usercommands".RunUserCommand("forcestartgame", {}, TheNet:GetClientTableForUser(TheNet:GetUserID()), nil)`


### Known issues
 - Waiting count doesn't update when the last player readies
   - timing issue with the dirty event trigger order?
