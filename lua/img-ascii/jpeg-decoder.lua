local M = {}

local JPEG_START_OF_IMAGE = 0xD8
local JPEG_END_OF_IMAGE = 0xD9
local JPEG_START_OF_FRAME_BASELINE = 0xC0
local JPEG_DEFINE_HUFFMAN_TABLE = 0xC4
local JPEG_DEFINE_QUANTIZATION_TABLE = 0xDB
local JPEG_START_OF_SCAN = 0xDA
local JPEG_RESTART_INTERVAL = 0xDD
local JPEG_RESTART_MARKER_MINIMUM = 0xD0
local JPEG_RESTART_MARKER_MAXIMUM = 0xD7
local JPEG_MARKER_PREFIX = 0xFF
local JPEG_BYTE_STUFFING = 0x00
local JPEG_8_BIT_PRECISION = 8
local JPEG_BASELINE_SPECTRAL_START = 0
local JPEG_BASELINE_SPECTRAL_END = 63
local JPEG_SUCCESSIVE_APPROXIMATION = 0
local JPEG_DC_TABLE_CLASS = 0
local JPEG_AC_TABLE_CLASS = 1
local JPEG_QUANTIZATION_8_BIT = 0
local JPEG_BLOCK_SIZE = 8
local JPEG_COEFFICIENT_COUNT = 64
local JPEG_FIRST_LUA_INDEX = 1
local JPEG_CENTER_VALUE = 128
local JPEG_MAXIMUM_VALUE = 255
local JPEG_COMPONENT_GRAYSCALE = 1
local JPEG_COMPONENT_RGB = 3
local JPEG_16_BIT_SEGMENT_LENGTH = 2
local JPEG_COMPONENT_HEADER_SIZE = 3
local JPEG_DQT_TABLE_INFORMATION_SIZE = 1
local JPEG_DQT_8_BIT_TABLE_SIZE = 64
local JPEG_DHT_TABLE_INFORMATION_SIZE = 1
local JPEG_DHT_CODE_LENGTH_COUNT = 16
local JPEG_PI = math.pi
local JPEG_IDCT_SCALE = 0.25
local JPEG_CHROMA_RED = 1.402
local JPEG_CHROMA_GREEN_CB = 0.344136
local JPEG_CHROMA_GREEN_CR = 0.714136
local JPEG_CHROMA_BLUE = 1.772

local ZIGZAG = {
	1,
	2,
	9,
	17,
	10,
	3,
	4,
	11,
	18,
	25,
	33,
	26,
	19,
	12,
	5,
	6,
	13,
	20,
	27,
	34,
	41,
	49,
	42,
	35,
	28,
	21,
	14,
	7,
	8,
	15,
	22,
	29,
	36,
	43,
	50,
	57,
	58,
	51,
	44,
	37,
	30,
	23,
	16,
	24,
	31,
	38,
	45,
	52,
	59,
	60,
	53,
	46,
	39,
	32,
	40,
	47,
	54,
	61,
	62,
	55,
	48,
	56,
	63,
	64,
}

local function read_uint16(data, offset)
	return data:byte(offset) * 256 + data:byte(offset + 1)
end

local function clamp(value)
	return math.max(0, math.min(JPEG_MAXIMUM_VALUE, math.floor(value + 0.5)))
end

local function new_bit_reader(data, offset)
	return { data = data, offset = offset, current_byte = nil, bit_index = JPEG_8_BIT_PRECISION }
end

local function read_bit(reader)
	if reader.bit_index == JPEG_8_BIT_PRECISION then
		local byte = reader.data:byte(reader.offset)
		if not byte then
			error("Unexpected end of JPEG scan data.")
		end
		reader.offset = reader.offset + 1
		if byte == JPEG_MARKER_PREFIX then
			local next_byte = reader.data:byte(reader.offset)
			while next_byte == JPEG_MARKER_PREFIX do
				reader.offset = reader.offset + 1
				next_byte = reader.data:byte(reader.offset)
			end
			if next_byte == JPEG_BYTE_STUFFING then
				reader.offset = reader.offset + 1
			elseif
				next_byte
				and next_byte >= JPEG_RESTART_MARKER_MINIMUM
				and next_byte <= JPEG_RESTART_MARKER_MAXIMUM
			then
				reader.offset = reader.offset + 1
			else
				error("Unexpected JPEG marker in scan data.")
			end
		end
		reader.current_byte = byte
		reader.bit_index = 0
	end

	local bit = math.floor(reader.current_byte / 2 ^ (JPEG_8_BIT_PRECISION - JPEG_FIRST_LUA_INDEX - reader.bit_index))
		% 2
	reader.bit_index = reader.bit_index + 1
	return bit
