---@type RadioControl
local RadioControl = require("radio_manager")

---@class RadioC
-- Core playback state
---@field playingPlaylist boolean Whether the custom playlist is currently playing
---@field curPlayingInd integer Index of the current song in the playlist (-1 if none)
---@field nowPlaying Song|nil The song currently being played by the active station
---@field nowPlayingArr table<number, Song|nil> Map of station index to currently playing song
---@field playlistAutoAdvanceCooldown number Cooldown before auto-advancing to the next playlist song
-- Playlist management
---@field playlist Song[] Array of songs currently in the playlist
---@field playlistNames string[] Localized song names for UI display
---@field playlistById table<string, boolean> Fast lookup table for songs in the playlist
-- Blocklist management
---@field blocklist Song[] Array of blocked songs
---@field blocklistNames string[] Localized names of blocked songs for UI display
---@field blocklistById table<string, boolean> Fast lookup table for blocked songs
---@field blocklistEnabled boolean Whether blocklist filtering is currently active
-- UI / Dropdown selection state
---@field dropdownStationInd integer Index of the currently selected station in the dropdown
---@field dropdownStation Station|nil Currently selected station object
---@field dropdownStationPlaying Song|nil Song currently playing on the selected station
---@field dropdownSong integer Index of the currently selected song in the station dropdown
-- Runtime / Timers
---@field updateTimer number Timer accumulator for periodic updates
local Radio = {
    -- Core playback state
    playingPlaylist = false,
    curPlayingInd = -1,
    nowPlaying = nil,
    nowPlayingArr = {},
    playlistAutoAdvanceCooldown = 0,

    -- Playlist management
    playlist = {},
    playlistNames = {},
    playlistById = {},

    -- Blocklist management
    blocklist = {},
    blocklistNames = {},
    blocklistById = {},
    blocklistEnabled = true,

    -- UI / Dropdown selection state
    dropdownStationInd = 0,
    dropdownStation = nil,
    dropdownStationPlaying = nil,
    dropdownSong = 1,

    -- Runtime / Timers
    updateTimer = 0,
}


------------------------------------------------------------------------
-- Playlist management
------------------------------------------------------------------------

---@param song Song
function Radio:AddSongToPlaylistNoSave(song)
    local id = song:GetID()
    if self.playlistById[id] then
        print("[Radio] Song already in playlist: " .. id)
        return
    end
    if self.blocklistById[id] then
        print("[Radio] Song is in blocklist, cannot add to playlist: " .. id)
        return
    end

    table.insert(self.playlist, song)
    table.insert(self.playlistNames, song:GetLocalized())
    self.playlistById[id] = true
    print("[Radio] Added song to playlist: " .. id)
end

---@param song Song
function Radio:AddSongToPlaylist(song)
    self:AddSongToPlaylistNoSave(song)
    self:SavePlaylist()
end

---@param song Song
function Radio:RemoveSongFromPlaylist(song)
    local id = song:GetID()
    if not self.playlistById[id] then
        print("[Radio] Song not found in playlist: " .. id)
        return
    end

    -- Find and remove from playlist array
    for i, s in ipairs(self.playlist) do
        if s:GetID() == id then
            table.remove(self.playlist, i)
            table.remove(self.playlistNames, i)
            break
        end
    end

    -- Remove from lookup table
    self.playlistById[id] = nil
    print("[Radio] Removed song from playlist: " .. id)
    self:SavePlaylist()
end

function Radio:SavePlaylist()
    local playlistFile = io.open("data/playlist.json", "w")
    if playlistFile ~= nil then
        local ids = {}
        for _, song in ipairs(self.playlist) do
            table.insert(ids, song:GetID())
        end
        playlistFile:write(json.encode(ids))
        playlistFile:close()
        print("[Radio] Saved playlist")
    else
        print("[Radio] ERROR: Could not write playlist")
    end
end

function Radio:ClearPlaylist()
    self.playlist = {}
    self.playlistById = {}
    self.playlistNames = {}
    self:SavePlaylist()
    print("[Radio] Cleared playlist")
end

