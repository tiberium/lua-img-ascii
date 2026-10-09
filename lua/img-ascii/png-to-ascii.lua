local M = {}

local PNG_SIGNATURE = "\137PNG\r\n\26\n"
local PNG_SIGNATURE_LENGTH = #PNG_SIGNATURE
local PNG_CHUNK_LENGTH_SIZE = 4
local PNG_CHUNK_TYPE_SIZE = 4
local PNG_CRC_SIZE = 4
local PNG_IHDR_DATA_LENGTH = 13
local PNG_BIT_DEPTH_8 = 8
local PNG_COLOR_TYPE_RGB = 2
local PNG_COLOR_TYPE_RGBA = 6
local PNG_COMPRESSION_METHOD_DEFLATE = 0
local PNG_FILTER_METHOD_ADAPTIVE = 0
local PNG_INTERLACE_NONE = 0
local PNG_FILTER_NONE = 0
local PNG_FILTER_SUB = 1
local PNG_FILTER_UP = 2
local PNG_FILTER_AVERAGE = 3
local PNG_FILTER_PAETH = 4
local FIRST_LUA_INDEX = 1
local FIRST_DEFLATE_BLOCK = 0
local FINAL_DEFLATE_BLOCK = 1
local DEFLATE_BLOCK_TYPE_STORED = 0
local DEFLATE_BLOCK_TYPE_FIXED = 1
local DEFLATE_BLOCK_TYPE_DYNAMIC = 2
local DEFLATE_MAX_BITS = 15
local DEFLATE_CODE_LENGTH_ALPHABET_SIZE = 19
local DEFLATE_LITERAL_LENGTH_MINIMUM = 257
local DEFLATE_LITERAL_LENGTH_MAXIMUM = 285
local DEFLATE_END_OF_BLOCK = 256
local DEFLATE_REPEAT_PREVIOUS_LENGTH = 16
local DEFLATE_REPEAT_ZERO_LENGTH_SHORT = 17
local DEFLATE_REPEAT_ZERO_LENGTH_LONG = 18
local DEFLATE_REPEAT_PREVIOUS_EXTRA_BITS = 2
local DEFLATE_REPEAT_ZERO_SHORT_EXTRA_BITS = 3
local DEFLATE_REPEAT_ZERO_LONG_EXTRA_BITS = 7
local DEFLATE_REPEAT_PREVIOUS_BASE = 3
local DEFLATE_REPEAT_ZERO_SHORT_BASE = 3
local DEFLATE_REPEAT_ZERO_LONG_BASE = 11
local DEFLATE_LENGTH_EXTRA_BITS = {
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	1,
	1,
	1,
	1,
	2,
	2,
	2,
	2,
	3,
	3,
	3,
	3,
	4,
	4,
	4,
	4,
	5,
	5,
	5,
	5,
	0,
}
local DEFLATE_LENGTH_BASES = {
	3,
	4,
	5,
	6,
	7,
	8,
	9,
	10,
	11,
	13,
	15,
	17,
	19,
	23,
	27,
	31,
	35,
	43,
	51,
	59,
	67,
	83,
	99,
	115,
	131,
	163,
	195,
	227,
	258,
}
local DEFLATE_DISTANCE_EXTRA_BITS = {
	0,
	0,
	0,
	0,
	1,
	1,
	2,
	2,
	3,
	3,
	4,
	4,
	5,
	5,
	6,
	6,
	7,
	7,
	8,
	8,
	9,
	9,
	10,
	10,
	11,
	11,
	12,
	12,
	13,
	13,
}
local DEFLATE_DISTANCE_BASES = {
	1,
	2,
	3,
	4,
	5,
	7,
	9,
	13,
	17,
	25,
	33,
	49,
	65,
	97,
	129,
	193,
	257,
	385,
	513,
	769,
	1025,
	1537,
	2049,
	3073,
	4097,
	6145,
	8193,
	12289,
	16385,
	24577,
}
local DEFLATE_CODE_LENGTH_ORDER = {
	16,
	17,
	18,
	0,
	8,
	7,
	9,
	6,
	10,
	5,
	11,
	4,
	12,
	3,
	13,
	2,
	14,
	1,
	15,
}
local RGB_CHANNEL_COUNT = 3
local RGBA_CHANNEL_COUNT = 4
local DEFAULT_PALETTE = " .:-=+*#%@"
local WHITE_BRIGHTNESS = 255
local ROUNDING_OFFSET = 0.5
local RED_LUMINANCE = 0.2126
local GREEN_LUMINANCE = 0.7152
local BLUE_LUMINANCE = 0.0722

