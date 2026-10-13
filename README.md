⚠️ This library was vibe coded. ⚠️

# lua-img-ascii

Decode PNG and JPEG image bytes and render them as ASCII art in pure Lua.

`lua-img-ascii` is a library, not a CLI. It has no runtime dependencies on
Neovim, LuaRocks, external image tools, or system converters.

## Supported formats

- Non-interlaced 8-bit RGB and RGBA PNG.
- 8-bit baseline sequential grayscale and RGB JPEG.

Progressive JPEG, interlaced PNG, palette PNG, and other image formats are not
currently supported.

## How decoding works

`decode()` identifies the format from its file signature, then sends the image
bytes to the PNG or JPEG decoder. Both decoders return pixels in row-major
order, with every pixel represented as RGB or RGBA byte values in the range
`0..255`.

### PNG

The PNG decoder reads the chunk stream, extracts image metadata from `IHDR`,
and joins the compressed `IDAT` chunks. It supports an 8-bit depth and RGB
(three-channel) or RGBA (four-channel) colour data without interlacing.

`IDAT` data is a zlib stream containing DEFLATE-compressed scanlines. The
implementation:

1. Validates the zlib header and decompresses stored, fixed-Huffman, and
   dynamic-Huffman DEFLATE blocks.
2. Builds canonical Huffman decoding tables from the fixed definitions or the
   dynamic code-length alphabet.
3. Reconstructs repeated byte sequences from DEFLATE length/distance pairs.
4. Reverses the per-scanline PNG filters: None, Sub, Up, Average, and Paeth.

The final step is necessary because PNG stores each row as a difference from
neighbouring pixels to make the image compress more effectively. The Paeth
filter uses the standard Paeth predictor to choose the closest of the left,
above, and upper-left bytes.

### JPEG

The JPEG decoder supports 8-bit **baseline sequential** JPEG images with one
(grayscale) or three components. It reads the JPEG marker segments and uses
the tables embedded in the image:

1. `DQT` quantization tables, which restore the scale of frequency
   coefficients.
2. `DHT` canonical Huffman tables, which decode the compressed DC and AC
   coefficients.
3. `SOF0` frame metadata, which supplies image dimensions and component
   sampling factors.
4. `SOS` scan metadata, which selects the Huffman tables for each component.

For every 8 x 8 block, the decoder Huffman-decodes the differential DC value
and run-length-coded AC values, maps them from JPEG zig-zag order back to
their natural positions, then dequantizes them. It applies the two-dimensional
inverse discrete cosine transform (IDCT), recentres the samples around 128,
and clamps them to `0..255`.

For colour JPEGs, the decoded Y, Cb, and Cr samples are converted to RGB using
the standard YCbCr-to-RGB equations. Components with smaller sampling factors
are upsampled by nearest-neighbour selection. Restart markers reset the DC
predictors at the configured restart interval.

### Rendering ASCII

`render()` scales by nearest-neighbour sampling: each output character selects
the corresponding source pixel. It converts RGB to perceived brightness using
the Rec. 709 luminance weights:

```text
brightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
```

RGBA pixels are first composited over white, so a fully transparent pixel
renders as the brightest palette character. The resulting brightness selects a
character from the supplied palette, or the default `" .:-=+*#%@"`, from
darkest to brightest.

## Installation

Install it with your Lua package manager, or place its `lua/` directory on
`package.path`.

With LuaRocks:

```sh
luarocks make
```

## Usage

```lua
local image_to_ascii = require("img-ascii")

local file = assert(io.open("avatar.jpg", "rb"))
local image_bytes = file:read("*a")
file:close()
local lines = image_to_ascii.to_ascii(image_bytes, 32, 16)

print(table.concat(lines, "\n"))
```

For separate decode and render stages:

```lua
local image_to_ascii = require("img-ascii")

local image = image_to_ascii.decode(image_bytes)
local lines = image_to_ascii.render(image, 32, 16, " .:-=+*#%@")
```

`decode()` returns:

```lua
{
  width = 128,
  height = 128,
  channels = 3,
  pixels = { red, green, blue, ... },
}
```

`render()` samples the decoded image into the requested character dimensions.
For RGBA PNG input, transparent pixels are composited on white.
The default palette is available as `image_to_ascii.default_palette` when you
need to reuse or extend it.

## Development

Run the Busted specs:

```sh
busted spec
```

Optionally validate style and lint:

```sh
stylua --check lua spec
luacheck lua spec
```

## License

[MIT](LICENSE)
