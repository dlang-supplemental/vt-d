/++
	Text attributes carried on a cell (SGR subset).
+/
module vt.attrs;

/// Boolean SGR-style attributes on a single cell.
struct Attrs
{
	bool bold;
	bool faint;
	bool italic;
	bool underline;
	bool blink;
	bool inverse;
	bool invisible;
	bool strikethrough;

	/// Reset all attributes to off.
	void reset() @safe pure nothrow @nogc
	{
		this = Attrs.init;
	}
}

unittest
{
	Attrs a;
	a.bold = true;
	a.underline = true;
	a.reset();
	assert(!a.bold && !a.underline);
}
