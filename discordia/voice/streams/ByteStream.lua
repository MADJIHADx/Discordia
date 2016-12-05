local AudioStream = require('./AudioStream')
local Buffer = require('../../utils/Buffer')
local constants = require('../constants')

local PCM_LEN = constants.PCM_LEN

local ByteStream = class('ByteStream', AudioStream)

function ByteStream:__init(bytes, client)
	AudioStream.__init(self, client)
	self._buffer = Buffer(bytes)
end

function ByteStream:play(duration)
	local buffer = self._buffer
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
	return self:_play(source, duration)
end

return ByteStream
