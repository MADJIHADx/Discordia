local AudioStream = require('./AudioStream')
local constants = require('./constants')

local PCM_SIZE = constants.PCM_SIZE

local WaveformStream = class('WaveformStream', AudioStream)

function WaveformStream:__init(generator, client)
	AudioStream.__init(self, client)
	self._generator = generator
end

function WaveformStream:play(duration)
	local generator = self._generator
	local function source()
		local pcm = {}
		for i = 0, PCM_SIZE / 2 - 1, 2 do
			local left, right = generator()
			pcm[i] = left or 0
			pcm[i + 1] = right or 0
		end
		return pcm
	end
	return self:_play(source, duration)
end

return WaveformStream
