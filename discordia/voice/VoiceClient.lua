local ClientBase = require('../utils/ClientBase')
local VoiceConnection = require('./VoiceConnection')
local constants = require('./constants')
local waveforms = require('./waveforms')

local CHANNELS = constants.CHANNELS
local SAMPLE_RATE = constants.SAMPLE_RATE
local SAMPLE_PERIOD = constants.SAMPLE_PERIOD
local MAX_INT16 = constants.MAX_INT16
local TAU = constants.TAU

local defaultOptions = {
	dateTime = '%c',
	bitrate = 64000,
}

local VoiceClient = class('VoiceClient', ClientBase)

local opus = require('./opus')
function VoiceClient._loadOpus(filename)
	opus = opus(filename)
	VoiceClient._opus = opus
end

local sodium = require('./sodium')
function VoiceClient._loadSodium(filename)
	sodium = sodium(filename)
	VoiceClient._sodium = sodium
end

function VoiceClient._loadFFmpeg(filename)
	VoiceClient._ffmpeg = filename
end

function VoiceClient:__init(customOptions)
	ClientBase.__init(self, customOptions, defaultOptions)
	if not VoiceClient._opus or not VoiceClient._sodium then
		return self:error('Cannot initialize a VoiceClient before loading voice libraries.')
	end
	self._connections = {}
end

function VoiceClient:joinChannel(channel, selfMute, selfDeaf)

	local guild = channel._parent
	local id = guild._id
	local connection = self._connections[id]

	if connection then
		if connection._channel == channel then return end
	else
		local encoder = opus.Encoder(SAMPLE_RATE, CHANNELS)
		encoder:set_bitrate(self._options.bitrate)
		connection = VoiceConnection(encoder, channel, self)
		guild._connection = connection
		self._connections[id] = connection
	end

	return guild._parent._socket:joinVoiceChannel(id, channel._id, selfMute, selfDeaf)

end

function VoiceClient:leaveChannel(channel)

	local guild = channel._parent
	local id = guild._id
	local connection = self._connections[id]

	if not connection then return end

	connection:stop()
	guild._connection = nil
	self._connections[id] = nil
	connection._socket:disconnect()

	return guild._parent._socket:joinVoiceChannel(id)

end

function VoiceClient:createMonoToneGenerator(name, freq, amplitude) -- luacheck: ignore self
	local h = TAU * freq / SAMPLE_RATE
	local a = (amplitude or 1) * MAX_INT16
	return waveforms[name](h, a)
end

function VoiceClient:createPolyToneGenerator(args) -- luacheck: ignore self
	local n = 1 / #args
	for i, v in ipairs(args) do
		local h = TAU * v[2] * SAMPLE_PERIOD
		local a = (v[3] or n) * MAX_INT16
		args[i] = waveforms[v[1]](h, a)
	end
	return function()
		local s = 0
		for _, waveform in ipairs(args) do
			s = s + waveform()
		end
		return s, s
	end
end

return VoiceClient
