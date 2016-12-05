local Buffer = require('../utils/Buffer')
local ClientBase = require('../utils/ClientBase')
local FFmpegStream = require('./FFmpegStream')
local WaveformStream = require('./WaveformStream')
local VoiceSocket = require('./VoiceSocket')
local constants = require('./constants')

local CHANNELS = constants.CHANNELS
local SAMPLE_RATE = constants.SAMPLE_RATE

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

function VoiceClient:createFFmpegStream(filename)

	if not self._ffmpeg then
		return self:warning(format('Cannot play %q. FFmpeg not loaded.'))
	end

	if not self._voice_socket._connected then
		return self:warning(format('Cannot play %q. Voice connection not found.', filename))
	end

	local file = open(filename)
	if not file then
		return self:warning(format('Cannot play %q. File not found.', filename))
	end

	return FFmpegStream(filename, self)

end

function VoiceClient:createWaveformStream(generator)
	return WaveformStream(generator, self)
end

return VoiceClient
