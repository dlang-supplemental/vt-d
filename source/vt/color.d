/++
	Foreground / background color models used by cells and SGR.
+/
module vt.color;

/// How a color value is encoded.
enum ColorKind : ubyte
{
	/// Terminal default (often theme fg/bg).
	default_,
	/// Indexed 0-255 (ANSI 16 / 256-color).
	indexed,
	/// 24-bit RGB.
	rgb,
}

/// A cell or SGR color.
struct Color
{
	ColorKind kind = ColorKind.default_;
	ubyte index; /// Valid when kind == indexed (0-255).
	ubyte r; /// Valid when kind == rgb.
	ubyte g;
	ubyte b;

	/// Terminal default color.
	static Color defaultColor() @safe pure nothrow @nogc
	{
		return Color.init;
	}

	/// Indexed ANSI / 256-color palette entry.
	static Color ansi(ubyte index) @safe pure nothrow @nogc
	{
		Color c;
		c.kind = ColorKind.indexed;
		c.index = index;
		return c;
	}

	/// Truecolor RGB.
	static Color rgbColor(ubyte r, ubyte g, ubyte b) @safe pure nothrow @nogc
	{
		Color c;
		c.kind = ColorKind.rgb;
		c.r = r;
		c.g = g;
		c.b = b;
		return c;
	}

	bool opEquals(const Color other) const @safe pure nothrow @nogc
	{
		if (kind != other.kind)
			return false;
		final switch (kind)
		{
		case ColorKind.default_:
			return true;
		case ColorKind.indexed:
			return index == other.index;
		case ColorKind.rgb:
			return r == other.r && g == other.g && b == other.b;
		}
	}
}

unittest
{
	assert(Color.defaultColor().kind == ColorKind.default_);
	assert(Color.ansi(1) == Color.ansi(1));
	assert(Color.ansi(1) != Color.ansi(2));
	assert(Color.rgbColor(1, 2, 3) == Color.rgbColor(1, 2, 3));
}