local function read_uint32_big_endian(bytes, offset)
	local first = bytes:byte(offset)
	local second = bytes:byte(offset + 1)
	local third = bytes:byte(offset + 2)
	local fourth = bytes:byte(offset + 3)
	return (((first * 256 + second) * 256 + third) * 256) + fourth
end

local function reverse_bits(value, bit_count)
	local reversed = 0
	for _ = FIRST_LUA_INDEX, bit_count do
		reversed = reversed * 2 + value % 2
		value = math.floor(value / 2)
	end
	return reversed
end

local function new_bit_reader(bytes)
	return {
		bytes = bytes,
		bit_offset = 0,
	}
end

local function read_bits(reader, bit_count)
	local value = 0
	local multiplier = 1
	local byte_count = #reader.bytes

	for _ = FIRST_LUA_INDEX, bit_count do
		local byte_offset = math.floor(reader.bit_offset / 8) + FIRST_LUA_INDEX
		if byte_offset > byte_count then
			error("Unexpected end of DEFLATE stream.")
		end

		local bit_offset = reader.bit_offset % 8
		local byte = reader.bytes:byte(byte_offset)
		local bit = math.floor(byte / 2 ^ bit_offset) % 2
		value = value + bit * multiplier
		multiplier = multiplier * 2
		reader.bit_offset = reader.bit_offset + 1
	end

	return value
end

local function align_to_next_byte(reader)
	reader.bit_offset = math.ceil(reader.bit_offset / 8) * 8
end

local function huffman_tree(code_lengths)
	local counts = {}
	local next_codes = {}
	local tree = {}
	local code = 0
	local maximum_length = 0

	for _, length in ipairs(code_lengths) do
		if length > DEFLATE_MAX_BITS then
			error("Invalid DEFLATE Huffman code length.")
		end
		if length > maximum_length then
			maximum_length = length
		end
		counts[length] = (counts[length] or 0) + 1
	end

	for length = FIRST_LUA_INDEX, maximum_length do
		code = (code + (counts[length - 1] or 0)) * 2
		next_codes[length] = code
	end

	for symbol, length in ipairs(code_lengths) do
		if length > 0 then
			local reversed_code = reverse_bits(next_codes[length], length)
			tree[length] = tree[length] or {}
			tree[length][reversed_code] = symbol - FIRST_LUA_INDEX
			next_codes[length] = next_codes[length] + 1
		end
	end

	return tree, maximum_length
end

local function read_huffman_symbol(reader, tree, maximum_length)
	local code = 0
	local multiplier = 1
	for length = FIRST_LUA_INDEX, maximum_length do
		code = code + read_bits(reader, 1) * multiplier
		local symbol = tree[length] and tree[length][code]
		if symbol ~= nil then
			return symbol
		end
		multiplier = multiplier * 2
	end
	error("Invalid DEFLATE Huffman code.")
end

