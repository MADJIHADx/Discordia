local Buffer = require('../utils/Buffer')
local Stopwatch = require('../utils/Stopwatch')
local constants = require('./constants')
local timer = require('timer')

local max = math.max
local sleep = timer.sleep

local running, resume, yield = coroutine.running, coroutine.resume, coroutine.yield

local SILENCE = constants.SILENCE
local PCM_SIZE = constants.PCM_SIZE
local FRAME_SIZE = constants.FRAME_SIZE
local MAX_DURATION = constants.MAX_DURATION
local FRAME_DURATION = constants.FRAME_DURATION

local AudioStream = class('AudioStream')

function AudioStream:__init(client)
	self._client = client
end

local function send(client, data)

	local header = client._header
	local nonce = client._nonce

	header:writeUInt16BE(2, client._seq)
	header:writeUInt32BE(4, client._timestamp)
	header:writeUInt32BE(8, client._ssrc)

	header:copy(nonce)

	client._seq = client._seq < 0xFFFF and client._seq + 1 or 0
	client._timestamp = client._timestamp < 0xFFFFFFFF and client._timestamp + FRAME_SIZE or 0

	local encrypted = client._sodium.encrypt(data, tostring(nonce), client._key)

	local len = #encrypted
	local packet = Buffer(12 + len)
	header:copy(packet)
	packet:writeString(12, encrypted, len)

	client._udp:send(tostring(packet), client._ip, client._port)

end

function AudioStream:_play(source, duration)

	duration = duration or MAX_DURATION

	local client = self._client

	client._voice_socket:setSpeaking(true)

	local elapsed = 0
	local clock = Stopwatch()
	local encoder = client._encoder

	self._elapsed = elapsed
	self._clock = clock
	self._stopped = false

	while elapsed < duration do
		local pcm = source()
		if not pcm or self._stopped then break end
		local data = encoder:encode(pcm, FRAME_SIZE, PCM_SIZE)
		send(client, data)
		local delay = FRAME_DURATION + (elapsed - clock.milliseconds)
		elapsed = elapsed + FRAME_DURATION
		sleep(max(0, delay))
		while self._paused do
			self._paused = running()
			send(client, SILENCE)
			clock:pause()
			yield()
			clock:resume()
		end
	end
	send(client, SILENCE)

	self._stopped = true
	client._voice_socket:setSpeaking(false)

end

function AudioStream:pause()
	self._paused = true
end

function AudioStream:resume()
	local paused = self._paused
	self._paused = false
	if type(paused) == 'thread' then
		resume(paused)
	end
end

function AudioStream:stop()
	self._stopped = true
end

return AudioStream
