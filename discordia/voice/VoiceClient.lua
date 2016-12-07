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

function VoiceClient:__init(customOptions)
	ClientBase.__init(self, customOptions, defaultOptions)
	self._connections = {}
end

local opus
function VoiceClient:loadOpus(filename)
	opus = opus or require('./opus')(filename)
	self._opus = opus
end

local sodium
function VoiceClient:loadSodium(filename)
	sodium = sodium or require('./sodium')(filename)
	self._sodium = sodium
end

function VoiceClient:joinChannel(channel, selfMute, selfDeaf)

	if not opus then return self:warning('Cannot join voice channel: libopus not loaded.') end
	if not sodium then return self:warning('Cannot join voice channel: libsodium not loaded.') end

	local guild = channel._parent
	local id = guild._id
	local connection = self._connections[id]

	if connection then
		if connection._channel == channel then return end
	else
		local encoder = opus.Encoder(SAMPLE_RATE, CHANNELS)
		encoder:set_bitrate(self._options.bitrate)
		connection = VoiceConnection(encoder, sodium.encrypt, channel, self)
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

	connection:stopStream()
	guild._connection = nil
	self._connections[id] = nil
	connection._socket:disconnect()

	return guild._parent._socket:joinVoiceChannel(id)

end

function VoiceClient:pauseStreams()
	for _, connection in pairs(self._connections) do
		if connection._stream then
			connection._stream:pause()
		end
	end
end

function VoiceClient:resumeStreams()
	for _, connection in pairs(self._connections) do
		if connection._stream then
			connection._stream:resume()
		end
	end
end

function VoiceClient:stopStreams()
	for _, connection in pairs(self._connections) do
		if connection._stream then
			connection._stream:stop()
		end
	end
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
