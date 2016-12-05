local Buffer = require('../utils/Buffer')
local ClientBase = require('../utils/ClientBase')
local PCMStream = require('./PCMStream')
local FFmpegStream = require('./FFmpegStream')
local WaveformStream = require('./WaveformStream')
local VoiceSocket = require('./VoiceSocket')
local constants = require('./constants')
local waveforms = require('./waveforms')

local CHANNELS = constants.CHANNELS
local FRAME_SIZE = constants.FRAME_SIZE
local SAMPLE_RATE = constants.SAMPLE_RATE
local SAMPLE_PERIOD = constants.SAMPLE_PERIOD
local MAX_INT16 = constants.MAX_INT16
local TAU = constants.TAU

local clamp = math.clamp
local format = string.format
local open = io.open

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
	if type(opus) == 'function' or type(sodium) == 'function' then
		return self:error('Cannot initialize a VoiceClient before loading voice libraries.')
	end
	self._encoder = opus.Encoder(SAMPLE_RATE, CHANNELS)
	self._encoder:set_bitrate(self._options.bitrate)
	self._voice_socket = VoiceSocket(self)
	self._seq = 0
	self._timestamp = 0
	local header = Buffer(12)
	local nonce = Buffer(24)
	header[0] = 0x80
	header[1] = 0x78
	self._header = header
	self._nonce = nonce
end

function VoiceClient:_prepare(udp, ip, port, ssrc)
	self._udp, self._ip, self._port, self._ssrc = udp, ip, port, ssrc
end

function VoiceClient:joinChannel(channel, selfMute, selfDeaf)
	local current = self._channel
	local id = channel._parent._id
	if current and current._parent._id ~= id then
		self:disconnect() -- guild switch
	end
	self._channel = channel
	local client = channel.client
	client._voice_sockets[id] = self._voice_socket
	return client._socket:joinVoiceChannel(id, channel._id, selfMute, selfDeaf)
end

function VoiceClient:disconnect()
	local channel = self._channel
	if not channel then return end
	self:stop()
	self._channel = nil
	local client = channel.client
	local id = channel._parent._id
	client._voice_sockets[id] = nil
	client._socket:joinVoiceChannel(id)
	self._voice_socket:disconnect()
end

function VoiceClient:getBitrate()
	return self._encoder:get_bitrate()
end

function VoiceClient:setBitrate(bitrate)
	return self._encoder:set_bitrate(clamp(bitrate, 8000, 128000))
end

function VoiceClient:_send(data)

	local header = self._header
	local nonce = self._nonce

	header:writeUInt16BE(2, self._seq)
	header:writeUInt32BE(4, self._timestamp)
	header:writeUInt32BE(8, self._ssrc)

	header:copy(nonce)

	self._seq = self._seq < 0xFFFF and self._seq + 1 or 0
	self._timestamp = self._timestamp < 0xFFFFFFFF and self._timestamp + FRAME_SIZE or 0

	local encrypted = self._sodium.encrypt(data, tostring(nonce), self._key)

	local len = #encrypted
	local packet = Buffer(12 + len)
	header:copy(packet)
	packet:writeString(12, encrypted, len)

	self._udp:send(tostring(packet), self._ip, self._port)

end

function VoiceClient:createFFmpegStream(filename)

	if not self._ffmpeg then
		return self:warning(format('Cannot open %q. FFmpeg not loaded.'))
	end

	local file = open(filename)
	if not file then
		return self:warning(format('Cannot open %q. File not found.', filename))
	end
	file:close()

	return FFmpegStream(filename, self)

end

function VoiceClient:createRawGenerator(bytes, offset, len) -- luacheck: ignore self
	local buffer = Buffer(bytes)
	offset = offset or 0
	local limit = #buffer - offset
	len = len and clamp(len, 0, limit) or limit
	return function()
		if offset >= len then return end
		local left = buffer:readInt16LE(offset)
		local right = buffer:readInt16LE(offset + 2)
		offset = offset + 4
		return left, right
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

function VoiceClient:createWaveformStream(generator)
	return WaveformStream(generator, self)
end

function VoiceClient:createPCMStream(pcm)
	return PCMStream(pcm, self)
end

return VoiceClient
