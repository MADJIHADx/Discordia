local AudioStream = require('./AudioStream')
local constants = require('../constants')

local PCM_LEN = constants.PCM_LEN

local PCMStream = class('PCMStream', AudioStream)

function PCMStream:__init(pcm, client)
	AudioStream.__init(self, client)
	self._pcm = pcm
end

function PCMStream:play(duration)
	local pcm = self._pcm
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
	return self:_play(source, duration)
end

return PCMStream