end

local function read_bits(reader, count)
	local value = 0
	for _ = JPEG_FIRST_LUA_INDEX, count do
		value = value * 2 + read_bit(reader)
	end
	return value
end

local function receive_extend(reader, length)
	if length == 0 then
		return 0
	end
	local value = read_bits(reader, length)
	local threshold = 2 ^ (length - 1)
	return value < threshold and value - (2 ^ length - 1) or value
end

local function read_huffman(reader, table)
	local code = 0
	for length = JPEG_FIRST_LUA_INDEX, JPEG_DHT_CODE_LENGTH_COUNT do
		code = code * 2 + read_bit(reader)
		local symbol = table[length] and table[length][code]
		if symbol then
			return symbol
		end
	end
	error("Invalid JPEG Huffman code.")
end

local function idct_block(coefficients)
	local output = {}
	for y = 0, JPEG_BLOCK_SIZE - 1 do
		for x = 0, JPEG_BLOCK_SIZE - 1 do
			local value = 0
			for v = 0, JPEG_BLOCK_SIZE - 1 do
				local vertical_scale = v == 0 and 1 / math.sqrt(2) or 1
				local vertical_cosine = math.cos((2 * y + 1) * v * JPEG_PI / (2 * JPEG_BLOCK_SIZE))
				for u = 0, JPEG_BLOCK_SIZE - 1 do
					local horizontal_scale = u == 0 and 1 / math.sqrt(2) or 1
					local horizontal_cosine = math.cos((2 * x + 1) * u * JPEG_PI / (2 * JPEG_BLOCK_SIZE))
					value = value
						+ horizontal_scale
							* vertical_scale
							* coefficients[v * JPEG_BLOCK_SIZE + u + JPEG_FIRST_LUA_INDEX]
							* horizontal_cosine
							* vertical_cosine
				end
			end
			output[y * JPEG_BLOCK_SIZE + x + JPEG_FIRST_LUA_INDEX] = clamp(value * JPEG_IDCT_SCALE + JPEG_CENTER_VALUE)
		end
	end
	return output
end

local function decode_block(reader, component, dc_table, ac_table)
	local coefficients = {}
	for index = JPEG_FIRST_LUA_INDEX, JPEG_COEFFICIENT_COUNT do
		coefficients[index] = 0
	end

	local dc_length = read_huffman(reader, dc_table)
	component.dc = component.dc + receive_extend(reader, dc_length)
	coefficients[JPEG_FIRST_LUA_INDEX] = component.dc * component.quantization[JPEG_FIRST_LUA_INDEX]

	local coefficient_index = 1
	while coefficient_index < JPEG_COEFFICIENT_COUNT do
		local symbol = read_huffman(reader, ac_table)
		local run = math.floor(symbol / 16)
		local length = symbol % 16
		if length == 0 then
			if run ~= 0 then
				coefficient_index = coefficient_index + 16
			else
				break
			end
		else
			coefficient_index = coefficient_index + run + 1
			if coefficient_index > JPEG_COEFFICIENT_COUNT then
				error("JPEG AC coefficient exceeds its block.")
			end
			local natural_index = ZIGZAG[coefficient_index]
			coefficients[natural_index] = receive_extend(reader, length) * component.quantization[natural_index]
		end
	end

	return idct_block(coefficients)
end

local function parse_huffman_table(data, offset, length, tables)
	local end_offset = offset + length
	while offset < end_offset do
		local information = data:byte(offset)
		offset = offset + JPEG_DHT_TABLE_INFORMATION_SIZE
		local table_class = math.floor(information / 16)
		local table_id = information % 16
		if table_class ~= JPEG_DC_TABLE_CLASS and table_class ~= JPEG_AC_TABLE_CLASS then
			error("JPEG has an invalid Huffman table class.")
		end

		local counts = {}
		local symbol_count = 0
		for index = JPEG_FIRST_LUA_INDEX, JPEG_DHT_CODE_LENGTH_COUNT do
			counts[index] = data:byte(offset + index - JPEG_FIRST_LUA_INDEX)
			symbol_count = symbol_count + counts[index]
		end
		offset = offset + JPEG_DHT_CODE_LENGTH_COUNT

		local huffman = {}
		local code = 0
		for code_length = JPEG_FIRST_LUA_INDEX, JPEG_DHT_CODE_LENGTH_COUNT do
			huffman[code_length] = {}
			for _ = JPEG_FIRST_LUA_INDEX, counts[code_length] do
				huffman[code_length][code] = data:byte(offset)
				offset = offset + 1
				code = code + 1
			end
			code = code * 2
		end
		if offset > end_offset + 1 then
			error("JPEG Huffman table exceeds its segment.")
		end
		tables[table_class][table_id] = huffman
	end
