/++
	One character cell on the screen grid.
+/
module vt.cell;

import vt.attrs;
import vt.color;

/// A single glyph + style on the grid.
struct Cell
{
	dchar ch = ' ';
	Color fg;
	Color bg;
	Attrs attrs;

	/// Blank cell with default colors/attrs.
	static Cell blank() @safe pure nothrow @nogc
	{
		return Cell.init;
	}

	bool opEquals(const Cell other) const @safe pure nothrow @nogc
	{
		return ch == other.ch
			&& fg == other.fg
			&& bg == other.bg
			&& attrs == other.attrs;
	}
}

unittest
{
	assert(Cell.blank().ch == ' ');
	Cell a;
	a.ch = 'X';
	a.fg = Color.ansi(1);
	assert(a != Cell.blank());
}