local function fixed_huffman_trees()
	local literal_lengths = {}
	for symbol = 0, 287 do
		if symbol <= 143 then
			literal_lengths[symbol + FIRST_LUA_INDEX] = 8
		elseif symbol <= 255 then
			literal_lengths[symbol + FIRST_LUA_INDEX] = 9
		elseif symbol <= 279 then
			literal_lengths[symbol + FIRST_LUA_INDEX] = 7
		else
			literal_lengths[symbol + FIRST_LUA_INDEX] = 8
		end
	end

	local distance_lengths = {}
	for distance = 0, 31 do
		distance_lengths[distance + FIRST_LUA_INDEX] = 5
	end

	local literal_tree, literal_maximum = huffman_tree(literal_lengths)
	local distance_tree, distance_maximum = huffman_tree(distance_lengths)
	return literal_tree, literal_maximum, distance_tree, distance_maximum
end

local function dynamic_huffman_trees(reader)
	local literal_length_count = read_bits(reader, 5) + 257
	local distance_count = read_bits(reader, 5) + 1
	local code_length_count = read_bits(reader, 4) + 4
	local code_length_lengths = {}

	for index = FIRST_LUA_INDEX, DEFLATE_CODE_LENGTH_ALPHABET_SIZE do
		code_length_lengths[index] = 0
	end
	for index = FIRST_LUA_INDEX, code_length_count do
		local symbol = DEFLATE_CODE_LENGTH_ORDER[index]
		code_length_lengths[symbol + FIRST_LUA_INDEX] = read_bits(reader, 3)
	end

	local code_length_tree, code_length_maximum = huffman_tree(code_length_lengths)
	local all_lengths = {}
	local required_length_count = literal_length_count + distance_count
	while #all_lengths < required_length_count do
		local symbol = read_huffman_symbol(reader, code_length_tree, code_length_maximum)
		if symbol <= DEFLATE_MAX_BITS then
			table.insert(all_lengths, symbol)
		else
			local repeat_count
			local value
			if symbol == DEFLATE_REPEAT_PREVIOUS_LENGTH then
				if #all_lengths == 0 then
					error("DEFLATE stream repeats a missing code length.")
				end
				repeat_count = read_bits(reader, DEFLATE_REPEAT_PREVIOUS_EXTRA_BITS) + DEFLATE_REPEAT_PREVIOUS_BASE
				value = all_lengths[#all_lengths]
			elseif symbol == DEFLATE_REPEAT_ZERO_LENGTH_SHORT then
				repeat_count = read_bits(reader, DEFLATE_REPEAT_ZERO_SHORT_EXTRA_BITS) + DEFLATE_REPEAT_ZERO_SHORT_BASE
				value = 0
			elseif symbol == DEFLATE_REPEAT_ZERO_LENGTH_LONG then
				repeat_count = read_bits(reader, DEFLATE_REPEAT_ZERO_LONG_EXTRA_BITS) + DEFLATE_REPEAT_ZERO_LONG_BASE
				value = 0
			else
				error("Invalid DEFLATE code-length symbol.")
			end

			if #all_lengths + repeat_count > required_length_count then
				error("DEFLATE code lengths exceed their declared size.")
			end
			for _ = FIRST_LUA_INDEX, repeat_count do
				table.insert(all_lengths, value)
			end
		end
	end

	local literal_lengths = {}
	local distance_lengths = {}
	for index = FIRST_LUA_INDEX, literal_length_count do
		literal_lengths[index] = all_lengths[index]
	end
	for index = FIRST_LUA_INDEX, distance_count do
		distance_lengths[index] = all_lengths[literal_length_count + index]
	end

	local literal_tree, literal_maximum = huffman_tree(literal_lengths)
	local distance_tree, distance_maximum = huffman_tree(distance_lengths)
	return literal_tree, literal_maximum, distance_tree, distance_maximum
end

local function inflate_huffman_block(reader, output, literal_tree, literal_maximum, distance_tree, distance_maximum)
	while true do
		local symbol = read_huffman_symbol(reader, literal_tree, literal_maximum)
		if symbol < DEFLATE_END_OF_BLOCK then
			table.insert(output, symbol)
		elseif symbol == DEFLATE_END_OF_BLOCK then
			return
		elseif symbol >= DEFLATE_LITERAL_LENGTH_MINIMUM and symbol <= DEFLATE_LITERAL_LENGTH_MAXIMUM then
			local length_index = symbol - DEFLATE_LITERAL_LENGTH_MINIMUM + FIRST_LUA_INDEX
			local length = DEFLATE_LENGTH_BASES[length_index]
				+ read_bits(reader, DEFLATE_LENGTH_EXTRA_BITS[length_index])
			local distance_symbol = read_huffman_symbol(reader, distance_tree, distance_maximum)
			local distance_index = distance_symbol + FIRST_LUA_INDEX
			local distance = DEFLATE_DISTANCE_BASES[distance_index]
				+ read_bits(reader, DEFLATE_DISTANCE_EXTRA_BITS[distance_index])

			if distance > #output then
				error("DEFLATE distance points before the output.")
			end
			for _ = FIRST_LUA_INDEX, length do
				table.insert(output, output[#output - distance + FIRST_LUA_INDEX])
			end
		else
			error("Invalid DEFLATE literal/length symbol.")
		end
	end
end

local function inflate_zlib(zlib_data)
	if #zlib_data < 6 then
		error("PNG IDAT data is too short for a zlib stream.")
	end

	local compression_method_and_flags = zlib_data:byte(FIRST_LUA_INDEX)
	local flags = zlib_data:byte(FIRST_LUA_INDEX + 1)
	if compression_method_and_flags % 16 ~= 8 or (compression_method_and_flags * 256 + flags) % 31 ~= 0 then
		error("PNG IDAT data does not contain a valid zlib stream.")
	end
	if math.floor(flags / 32) % 2 == 1 then
		error("PNG IDAT data uses an unsupported zlib preset dictionary.")
	end

	local deflate_start = FIRST_LUA_INDEX + 2
	local adler32_size = 4
	local deflate_end = #zlib_data - adler32_size
	local reader = new_bit_reader(zlib_data:sub(deflate_start, deflate_end))
	local output = {}
	local is_final_block = FIRST_DEFLATE_BLOCK

	while is_final_block ~= FINAL_DEFLATE_BLOCK do
		is_final_block = read_bits(reader, 1)
		local block_type = read_bits(reader, 2)
		if block_type == DEFLATE_BLOCK_TYPE_STORED then
			align_to_next_byte(reader)
			local length = read_bits(reader, 16)
			local inverse_length = read_bits(reader, 16)
			if length + inverse_length ~= 65535 then
				error("Invalid DEFLATE stored-block length.")
			end
			for _ = FIRST_LUA_INDEX, length do
				table.insert(output, read_bits(reader, 8))
			end
		elseif block_type == DEFLATE_BLOCK_TYPE_FIXED then
			local literal_tree, literal_maximum, distance_tree, distance_maximum = fixed_huffman_trees()
			inflate_huffman_block(reader, output, literal_tree, literal_maximum, distance_tree, distance_maximum)
		elseif block_type == DEFLATE_BLOCK_TYPE_DYNAMIC then
			local literal_tree, literal_maximum, distance_tree, distance_maximum = dynamic_huffman_trees(reader)
			inflate_huffman_block(reader, output, literal_tree, literal_maximum, distance_tree, distance_maximum)
		else
			error("PNG IDAT data uses a reserved DEFLATE block type.")
		end
	end

	local output_characters = {}
	for _, byte in ipairs(output) do
		table.insert(output_characters, string.char(byte))
	end
	return table.concat(output_characters)
end

local function paeth_predictor(left, up, upper_left)
	local prediction = left + up - upper_left
	local left_distance = math.abs(prediction - left)
	local up_distance = math.abs(prediction - up)
	local upper_left_distance = math.abs(prediction - upper_left)

	if left_distance <= up_distance and left_distance <= upper_left_distance then
		return left
	end
	if up_distance <= upper_left_distance then
		return up
	end
	return upper_left
end

local function unfilter_scanlines(data, width, height, bytes_per_pixel)
	local stride = width * bytes_per_pixel
	local scanline_size = stride + 1
	local expected_size = height * scanline_size
	if #data ~= expected_size then
		error("PNG decompressed data has an unexpected size.")
	end

	local pixels = {}
	local previous_scanline = {}
	for y = 0, height - 1 do
		local row_offset = y * scanline_size
		local filter_type = data:byte(row_offset + FIRST_LUA_INDEX)
		local scanline = {}
		if filter_type < PNG_FILTER_NONE or filter_type > PNG_FILTER_PAETH then
			error("PNG uses an unsupported scanline filter.")
		end

		for x = FIRST_LUA_INDEX, stride do
			local filtered = data:byte(row_offset + 1 + x)
			local left = x > bytes_per_pixel and scanline[x - bytes_per_pixel] or 0
			local up = previous_scanline[x] or 0
			local upper_left = x > bytes_per_pixel and previous_scanline[x - bytes_per_pixel] or 0
			local value

			if filter_type == PNG_FILTER_NONE then
				value = filtered
			elseif filter_type == PNG_FILTER_SUB then
				value = (filtered + left) % 256
			elseif filter_type == PNG_FILTER_UP then
				value = (filtered + up) % 256
			elseif filter_type == PNG_FILTER_AVERAGE then
				value = (filtered + math.floor((left + up) / 2)) % 256
			else
				value = (filtered + paeth_predictor(left, up, upper_left)) % 256
			end
			scanline[x] = value
			table.insert(pixels, value)
		end
		previous_scanline = scanline
	end

	return pixels
end

---@param png string
---@return { width: number, height: number, channels: number, pixels: number[] }
function M.decode(png)
	if type(png) ~= "string" then
		error("PNG data must be a string.")
	end
	if png:sub(FIRST_LUA_INDEX, PNG_SIGNATURE_LENGTH) ~= PNG_SIGNATURE then
		error("Input is not a PNG file.")
	end

	local offset = PNG_SIGNATURE_LENGTH + FIRST_LUA_INDEX
	local width
	local height
	local channels
	local idat_parts = {}
	while offset <= #png do
		if offset + PNG_CHUNK_LENGTH_SIZE + PNG_CHUNK_TYPE_SIZE + PNG_CRC_SIZE - FIRST_LUA_INDEX > #png then
			error("PNG contains a truncated chunk.")
		end
		local chunk_length = read_uint32_big_endian(png, offset)
		local chunk_type_offset = offset + PNG_CHUNK_LENGTH_SIZE
		local chunk_data_offset = chunk_type_offset + PNG_CHUNK_TYPE_SIZE
		local chunk_end = chunk_data_offset + chunk_length + PNG_CRC_SIZE - FIRST_LUA_INDEX
		if chunk_end > #png then
			error("PNG contains a truncated chunk.")
		end

		local chunk_type = png:sub(chunk_type_offset, chunk_type_offset + PNG_CHUNK_TYPE_SIZE - FIRST_LUA_INDEX)
		local chunk_data = png:sub(chunk_data_offset, chunk_data_offset + chunk_length - FIRST_LUA_INDEX)
		if chunk_type == "IHDR" then
			if width then
				error("PNG contains more than one IHDR chunk.")
			end
			if chunk_length ~= PNG_IHDR_DATA_LENGTH then
				error("PNG IHDR chunk has an invalid length.")
			end
			width = read_uint32_big_endian(chunk_data, FIRST_LUA_INDEX)
			height = read_uint32_big_endian(chunk_data, 5)
			local bit_depth = chunk_data:byte(9)
			local color_type = chunk_data:byte(10)
			local compression_method = chunk_data:byte(11)
			local filter_method = chunk_data:byte(12)
			local interlace_method = chunk_data:byte(13)

			if width == 0 or height == 0 then
				error("PNG dimensions must be positive.")
			end
			if bit_depth ~= PNG_BIT_DEPTH_8 then
				error("Only 8-bit PNG images are supported.")
			end
			if color_type == PNG_COLOR_TYPE_RGB then
				channels = RGB_CHANNEL_COUNT
			elseif color_type == PNG_COLOR_TYPE_RGBA then
				channels = RGBA_CHANNEL_COUNT
			else
				error("Only RGB and RGBA PNG images are supported.")
			end
			if
				compression_method ~= PNG_COMPRESSION_METHOD_DEFLATE
				or filter_method ~= PNG_FILTER_METHOD_ADAPTIVE
				or interlace_method ~= PNG_INTERLACE_NONE
			then
				error("PNG uses an unsupported encoding.")
			end
		elseif chunk_type == "IDAT" then
			table.insert(idat_parts, chunk_data)
		elseif chunk_type == "IEND" then
			break
		end

		offset = chunk_end + FIRST_LUA_INDEX
	end

	if not width then
		error("PNG is missing its IHDR chunk.")
	end
	if #idat_parts == 0 then
		error("PNG is missing its IDAT data.")
	end

	return {
		width = width,
		height = height,
		channels = channels,
		pixels = unfilter_scanlines(inflate_zlib(table.concat(idat_parts)), width, height, channels),
	}
end

---@param image { width: number, height: number, channels: number, pixels: number[] }
---@param output_width number
---@param output_height number
---@param palette string|nil
---@return string[]
function M.render(image, output_width, output_height, palette)
	if type(image) ~= "table" or type(image.pixels) ~= "table" then
		error("Image must be the result of png-to-ascii.decode.")
	end
	if type(output_width) ~= "number" or output_width <= 0 or output_width % 1 ~= 0 then
		error("Output width must be a positive integer.")
	end
	if type(output_height) ~= "number" or output_height <= 0 or output_height % 1 ~= 0 then
		error("Output height must be a positive integer.")
	end
	palette = palette or DEFAULT_PALETTE
	if type(palette) ~= "string" or #palette < 2 then
		error("ASCII palette must contain at least two characters.")
	end

	local lines = {}
	local palette_maximum_index = #palette - FIRST_LUA_INDEX
	for output_y = 0, output_height - FIRST_LUA_INDEX do
		local source_y = math.min(image.height - FIRST_LUA_INDEX, math.floor(output_y * image.height / output_height))
		local characters = {}
		for output_x = 0, output_width - FIRST_LUA_INDEX do
			local source_x = math.min(image.width - FIRST_LUA_INDEX, math.floor(output_x * image.width / output_width))
			local pixel_offset = (source_y * image.width + source_x) * image.channels
			local red = image.pixels[pixel_offset + FIRST_LUA_INDEX]
			local green = image.pixels[pixel_offset + 2]
			local blue = image.pixels[pixel_offset + 3]
			local alpha = image.channels == RGBA_CHANNEL_COUNT and image.pixels[pixel_offset + 4] or WHITE_BRIGHTNESS
			local color_brightness = red * RED_LUMINANCE + green * GREEN_LUMINANCE + blue * BLUE_LUMINANCE
			local brightness = color_brightness * alpha / WHITE_BRIGHTNESS
				+ WHITE_BRIGHTNESS * (WHITE_BRIGHTNESS - alpha) / WHITE_BRIGHTNESS
			local palette_index = math.floor(brightness / WHITE_BRIGHTNESS * palette_maximum_index + ROUNDING_OFFSET)
				+ FIRST_LUA_INDEX
			table.insert(characters, palette:sub(palette_index, palette_index))
		end
		table.insert(lines, table.concat(characters))
	end

	return lines
end

---@param png string
---@param output_width number
---@param output_height number
---@param palette string|nil
---@return string[]
function M.to_ascii(png, output_width, output_height, palette)
	return M.render(M.decode(png), output_width, output_height, palette)
end

return M
