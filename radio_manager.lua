---@class RadioControl
---@field stations Station[]
---@field stationsByName { [string]: Station }
---@field stationsByLocKey { [string]: Station }
---@field stationsByLocalized { [string]: Station }
---@field numStations integer
---@field songs { [string]: Song }
---@field songsByLocKey { [string]: Song }
---@field songsByPrimaryLocKey { [integer]: Song }
---@field songsByLocalized { [string]: Song }
---@field init boolean
local RadioControl = {
    init = false,
}
-- Song class. Represents a single song/track
---@class Song
---@field id string
---@field station Station
---@field primaryLocKey integer
---@field locKey string
---@field isStreamingFriendly boolean
---@field localized string
local Song = {}
Song.__index = Song
-- Station class. Represents a radio station with multiple songs
---@class Station
---@field id string
---@field localized string
---@field index integer
---@field speaker string
---@field tracks Song[]
local Station = {}
Station.__index = Station

--TODO: handle radio_station_05_pop_completed_sq017 vs radio_station_05_pop

---@alias TrackEventName string
---@alias LocKey string
---@alias PrimaryLocKey integer
---@alias RadioSpeaker string

---@class TrackData
---@field name string                 -- e.g. "radio_station_01_att_rock"
---@field radioInd integer            -- e.g. 5 (ERadioStationList index)
---@field locKey LocKey               -- e.g. "Gameplay-Devices-Radio-RadioStationAttRock"
---@field speaker RadioSpeaker        -- e.g. "MaximumMike"
---@field tracks TrackEventName[]     -- e.g. { "mus_radio_01_att_rock_heaven_ho", ... }

---@class TrackMetadataRaw
---@field isStreamingFriendly integer|boolean  -- JSON uses 0/1; normalize to boolean later
---@field localizationKey LocKey
---@field primaryLocKey PrimaryLocKey
---@field trackEventName TrackEventName

---@class TrackMetadata
---@field isStreamingFriendly boolean
---@field localizationKey LocKey
---@field primaryLocKey PrimaryLocKey
---@field trackEventName TrackEventName

---@alias TrackToMetadata table<TrackEventName, TrackMetadata>

local function loadJson(path)
    local f = io.open(path, "r")
    if f ~= nil then
        local ret = json.decode(f:read("*a"))
        f:close()
        return ret
    else
        print("[Radio Manager] ERROR: COULD NOT OPEN " .. path)
        return nil
    end
end

------------------------------------------------------------------------
-- RadioControl class methods
------------------------------------------------------------------------

--- Initializes the RadioControl system by loading metadata from disk
function RadioControl:Init()
    if self.init then return end
    ---@type TrackData[]|nil
    local tracksData = loadJson("data/radio_tracks.json")
    ---@type TrackMetadata[]|nil
    local tracksMetadataRaw = loadJson("data/radio_tracks_metadata.json")
    if tracksData == nil or tracksMetadataRaw == nil then
        print("[Radio Manager] ERROR: COULD NOT LOAD DATA FILES")
        return
    end

    
    -- Normalize raw metadata to boolean-friendly typed records
    ---@type TrackMetadata[]
    local tracksMetadata = {}
    for i, m in ipairs(tracksMetadataRaw) do
        ---@type TrackMetadata
        tracksMetadata[i] = {
            isStreamingFriendly = (m.isStreamingFriendly == true) or (m.isStreamingFriendly == 1),
            localizationKey     = m.localizationKey,
            primaryLocKey       = m.primaryLocKey,
            trackEventName      = m.trackEventName,
        }
    end

    -- first, build stations
    self.stations = {}
    self.stationsByName = {}
    self.stationsByLocKey = {}
    self.stationsByLocalized = {}
    self.numStations = 0
    for _, stationData in ipairs(tracksData) do
        local localized = Game.GetLocalizedTextByKey(stationData.locKey)
        local station = Station:New(stationData.name, localized, stationData.radioInd, stationData.speaker)
        self.stations[stationData.radioInd] = station
        self.stationsByName[stationData.name] = station
        self.stationsByLocKey[stationData.locKey] = station
        self.stationsByLocalized[localized] = station
        self.numStations = self.numStations + 1
    end

    -- then, build songs and add to stations
    -- build song metadata map
    ---@type TrackToMetadata
    local trackToMetadata = {}
    for _, track in ipairs(tracksMetadata) do
        trackToMetadata[track.trackEventName] = track
    end

    self.songs = {}
    self.songsByLocKey = {}
    self.songsByPrimaryLocKey = {}
    self.songsByLocalized = {}
    for _, stationData in ipairs(tracksData) do
        local station = self.stations[stationData.radioInd]
        for _, trackName in ipairs(stationData.tracks) do
            local trackData = trackToMetadata[trackName]
            if trackData ~= nil then
                local song = Song:New(trackData, station)
                self.songs[trackName] = song
                self.songsByLocKey[trackData.localizationKey] = song
                self.songsByPrimaryLocKey[trackData.primaryLocKey] = song
                local localized = song.localized
                self.songsByLocalized[localized] = song
                station:AddSong(song)
            end
        end
    end
    self.init = true
    print("[Radio Manager] Loaded " .. self.numStations .. " stations and " .. self:GetNumSongs() .. " songs")