function Radio:LoadPlaylist()
    local playlistFile = io.open("data/playlist.json", "r")
    if playlistFile ~= nil then
        local ids = json.decode(playlistFile:read("*a"))
        playlistFile:close()
        self.playlist = {}
        self.playlistById = {}
        self.playlistNames = {}
        for _, id in ipairs(ids) do
            self:AddSongToPlaylistNoSave(RadioControl:GetSong(id))
        end
        print("[Radio] Loaded playlist with " .. #self.playlist .. " songs")
    else
        print("[Radio] WARNING: Could not read playlist file")
        self.playlist = {}
        self.playlistById = {}
        self.playlistNames = {}
    end
end


------------------------------------------------------------------------
-- Playlist dynamics
------------------------------------------------------------------------

-- play a random song from the playlist that is not the current song
function Radio:PlayNextPlaylistSong()
    print("[Radio] Advancing to next playlist song")
    local currentSong = nil
    if self.curPlayingInd ~= -1 then
        currentSong = self.playlist[self.curPlayingInd]
    end
    if #self.playlist == 0 then
        print("[Radio] Playlist is empty, cannot play next song")
        self.playingPlaylist = false
        return nil
    end
    local skipList = {currentSong}
    if self.blocklistEnabled then
        skipList = { currentSong, unpack(self.blocklist) }
    end
    local chosen = RadioControl:PlayRandomSongFromList(self.playlist, true, skipList)
    if chosen then
        for i, s in ipairs(self.playlist) do
            if s:GetID() == chosen:GetID() then
                self.curPlayingInd = i
                break
            end
        end
    else
        print("[Radio] ERROR: Could not play next playlist song")
        self.playingPlaylist = false
    end
    return chosen
end

------------------------------------------------------------------------
-- Blocklist management
------------------------------------------------------------------------

---@param song Song
function Radio:AddSongToBlocklistNoSave(song)
    local id = song:GetID()
    if self.blocklistById[id] then
        print("[Radio] Song already in blocklist: " .. id)
        return
    end
    if self.playlistById[id] then
        print("[Radio] Song is in playlist, cannot add to blocklist: " .. id)
        return
    end
    table.insert(self.blocklist, song)
    table.insert(self.blocklistNames, song:GetLocalized())
    self.blocklistById[id] = true
    print("[Radio] Added song to blocklist: " .. id)
end

---@param song Song
function Radio:AddSongToBlocklist(song)
    self:AddSongToBlocklistNoSave(song)
    self:SaveBlocklist()
end

---@param song Song
function Radio:RemoveSongFromBlocklist(song)
    local id = song:GetID()
    if not self.blocklistById[id] then
        print("[Radio] Song not found in blocklist: " .. id)
        return
    end
    for i, s in ipairs(self.blocklist) do
        if s:GetID() == id then
            table.remove(self.blocklist, i)
            table.remove(self.blocklistNames, i)
            break
        end
    end
    self.blocklistById[id] = nil
    print("[Radio] Removed song from blocklist: " .. id)
    self:SaveBlocklist()
end

function Radio:ClearBlocklist()
    self.blocklist = {}
    self.blocklistNames = {}
    self.blocklistById = {}
    self:SaveBlocklist()
    print("[Radio] Cleared blocklist")
end

function Radio:SaveBlocklist()
    local f = io.open("data/blocklist.json", "w")
    if f ~= nil then
        local ids = {}
        for _, song in ipairs(self.blocklist) do
            table.insert(ids, song:GetID())
        end
        f:write(json.encode(ids))
        f:close()
        print("[Radio] Saved blocklist")
    else
        print("[Radio] ERROR: Could not write blocklist file")
    end
end

function Radio:LoadBlocklist()
    local f = io.open("data/blocklist.json", "r")
    if f ~= nil then
        local ids = json.decode(f:read("*a"))
        f:close()
        self.blocklist = {}
        self.blocklistNames = {}
        self.blocklistById = {}
        for _, id in ipairs(ids) do
            self:AddSongToBlocklistNoSave(RadioControl:GetSong(id))
        end
        print("[Radio] Loaded blocklist with " .. #self.blocklist .. " songs")
    else
        print("[Radio] WARNING: Could not read blocklist file")
        self.blocklist = {}
        self.blocklistNames = {}
        self.blocklistById = {}
    end
end


-- constructor
function Radio:Init()
    math.randomseed(os.time())
    RadioControl:Init()
    self:LoadPlaylist()
    self:LoadBlocklist()
    print("[Radio] Loaded radio metadata")
end

-- update function, call every game update
function Radio:Update(dt)
    self.updateTimer = self.updateTimer + dt
    self.playlistAutoAdvanceCooldown = math.max(0, self.playlistAutoAdvanceCooldown - dt)
    if self.updateTimer < 1 then return end
    self.updateTimer = 0
    for k, station in pairs(RadioControl.stations) do
        local np = station:GetNowPlaying()
        -- auto-skip blocked songs
        if self.blocklistEnabled and np and self.blocklistById[np:GetID()] then
            print("[Radio] Blocked song detected, skipping... (" .. np.localized .. ")")
            station:SkipTrack(self.blocklist)
        end
        self.nowPlayingArr[k] = np
    end
    self.nowPlaying = RadioControl:GetPlayerRadio():GetNowPlaying()
    if self.dropdownStation ~= nil then
        self.dropdownStationPlaying = self.dropdownStation:GetNowPlaying()
    end
    if self.playingPlaylist and self.playlistAutoAdvanceCooldown == 0 then
        if self.curPlayingInd == -1 then
            self:PlayNextPlaylistSong()
            self.playlistAutoAdvanceCooldown = 10
        else
            local currSong = self.playlist[self.curPlayingInd]

            if currSong == nil or self.nowPlaying == nil or currSong:GetID() ~= self.nowPlaying:GetID() then
                self:PlayNextPlaylistSong()
                self.playlistAutoAdvanceCooldown = 10
            end
        end
    end
end

-- draw the ImGui interface
function Radio:Draw()
    --if not RadioControl.init then
    --    return
    --end
    if ImGui.Begin("RadioControl", ImGuiWindowFlags.NoScrollbar) then
        if self.nowPlaying == nil then
            ImGui.Text("No song playing")
        else
            ImGui.Text("Now Playing")
            ImGui.SameLine()
            ImGui.TextColored(0, 1, 1, 1, self.nowPlaying.localized)
            ImGui.SameLine()
            ImGui.Text("on")
            ImGui.SameLine()
            ImGui.TextColored(1, 0.8, 0, 1, self.nowPlaying:GetStation().localized)
        end

        ImGui.Text("Playlist:")
        ImGui.SameLine()
        if self.playingPlaylist then
            ImGui.TextColored(0, 1, 0, 1, "Playing")
        else
            ImGui.TextColored(1, 0, 0, 1, "Stopped")
        end
        ImGui.Text("Blocklist:")
        ImGui.SameLine()
        if self.blocklistEnabled then
            ImGui.TextColored(0, 1, 0, 1, "Enabled")
        else
            ImGui.TextColored(1, 0, 0, 1, "Disabled")
        end

        ImGui.Separator()

        if ImGui.BeginTabBar("RadioControlTabs", ImGuiTabBarFlags.None) then
            
            if ImGui.BeginTabItem("Radio") then
                ImGui.BeginDisabled(self.nowPlaying == nil)
                if ImGui.Button("Go to now playing") then
                    self.dropdownStation = self.nowPlaying:GetStation()
                    self.dropdownStationInd = self.dropdownStation:GetIndex()
                    self.dropdownStationPlaying = self.dropdownStation:GetNowPlaying()
                    for i, s in ipairs(self.dropdownStation.tracks) do
                        if s:GetID() == self.nowPlaying:GetID() then
                            self.dropdownSong = i
                            break
                        end
                    end
                end
                ImGui.EndDisabled()

                if ImGui.Button(Radio.playingPlaylist and "Stop Playlist" or "Play Playlist") then
                    if Radio.playingPlaylist then
                        Radio.playingPlaylist = false
                    else
                        Radio.playingPlaylist = true
                        self:PlayNextPlaylistSong()
                    end
                end
                ImGui.SameLine()
                if ImGui.Button(self.blocklistEnabled and "Disable Blocklist" or "Enable Blocklist") then
                    self.blocklistEnabled = not self.blocklistEnabled
                end
                if Radio.playingPlaylist then
                    if ImGui.Button("Skip playlist song") then
                        self:PlayNextPlaylistSong()
                    end
                end

                ImGui.Separator()
                ImGui.Text("Song Selector")

                if self.dropdownStation == nil then
                    self.dropdownStation = RadioControl:GetStation(self.dropdownStationInd)
                end
                ImGui.Text("Selected station:")
                ImGui.SameLine()
                ImGui.TextColored(1, 0.8, 0, 1, self.dropdownStation.localized)
                ImGui.SameLine()
                ImGui.Text("playing")
                ImGui.SameLine()
                if self.dropdownStationPlaying == nil then
                    ImGui.TextColored(1, 0, 0, 1, "None")
                else
                    ImGui.TextColored(0, 1, 1, 1, self.dropdownStationPlaying.localized)
                end
                
                if ImGui.BeginCombo("Stations", self.dropdownStation.localized) then
                    for i, tmp in pairs(RadioControl.stations) do
                        if ImGui.Selectable(tmp.localized, self.dropdownStationInd == i) then
                            self.dropdownStationInd = i
                            self.dropdownStation = tmp
                            self.dropdownStationPlaying = self.dropdownStation:GetNowPlaying()
                            self.dropdownSong = 1
                        end
                    end
                    ImGui.EndCombo()
                end
                local currSong = self.dropdownStation.tracks[self.dropdownSong]
                if ImGui.BeginCombo("Songs", currSong.localized) then
                    local songs = self.dropdownStation.tracks
                    for i = 1, #songs do
                        if ImGui.Selectable(songs[i].localized, self.dropdownSong == i) then
                            self.dropdownSong = i
                        end
                    end
                    ImGui.EndCombo()
                end
                if ImGui.Button("Play") then
                    currSong:Play()
                    RadioControl:GetPlayerRadio():SwitchToStation(currSong)
                end

                ImGui.SameLine()
                --add/remove from playlist
                local indInPlaylist = -1
                if self.playlistById[currSong.id] then
                    if ImGui.Button("Remove from Playlist") then
                        self:RemoveSongFromPlaylist(currSong)
                    end
                    for i, s in ipairs(self.playlist) do
                        if s:GetID() == currSong:GetID() then
                            indInPlaylist = i
                            break
                        end
                    end
                else
                    if ImGui.Button("Add to Playlist") then
                        self:AddSongToPlaylist(currSong)
                    end
                end

                ImGui.SameLine()
                --add/remove from blocklist
                local indInBlocklist = -1
                if self.blocklistById[currSong:GetID()] then
                    if ImGui.Button("Remove from Blocklist") then
                        self:RemoveSongFromBlocklist(currSong)
                    end
                    for i, s in ipairs(self.blocklist) do
                        if s:GetID() == currSong:GetID() then
                            indInBlocklist = i
                            break
                        end
                    end
                else
                    if ImGui.Button("Add to Blocklist") then
                        self:AddSongToBlocklist(currSong)
                    end
                end

                -- Playlist UI
                ImGui.Separator()
                ImGui.Text("Playlist")

                local a, b = ImGui.ListBox("Playlist", indInPlaylist - 1, self.playlistNames, #self.playlistNames, 5)
                if b then
                    a = a + 1
                    local song = self.playlist[a]
                    self.dropdownStation = song:GetStation()
                    self.dropdownStationInd = self.dropdownStation:GetIndex()
                    self.dropdownStationPlaying = self.dropdownStation:GetNowPlaying()
                    for i, s in ipairs(self.dropdownStation.tracks) do
                        if s:GetID() == song:GetID() then
                            self.dropdownSong = i
                            break
                        end
                    end
                end

                -- Blocklist UI
                ImGui.Separator()
                ImGui.Text("Blocklist")

                local c, d = ImGui.ListBox("Blocklist", indInBlocklist - 1, self.blocklistNames, #self.blocklistNames, 5)
                if d then
                    c = c + 1
                    local song = self.blocklist[c]
                    self.dropdownStation = song:GetStation()
                    self.dropdownStationInd = self.dropdownStation:GetIndex()
                    self.dropdownStationPlaying = self.dropdownStation:GetNowPlaying()
                    for i, s in ipairs(self.dropdownStation.tracks) do
                        if s:GetID() == song:GetID() then
                            self.dropdownSong = i
                            break
                        end
                    end
                end


                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem("Now Playing") then
                if ImGui.BeginTable("NowPlayingTable", 2, ImGuiTableFlags.RowBg) then
                    ImGui.TableSetupColumn("Station")
                    ImGui.TableSetupColumn("Track")
                    ImGui.TableHeadersRow()
                    for k, station in pairs(RadioControl.stations) do
                        local np = self.nowPlayingArr[k]
                        if np == nil then
                            np = {localized = "None", fake = true}
                        end
                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0)
                        local highlight = self.nowPlaying ~= nil and not np.fake and np:GetID() == self.nowPlaying:GetID()
                        if highlight then
                            ImGui.TextColored(1, 0.7, 0, 1, station.localized)
                        else
                            ImGui.Text(station.localized)
                        end
                        ImGui.SameLine()
                        if ImGui.Button("Play##" .. k) then
                            print("Switching to station " .. station.localized)
                            RadioControl:GetPlayerRadio():SwitchToStation(station)
                        end
                        ImGui.SameLine()
                        if ImGui.Button("Skip##" .. k) then
                            print("Skipping track on station " .. station.localized)
                            station:SkipTrack(self.blocklistEnabled and self.blocklist or nil)
                        end
                        ImGui.TableSetColumnIndex(1)
                        if highlight then
                            ImGui.TextColored(0, 1, 1, 1, np.localized)
                        else
                            ImGui.Text(np.localized)
                        end
                    end
                    ImGui.EndTable()
                end
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
    end
    ImGui.End()
end

return Radio