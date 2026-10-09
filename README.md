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
