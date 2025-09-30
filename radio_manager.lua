local RadioControl = {
    init = false,
}
-- Song class. Represents a single song/track
local Song = {}
Song.__index = Song
-- Station class. Represents a radio station with multiple songs
local Station = {}
Station.__index = Station

--TODO: handle radio_station_05_pop_completed_sq017 vs radio_station_05_pop

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

-- Initializes the RadioControl system by loading metadata from disk
function RadioControl:Init()
    if self.init then return end
    local tracksData = loadJson("data/radio_tracks.json")
    local tracksMetadata = loadJson("data/radio_tracks_metadata.json")
    if tracksData == nil or tracksMetadata == nil then
        print("[Radio Manager] ERROR: COULD NOT LOAD DATA FILES")
        return
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
function RadioControl:GetStations() return self.stations end
function RadioControl:GetSongs() return self.songs end
function RadioControl:GetNumStations() return self.numStations end
function RadioControl:GetStationsByName() return self.stationsByName end
function RadioControl:GetStationsByLocKey() return self.stationsByLocKey end
function RadioControl:GetStationsByLocalized() return self.stationsByLocalized end
function RadioControl:GetSongsByLocKey() return self.songsByLocKey end
function RadioControl:GetSongsByPrimaryLocKey() return self.songsByPrimaryLocKey end
function RadioControl:GetSongsByLocalized() return self.songsByLocalized end
function RadioControl:GetNumSongs()
    local count = 0
    for _, _ in pairs(self.songs) do
        count = count + 1
    end
    return count
end

-- Gets a Station object by its index (ERadioStationList), name, locKey, or localized name
function RadioControl:GetStation(key)
    if type(key) == "number" then
        return self.stations[key]
    elseif type(key) == "string" then
        print("Get station string: " .. key)
        return self.stationsByName[key]
            or self.stationsByLocKey[key]
            or self.stationsByLocalized[key]
    else
        print("Get station CName: " .. tostring(key))
        if key.hash_lo ~= nil then
            -- assume it's a CName
            if key.hash_hi == 0 and key.hash_lo ~= 0 then
                -- it's probably a loc key
                return self.stationsByLocKey[key.hash_lo]
                    or self.stationsByLocalized[Game.GetLocalizedTextByKey(key)]
                    or self.stationsByName[key.value]
            end
            return self.stationsByName[key.value]
                or self.stationsByLocKey[key.value]
                or self.stationsByLocalized[Game.GetLocalizedTextByKey(key)]
        end
        -- assume it's a ERadioStationList
        return self.stations[tonumber(EnumInt(key))]
    end
end

-- Gets a Song object by its trackEventName, localizationKey, primaryLocKey, or localized name
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

function RadioControl:PlaySong(song) 
    Game.GetAudioSystem():RequestSongOnRadioStation(song:GetStation().id, song.id)
end

------------------------------------------------------------------------
-- Radio class methods
------------------------------------------------------------------------

-- Radio helper object. Represents the player's current radio, either car or pocket radio
local Radio = {}

-- Gets the player's current station, or nil if no radio is active
function Radio:GetCurrentStation()
    local player = Game.GetPlayer()
    if player == nil then return nil end
    local car = Game.GetMountedVehicle(player)
    if car ~= nil then
        print("[Radio] Got car")
        if not car:IsRadioReceiverActive() then return nil end
        local stationLocKey = car:GetRadioReceiverStationName()
        print("[Radio] Car station loc key: " .. tostring(stationLocKey))
        return RadioControl:GetStation(stationLocKey)
    end
    local pr = player:GetPocketRadio()
    if pr ~= nil then
        local stationLocKey = pr:GetStationName()
        return RadioControl:GetStation(stationLocKey)
    end
    return nil
end

-- Gets the song currently playing on the player's radio, or nil if no song is playing
function Radio:GetNowPlaying()
    print("[Radio] Getting current station")
    local station = self:GetCurrentStation()
    print("[Radio] Current station: " .. (station ~= nil and station:GetLocalized() or "nil"))
    if station == nil then return nil end
    return station:GetNowPlaying()
end

function Radio:SwitchToStation(stationOrSong)
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
        player:PSSetPocketRadioStation(stationOrSong.index)
    end
    return
end

-- Gets the player's current radio
function RadioControl:GetPlayerRadio()
    return Radio
end

------------------------------------------------------------------------
-- Song class methods
------------------------------------------------------------------------

function Song:New(data, station)
    local localized = Game.GetLocalizedTextByKey(ToCName{hash_lo=data.primaryLocKey, hash_hi=0})
    return setmetatable({
        id = data.trackEventName,
        station = station,   -- backref to Station
        primaryLocKey = data.primaryLocKey,
        locKey = data.localizationKey,
        isStreamingFriendly = data.isStreamingFriendly,
        indexCname = data.indexCName,
        localized = localized
    }, self)
end

function Song:GetID() return self.id end
function Song:GetStation() return self.station end
function Song:GetPrimaryLocKey() return self.primaryLocKey end
function Song:GetLocKey() return self.locKey end
function Song:IsStreamingFriendly() return self.isStreamingFriendly end
function Song:GetIndexCname() return self.indexCname end
function Song:GetLocalized() return self.localized end

-- Plays this song on its station
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

function Station:GetNumTracks()
    return #self.tracks
end

-- Gets the song currently playing on this station, or nil if no song is playing
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