end

-- Getters
---@return Station[]
function RadioControl:GetStations() return self.stations end
---@return { [string]: Song }
function RadioControl:GetSongs() return self.songs end
---@return integer
function RadioControl:GetNumStations() return self.numStations end
---@return { [string]: Station }
function RadioControl:GetStationsByName() return self.stationsByName end
---@return { [string]: Station }
function RadioControl:GetStationsByLocKey() return self.stationsByLocKey end
---@return { [string]: Station }
function RadioControl:GetStationsByLocalized() return self.stationsByLocalized end
---@return { [string]: Song }
function RadioControl:GetSongsByLocKey() return self.songsByLocKey end
---@return { [integer]: Song }
function RadioControl:GetSongsByPrimaryLocKey() return self.songsByPrimaryLocKey end
---@return { [string]: Song }
function RadioControl:GetSongsByLocalized() return self.songsByLocalized end
---@return integer
function RadioControl:GetNumSongs()
    local count = 0
    for _, _ in pairs(self.songs) do
        count = count + 1
    end
    return count
end

--- Gets a Station object by its index (ERadioStationList), name, locKey, or localized name
--- The indices start at 0, since ERadioStationList starts at 0
---@param key integer|string|CName|ERadioStationList
---@return Station|nil
function RadioControl:GetStation(key)
    if type(key) == "number" then
        return self.stations[key]
    elseif type(key) == "string" then
        return self.stationsByName[key]
            or self.stationsByLocKey[key]
            or self.stationsByLocalized[key]
    else
        if key and key.hash_lo ~= nil then
            -- assume it's a CName
            -- try by value first
            local byValue = self.stationsByName[key.value]
                or self.stationsByLocKey[key.value]
                or self.stationsByLocalized[Game.GetLocalizedTextByKey(key)]
            if byValue ~= nil then return byValue end
            
            if key.hash_hi == 0 and key.hash_lo ~= 0 then
                -- it's probably a loc key
                return self.stationsByLocKey[key.hash_lo]
                    or self.stationsByLocalized[Game.GetLocalizedTextByKey(key)]
                    or self.stationsByName[key.value]
            end

            return nil
        end
        -- assume it's a ERadioStationList
        return self.stations[tonumber(EnumInt(key))]
    end
end

--- Gets a Song object by its trackEventName, localizationKey, primaryLocKey, or localized name
---@param key string|integer|CName
---@return Song|nil
function RadioControl:GetSong(key)
    if key.hash_lo ~= nil then
        -- assume it's a CName
        -- check loc key first
        if self.songsByPrimaryLocKey[key.hash_lo] ~= nil then
            return self.songsByPrimaryLocKey[key.hash_lo]
        end
        key = key.value
    end
    if type(key) ~= "string" then
        print("[Radio Manager] ERROR: GetSong expects a string or CName, got " .. type(key))
        return nil
    end
    return self.songs[key]
        or self.songsByLocKey[key]
        or self.songsByPrimaryLocKey[key]
        or self.songsByLocalized[Game.GetLocalizedTextByKey(key)]
end

---@param song Song
function RadioControl:PlaySong(song)
    Game.GetAudioSystem():RequestSongOnRadioStation(song:GetStation().id, song.id)
end