end

local function write_block(component, block, x_offset, y_offset)
	for y = 0, JPEG_BLOCK_SIZE - 1 do
		local destination_y = y_offset + y
		if destination_y < component.height then
			for x = 0, JPEG_BLOCK_SIZE - 1 do
				local destination_x = x_offset + x
				if destination_x < component.width then
					component.samples[destination_y * component.width + destination_x + JPEG_FIRST_LUA_INDEX] =
						block[y * JPEG_BLOCK_SIZE + x + JPEG_FIRST_LUA_INDEX]
				end
			end
		end
	end
end

---@param jpeg string
---@return { width: number, height: number, channels: number, pixels: number[] }
function M.decode(jpeg)
	if type(jpeg) ~= "string" or jpeg:byte(1) ~= JPEG_MARKER_PREFIX or jpeg:byte(2) ~= JPEG_START_OF_IMAGE then
		error("Input is not a JPEG file.")
	end

	local offset = 3
	local quantization_tables = {}
	local huffman_tables = { [JPEG_DC_TABLE_CLASS] = {}, [JPEG_AC_TABLE_CLASS] = {} }
	local components = {}
	local components_by_id = {}
	local width
	local height
	local maximum_horizontal_sampling
	local maximum_vertical_sampling
	local restart_interval = 0

	while offset <= #jpeg do
		while jpeg:byte(offset) == JPEG_MARKER_PREFIX do
			offset = offset + 1
		end
		local marker = jpeg:byte(offset)
		offset = offset + 1
		if marker == JPEG_END_OF_IMAGE then
			break
		elseif marker < JPEG_RESTART_MARKER_MINIMUM or marker > JPEG_RESTART_MARKER_MAXIMUM then
			local segment_length = read_uint16(jpeg, offset)
			local segment_offset = offset + JPEG_16_BIT_SEGMENT_LENGTH
			local segment_data_length = segment_length - JPEG_16_BIT_SEGMENT_LENGTH
			offset = segment_offset + segment_data_length

			if marker == JPEG_DEFINE_QUANTIZATION_TABLE then
				local table_offset = segment_offset
				while table_offset < offset do
					local information = jpeg:byte(table_offset)
					table_offset = table_offset + JPEG_DQT_TABLE_INFORMATION_SIZE
					if math.floor(information / 16) ~= JPEG_QUANTIZATION_8_BIT then
						error("Only 8-bit JPEG quantization tables are supported.")
					end
					local table_id = information % 16
					local table = {}
					for index = JPEG_FIRST_LUA_INDEX, JPEG_DQT_8_BIT_TABLE_SIZE do
						table[ZIGZAG[index]] = jpeg:byte(table_offset + index - JPEG_FIRST_LUA_INDEX)
					end
					table_offset = table_offset + JPEG_DQT_8_BIT_TABLE_SIZE
					quantization_tables[table_id] = table
				end
			elseif marker == JPEG_START_OF_FRAME_BASELINE then
				if jpeg:byte(segment_offset) ~= JPEG_8_BIT_PRECISION then
					error("Only 8-bit JPEG precision is supported.")
				end
				height = read_uint16(jpeg, segment_offset + 1)
				width = read_uint16(jpeg, segment_offset + 3)
				local component_count = jpeg:byte(segment_offset + 5)
				if component_count ~= JPEG_COMPONENT_GRAYSCALE and component_count ~= JPEG_COMPONENT_RGB then
					error("Only grayscale and three-component JPEG images are supported.")
				end
				maximum_horizontal_sampling = 0
				maximum_vertical_sampling = 0
				for index = JPEG_FIRST_LUA_INDEX, component_count do
					local component_offset = segment_offset
						+ 6
						+ (index - JPEG_FIRST_LUA_INDEX) * JPEG_COMPONENT_HEADER_SIZE
					local sampling = jpeg:byte(component_offset + 1)
					local component = {
						id = jpeg:byte(component_offset),
						h = math.floor(sampling / 16),
						v = sampling % 16,
						quantization_id = jpeg:byte(component_offset + 2),
						dc = 0,
					}
					maximum_horizontal_sampling = math.max(maximum_horizontal_sampling, component.h)
					maximum_vertical_sampling = math.max(maximum_vertical_sampling, component.v)
					table.insert(components, component)
					components_by_id[component.id] = component
				end
			elseif marker == JPEG_DEFINE_HUFFMAN_TABLE then
				parse_huffman_table(jpeg, segment_offset, segment_data_length, huffman_tables)
			elseif marker == JPEG_RESTART_INTERVAL then
				restart_interval = read_uint16(jpeg, segment_offset)
			elseif marker == JPEG_START_OF_SCAN then
				if not width then
					error("JPEG scan appears before its frame.")
				end
				local scan_component_count = jpeg:byte(segment_offset)
				local scan_components = {}
				for index = JPEG_FIRST_LUA_INDEX, scan_component_count do
					local component_offset = segment_offset + 1 + (index - JPEG_FIRST_LUA_INDEX) * 2
					local component = components_by_id[jpeg:byte(component_offset)]
					if not component then
						error("JPEG scan references an unknown component.")
					end
					local table_selectors = jpeg:byte(component_offset + 1)
					component.dc_table_id = math.floor(table_selectors / 16)
					component.ac_table_id = table_selectors % 16
					table.insert(scan_components, component)
				end
				local spectral_offset = segment_offset + 1 + scan_component_count * 2
				if
					jpeg:byte(spectral_offset) ~= JPEG_BASELINE_SPECTRAL_START
					or jpeg:byte(spectral_offset + 1) ~= JPEG_BASELINE_SPECTRAL_END
					or jpeg:byte(spectral_offset + 2) ~= JPEG_SUCCESSIVE_APPROXIMATION
				then
					error("Only baseline sequential JPEG scans are supported.")
				end

				for _, component in ipairs(components) do
					component.quantization = quantization_tables[component.quantization_id]
					if not component.quantization then
						error("JPEG component is missing its quantization table.")
					end
					component.width = math.ceil(width * component.h / maximum_horizontal_sampling)
					component.height = math.ceil(height * component.v / maximum_vertical_sampling)
					component.samples = {}
				end

				local reader = new_bit_reader(jpeg, offset)
				local mcu_width = JPEG_BLOCK_SIZE * maximum_horizontal_sampling
				local mcu_height = JPEG_BLOCK_SIZE * maximum_vertical_sampling
				local mcu_columns = math.ceil(width / mcu_width)
				local mcu_rows = math.ceil(height / mcu_height)
				local mcu_index = 0
				for mcu_y = 0, mcu_rows - 1 do
					for mcu_x = 0, mcu_columns - 1 do
						if restart_interval > 0 and mcu_index > 0 and mcu_index % restart_interval == 0 then
							reader.bit_index = JPEG_8_BIT_PRECISION
							for _, component in ipairs(scan_components) do
								component.dc = 0
							end
						end
						for _, component in ipairs(scan_components) do
							local dc_table = huffman_tables[JPEG_DC_TABLE_CLASS][component.dc_table_id]
							local ac_table = huffman_tables[JPEG_AC_TABLE_CLASS][component.ac_table_id]
							if not dc_table or not ac_table then
								error("JPEG scan is missing a Huffman table.")
							end
							for block_y = 0, component.v - 1 do
								for block_x = 0, component.h - 1 do
									local block = decode_block(reader, component, dc_table, ac_table)
									write_block(
										component,
										block,
										(mcu_x * component.h + block_x) * JPEG_BLOCK_SIZE,
										(mcu_y * component.v + block_y) * JPEG_BLOCK_SIZE
									)
								end
							end
						end
						mcu_index = mcu_index + 1
					end
				end
				offset = reader.offset
			end
		end
	end

	if not width then
		error("JPEG is missing a baseline frame.")
	end

	local pixels = {}
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local samples = {}
			for index, component in ipairs(components) do
				local sample_x = math.floor(x * component.h / maximum_horizontal_sampling)
				local sample_y = math.floor(y * component.v / maximum_vertical_sampling)
				samples[index] = component.samples[sample_y * component.width + sample_x + JPEG_FIRST_LUA_INDEX]
			end
			if #components == JPEG_COMPONENT_GRAYSCALE then
				table.insert(pixels, samples[1])
				table.insert(pixels, samples[1])
				table.insert(pixels, samples[1])
			else
				local luminance = samples[1]
				local blue_chroma = samples[2] - JPEG_CENTER_VALUE
				local red_chroma = samples[3] - JPEG_CENTER_VALUE
				table.insert(pixels, clamp(luminance + JPEG_CHROMA_RED * red_chroma))
				table.insert(
					pixels,
					clamp(luminance - JPEG_CHROMA_GREEN_CB * blue_chroma - JPEG_CHROMA_GREEN_CR * red_chroma)
				)
				table.insert(pixels, clamp(luminance + JPEG_CHROMA_BLUE * blue_chroma))
			end
		end
	end

	return { width = width, height = height, channels = JPEG_COMPONENT_RGB, pixels = pixels }
end

return M
