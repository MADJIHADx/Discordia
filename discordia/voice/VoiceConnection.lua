local VoiceSocket = require('./VoiceSocket')
local AudioStream = require('./AudioStream')
local Buffer = require('../utils/Buffer')
local constants = require('./constants')

local PCM_LEN = constants.PCM_LEN
local PCM_SIZE = constants.PCM_SIZE
local FRAME_SIZE = constants.FRAME_SIZE

local clamp = math.clamp
local format, unpack, rep = string.format, string.unpack, string.rep
local open, popen = io.open, io.popen

local function shorts(str)
    return {unpack(rep('<H', #str / 2), str)}
end

local VoiceConnection = class('VoiceConnection')

function VoiceConnection:__init(encoder, channel, client)
	self._client = client
	self._channel = channel
	self._socket = VoiceSocket(self)
	self._encoder = encoder
	self._seq = 0
	self._timestamp = 0
	local header = Buffer(12)
	local nonce = Buffer(24)
	header[0] = 0x80
	header[1] = 0x78
	self._header = header
	self._nonce = nonce
end

function VoiceConnection:_prepare(udp, ip, port, ssrc)
	self._udp, self._ip, self._port, self._ssrc = udp, ip, port, ssrc
end

function VoiceConnection:_send(data)

	local header = self._header
	local nonce = self._nonce

	header:writeUInt16BE(2, self._seq)
	header:writeUInt32BE(4, self._timestamp)
	header:writeUInt32BE(8, self._ssrc)

	header:copy(nonce)

	self._seq = self._seq < 0xFFFF and self._seq + 1 or 0
	self._timestamp = self._timestamp < 0xFFFFFFFF and self._timestamp + FRAME_SIZE or 0

	local encrypted = self._client._sodium.encrypt(data, tostring(nonce), self._key)

	local len = #encrypted
	local packet = Buffer(12 + len)
	header:copy(packet)
	packet:writeString(12, encrypted, len)

	self._udp:send(tostring(packet), self._ip, self._port)

end

function VoiceConnection:getBitrate()
	return self._encoder:get_bitrate()
end

function VoiceConnection:setBitrate(bitrate)
	return self._encoder:set_bitrate(clamp(bitrate, 8000, 128000))
end

local function play(self, source, duration)
	if self._stream then self._stream:stop() end
	return AudioStream(source, self):play(duration)
end

function VoiceConnection:playFile(filename, duration)

	local client = self._client
	local ffmpeg = client._ffmpeg

	if not ffmpeg then
		return client:warning(format('Cannot open %q. FFmpeg not loaded.'))
	end

	local file = open(filename)
	if not file then
		return client:warning(format('Cannot open %q. File not found.', filename))
	end
	file:close()

	local pipe = popen(format('%s -y -i %q -ar 48000 -ac 2 -f s16le pipe:1 -loglevel warning', ffmpeg, filename))

	local function source()
		local success, bytes = pcall(pipe.read, pipe, PCM_SIZE)
		return success and bytes and shorts(bytes)
	end

	play(self, source, duration)
	pcall(pipe.close, pipe)

end

function VoiceConnection:playBytes(bytes, duration)
	local buffer = Buffer(bytes)
	local offset = 0
	local len = #buffer
	local function source()
		if offset >= len then return end
		local pcm = {}
		for i = 0, PCM_LEN - 1, 2 do
			pcm[i] = buffer:readInt16LE(offset)
			pcm[i + 1] = buffer:readInt16LE(offset + 2)
			offset = offset + 4
			if offset >= len then break end
		end
		return pcm
	end
	return play(self, source, duration)
end

function VoiceConnection:playPCM(pcm, duration)
	local len = #pcm
	local offset = 1
	local function source()
		if offset > len then return end
		local slice = {}
		for i = 1, PCM_LEN do
			slice[i] = pcm[offset]
			offset = offset + 1
		end
		return slice
	end
	return play(self, source, duration)
end

function VoiceConnection:playWaveform(generator, duration)
	local function source()
		local pcm = {}
		for i = 0, PCM_LEN - 1, 2 do
			local left, right = generator()
			if not left and not right then return end
			pcm[i] = left or 0
			pcm[i + 1] = right or 0
		end
		return pcm
	end
	return play(self, source, duration)
end

function VoiceConnection:pause()
	if not self._stream then return end
	return self._stream:pause()
end

function VoiceConnection:resume()
	if not self._stream then return end
	return self._stream:resume()
end

function VoiceConnection:stop()
	if not self._stream then return end
	return self._stream:stop()
end

return VoiceConnection