--- Plays a random song from the given list of songs, optionally switching to that station
---@param songs Song[]
---@param switchToStation boolean whether to switch the player's radio to the station of the song
---@param songsToExclude Song|Song[]|nil a song to exclude from selection (e.g. the currently playing song)
function RadioControl:PlayRandomSongFromList(songs, switchToStation, songsToExclude)
    if #songs == 0 then
        print("[Radio Manager] No songs available to play")
        return
    end
    if songsToExclude ~= nil then
        if type(songsToExclude) ~= "table" then
            songsToExclude = { songsToExclude }
        end
    else
        songsToExclude = {}
    end
    local n = math.random(1, #songs)
    if #songs == 1 then
        n = 1
        for _, ex in ipairs(songsToExclude) do
            if songs[n] == ex then
                print("[Radio Manager] Only one song available, but it's excluded")
                return
            end
        end
    else
        local attempts = 0
        local maxAttempts = #songs * 2
        local doLongMethod = false
        while true do
            local excluded = false
            for _, ex in ipairs(songsToExclude) do
                if songs[n] == ex then
                    excluded = true
                    break
                end
            end
            if not excluded then
                break
            end
            n = math.random(1, #songs)
            attempts = attempts + 1
            if attempts >= maxAttempts then
                print("[Radio Manager] Could not find a non-excluded song after " .. maxAttempts .. " attempts, going the long way")
                doLongMethod = true
                break
            end
        end
        if doLongMethod then
            local filtered = {}
            for _, song in ipairs(songs) do
                local excluded = false
                for _, ex in ipairs(songsToExclude) do
                    if song == ex then
                        excluded = true
                        break
                    end
                end
                if not excluded then
                    table.insert(filtered, song)
                end
            end
            if #filtered == 0 then
                print("[Radio Manager] No songs available to play after filtering")
                return
            end
            n = math.random(1, #filtered)
            songs = filtered
        end
    end
    local song = songs[n]
    if song == nil then
        print("[Radio Manager] ERROR: Song is nil")
        return
    end
    song:Play()
    if switchToStation then
        RadioControl:GetPlayerRadio():SwitchToStation(song)
    end
    return song
end

------------------------------------------------------------------------
-- PlayerRadio class methods
------------------------------------------------------------------------

--- Radio helper object. Represents the player's current radio, either car or pocket radio
---@class PlayerRadio
local PlayerRadio = {}

--- Gets the player's current station, or nil if no radio is active
---@return Station|nil
function PlayerRadio:GetCurrentStation()
    local player = Game.GetPlayer()
    if player == nil then return nil end
    local car = Game.GetMountedVehicle(player)
    if car ~= nil then
        if not car:IsRadioReceiverActive() then return nil end
        local stationLocKey = car:GetRadioReceiverStationName()
        return RadioControl:GetStation(stationLocKey)
    end
    local pr = player:GetPocketRadio()
    -- if pr.selectedStation == -1, the pocket radio is off
    -- for some reason, GetStationName() still returns a station name even when off
    if pr ~= nil and pr.selectedStation ~= -1 then
        local stationLocKey = pr:GetStationName()
        return RadioControl:GetStation(stationLocKey)
    end
    return nil
end

--- Gets the song currently playing on the player's radio, or nil if no song is playing
---@return Song|nil
function PlayerRadio:GetNowPlaying()
    local station = self:GetCurrentStation()
    if station == nil then return nil end
    return station:GetNowPlaying()
end

---@param stationOrSong Station|Song
function PlayerRadio:SwitchToStation(stationOrSong)
    if stationOrSong.GetStation ~= nil then
        -- it's a song
        stationOrSong = stationOrSong:GetStation()
    end
    local player = Game.GetPlayer()
    if player == nil then return nil end
    local car = Game.GetMountedVehicle(player)
    if car ~= nil then
        if not car:IsRadioReceiverActive() then return nil end
        car:SetRadioReceiverStation(stationOrSong.index)
        return
    end
    local pr = player:GetPocketRadio()
    if pr ~= nil then
        pr.station = stationOrSong.index
        pr.selectedStation = stationOrSong.index
        player:PSSetPocketRadioStation(stationOrSong.index)
        pr:TurnOn(false)
    end
    return
end

--- Gets the player's current radio
---@return PlayerRadio
function RadioControl:GetPlayerRadio()
    return PlayerRadio
end

------------------------------------------------------------------------
-- Song class methods
------------------------------------------------------------------------

---@param data TrackMetadata
---@param station Station
---@return Song
function Song:New(data, station)
    local localized = Game.GetLocalizedTextByKey(ToCName{hash_lo=data.primaryLocKey, hash_hi=0})
    return setmetatable({
        id = data.trackEventName,
        station = station,   -- backref to Station
        primaryLocKey = data.primaryLocKey,
        locKey = data.localizationKey,
        isStreamingFriendly = data.isStreamingFriendly,
        localized = localized
    }, self)
end

function Song:GetID() return self.id end
function Song:GetStation() return self.station end
function Song:GetPrimaryLocKey() return self.primaryLocKey end
function Song:GetLocKey() return self.locKey end
function Song:IsStreamingFriendly() return self.isStreamingFriendly end
function Song:GetLocalized() return self.localized end

--- Plays this song on its corresponding station
function Song:Play()
    RadioControl:PlaySong(self)
end

------------------------------------------------------------------------
-- Station class methods
------------------------------------------------------------------------


function Station:New(id, localized, index, speaker)
    return setmetatable({
        id = id,
        localized = localized,
        index = index, -- member of ERadioStationList
        speaker = speaker,
        tracks = {}, -- list of Song objects
    }, self)
end

function Station:GetID() return self.id end
function Station:GetLocalized() return self.localized end
function Station:GetIndex() return self.index end
function Station:GetSpeaker() return self.speaker end
function Station:GetTracks() return self.tracks end

---@param songsToExclude Song|Song[]|nil a song or list of songs to exclude from selection (e.g. the currently playing song)
function Station:SkipTrack(songsToExclude)
    local currSong = self:GetNowPlaying()
    local e = {unpack(songsToExclude or {})}
    table.insert(e, currSong)
    RadioControl:PlayRandomSongFromList(self.tracks, false, e)
end

---@return integer
function Station:GetNumTracks()
    return #self.tracks
end

--- Gets the song currently playing on this station, or nil if no song is playing
---@return Song|nil
function Station:GetNowPlaying()
    local trackCname = GetRadioStationCurrentTrackName(self.id)

    if trackCname ~= nil then
        return RadioControl:GetSong(trackCname)
    end

    return nil
end

-- Adds a song to this station's track list
function Station:AddSong(song)
    table.insert(self.tracks, song)
end

return RadioControl