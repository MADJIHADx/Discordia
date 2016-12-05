local CHANNELS = 2
local SAMPLE_RATE = 48000
local FRAME_DURATION = 20 -- ms
local FRAME_SIZE = SAMPLE_RATE * FRAME_DURATION / 1000

return {
	CHANNELS = CHANNELS,
	SAMPLE_RATE = SAMPLE_RATE,
	SAMPLE_PERIOD = 1 / SAMPLE_RATE,
	MAX_DURATION = math.huge,
	FRAME_DURATION = FRAME_DURATION,
	FRAME_SIZE = FRAME_SIZE,
	PCM_SIZE = FRAME_SIZE * CHANNELS * 2,
	SILENCE = '\xF8\xFF\xFE',
	TAU = 2 * math.pi,
	MAX_INT16 = 32767,
}
