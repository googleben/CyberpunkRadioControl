local RadioControl = require("radio_manager.lua")
local Radio = {
    playingPlaylist = false,
    playlist = {},
    playlistNames = {},
    dropdownStationInd = 0,
    dropdownStation = nil,
    dropdownStationPlaying = nil,
    dropdownSong = 1,
    updateTimer = 0,
    curPlayingInd = -1,
    nowPlaying = nil,
    nowPlayingArr = {},
    playlistById = {},
}

function Radio:AddSongToPlaylist(song)
    local id = song:GetID()
    if self.playlistById[id] then
        print("[Radio] Song already in playlist: " .. id)
        return
    end

    table.insert(self.playlist, song)
    table.insert(self.playlistNames, song:GetLocalized())
    self.playlistById[id] = true
    print("[Radio] Added song to playlist: " .. id)
    self:SavePlaylist()
end

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
            self:AddSongToPlaylist(RadioControl:GetSong(id))
        end
        print("[Radio] Loaded playlist with " .. #self.playlist .. " songs")
    else
        print("[Radio] WARNING: Could not read playlist file")
        self.playlist = {}
        self.playlistById = {}
        self.playlistNames = {}
    end
end

-- play a random song from the playlist that is not the current song
function Radio:PlayNextPlaylistSong()
    local n = math.random(1, #self.playlist)
    if #self.playlist == 0 then
        print("[Radio] Playlist is empty, cannot play next song")
        self.playingPlaylist = false
        return
    end
    if #self.playlist == 1 then
        n = 1
    else
        while n == self.curPlayingInd do
            n = math.random(1, #self.playlist)
        end
    end
    self.curPlayingInd = n
    local song = self.playlist[n]
    song:Play()
end

-- constructor
function Radio:Init()
    math.randomseed(os.time())
    RadioControl:Init()
    self:LoadPlaylist()
    print("[Radio] Loaded radio metadata")
end



-- update function, call every game update
function Radio:Update(dt)
    self.updateTimer = self.updateTimer + dt
    if self.updateTimer < 1 then return end
    self.updateTimer = 0
    for k, station in pairs(RadioControl.stations) do
        local np = station:GetNowPlaying()
        self.nowPlayingArr[k] = np
    end
    self.nowPlaying = RadioControl:GetPlayerRadio():GetNowPlaying()
    if self.dropdownStation ~= nil then
        self.dropdownStationPlaying = self.dropdownStation:GetNowPlaying()
    end
    if self.playingPlaylist then
        local currSong = self.playlist[self.curPlayingInd]

        if currSong == nil or self.nowPlaying == nil or currSong:GetID() ~= self.nowPlaying:GetID() then
            self:PlayNextPlaylistSong()
        end
    end
end

-- draw the ImGui interface
function Radio:Draw()
    --if not RadioControl.init then
    --    return
    --end
    if ImGui.BeginTabItem("Radio") then
        if self.nowPlaying == nil then
            ImGui.Text("No song playing")
        else
            ImGui.Text("Now playing " .. self.nowPlaying.localized .. " on " .. self.nowPlaying.station.localized)
        end
        if ImGui.Button(Radio.playingPlaylist and "Stop Playlist" or "Play Playlist") then
            if Radio.playingPlaylist then
                Radio.playingPlaylist = false
            else
                Radio.playingPlaylist = true
                self:PlayNextPlaylistSong()
            end
        end
        if Radio.playingPlaylist then
            if ImGui.Button("Next") then
                self:PlayNextPlaylistSong()
            end
        end
        if self.dropdownStation ~= nil then
            if self.dropdownStationPlaying ~= nil then
                ImGui.Text("Current station: " .. self.dropdownStation.localized .. " playing " .. self.dropdownStationPlaying.localized)
            else
                ImGui.Text("Current station: " .. self.dropdownStation.localized .. " playing None")
            end
        else
            self.dropdownStation = RadioControl:GetStation(self.dropdownStationInd)
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
        end
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

        ImGui.EndTabItem()
    end
    if ImGui.BeginTabItem("Now Playing") then
        if ImGui.BeginTable("NowPlayingTable", 2, ImGuiTableFlags.RowBg) then
            ImGui.TableSetupColumn("Station")
            ImGui.TableSetupColumn("Track")
            ImGui.TableHeadersRow()
            --print(RadioControl.stations)
            for k, station in pairs(RadioControl.stations) do
                local np = self.nowPlayingArr[k]
                if np == nil then
                    np = {localized = "None"}
                end
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                ImGui.Text(station.localized)
                ImGui.TableSetColumnIndex(1)
                ImGui.Text(np.localized)
            end
            ImGui.EndTable()
        end
        ImGui.EndTabItem()
    end
end

return Radio