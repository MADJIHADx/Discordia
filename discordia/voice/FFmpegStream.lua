local AudioStream = require('./AudioStream')
local constants = require('./constants')

local PCM_SIZE = constants.PCM_SIZE

local popen = io.popen
local format, unpack, rep = string.format, string.unpack, string.rep

local function shorts(str)
    local len = #str / 2
    return {unpack(rep('<H', len), str)}
end

local FFmpegStream = class('FFmpegStream', AudioStream)

function FFmpegStream:__init(filename, client)
	AudioStream.__init(self, client)
	self._filename = filename
end

function FFmpegStream:play(duration)

	local ffmpeg = self._client._ffmpeg
	local pipe = popen(format('%s -y -i %s -ar 48000 -ac 2 -f s16le pipe:1 -loglevel fatal', ffmpeg, self._filename))

	local function source()
		local success, pcm = pcall(pipe.read, pipe, PCM_SIZE)
		return success and pcm and shorts(pcm)
	end

	self:_play(source, duration)
	pcall(pipe.close, pipe)

end

return FFmpegStream
