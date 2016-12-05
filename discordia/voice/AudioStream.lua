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

function AudioStream:_play(source, duration)

	local client = self._client

	if not client._voice_socket._connected then
		return client:warning('Cannot play stream. Voice connection not found.')
	end

	duration = duration or MAX_DURATION

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
		client:_send(data)
		local delay = FRAME_DURATION + (elapsed - clock.milliseconds)
		elapsed = elapsed + FRAME_DURATION
		sleep(max(0, delay))
		while self._paused do
			self._paused = running()
			client:_send(SILENCE)
			clock:pause()
			yield()
			clock:resume()
		end
	end
	client:_send(SILENCE)

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
