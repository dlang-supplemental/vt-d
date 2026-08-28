/++
	Character-cell grid, cursor, scroll region, and optional scrollback.
+/
module vt.screen;

import vt.attrs;
import vt.cell;
import vt.color;

/// Visible screen buffer plus optional scrollback history.
final class Screen
{
	private Cell[] _cells; // row-major, cols * rows
	private int _cols;
	private int _rows;
	private size_t _scrollbackLimit;
	private Cell[][] _scrollback; // oldest first
	private int _scrollTop; // inclusive, 0-based
	private int _scrollBottom; // inclusive, 0-based

	int cursorCol; /// 0-based column
	int cursorRow; /// 0-based row
	bool cursorVisible = true;
	string title;
	Attrs penAttrs;
	Color penFg;
	Color penBg;
	bool originMode; /// DECOM: origin is scroll-region top-left
	bool autoWrap = true; /// DECAWM
	bool insertMode; /// IRM

	this(int cols, int rows, size_t scrollbackLimit = 1000)
	{
		assert(cols > 0 && rows > 0);
		_cols = cols;
		_rows = rows;
		_scrollbackLimit = scrollbackLimit;
		_cells = new Cell[](cols * rows);
		_scrollTop = 0;
		_scrollBottom = rows - 1;
		clear();
	}

	@property int cols() const @safe pure nothrow @nogc { return _cols; }
	@property int rows() const @safe pure nothrow @nogc { return _rows; }
	@property size_t scrollbackLimit() const @safe pure nothrow @nogc { return _scrollbackLimit; }
	@property size_t scrollbackLines() const @safe pure nothrow @nogc { return _scrollback.length; }
	@property int scrollTop() const @safe pure nothrow @nogc { return _scrollTop; }
	@property int scrollBottom() const @safe pure nothrow @nogc { return _scrollBottom; }

	/// Access a visible cell (bounds-checked).
	ref Cell at(int col, int row) @safe pure
	{
		assert(col >= 0 && col < _cols);
		assert(row >= 0 && row < _rows);
		return _cells[row * _cols + col];
	}

	const(Cell) at(int col, int row) const @safe pure
	{
		assert(col >= 0 && col < _cols);
		assert(row >= 0 && row < _rows);
		return _cells[row * _cols + col];
	}

	/// Snapshot of one scrollback line (may be shorter than cols historically; padded).
	const(Cell)[] scrollbackAt(size_t index) const @safe pure
	{
		assert(index < _scrollback.length);
		return _scrollback[index];
	}

	/// Resize the visible grid. Contents preserved where they overlap; cursor clamped.
	void resize(int cols, int rows)
	{
		assert(cols > 0 && rows > 0);
		auto next = new Cell[](cols * rows);
		immutable copyCols = cols < _cols ? cols : _cols;
		immutable copyRows = rows < _rows ? rows : _rows;
		foreach (r; 0 .. copyRows)
			foreach (c; 0 .. copyCols)
				next[r * cols + c] = _cells[r * _cols + c];
		_cells = next;
		_cols = cols;
		_rows = rows;
		if (_scrollBottom >= _rows)
			_scrollBottom = _rows - 1;
		if (_scrollTop > _scrollBottom)
			_scrollTop = 0;
		clampCursor();
	}

	/// Clear all visible cells and reset pen/cursor (keeps scrollback).
	void clear()
	{
		foreach (ref cell; _cells)
			cell = Cell.blank();
		cursorCol = 0;
		cursorRow = 0;
		penAttrs.reset();
		penFg = Color.defaultColor();
		penBg = Color.defaultColor();
		_scrollTop = 0;
		_scrollBottom = _rows - 1;
		originMode = false;
		autoWrap = true;
		insertMode = false;
		cursorVisible = true;
	}

	/// Hard reset: clear + drop scrollback + title.
	void hardReset()
	{
		_scrollback.length = 0;
		title = null;
		clear();
	}

	void setScrollRegion(int top, int bottom)
	{
		if (top < 0)
			top = 0;
		if (bottom >= _rows)
			bottom = _rows - 1;
		if (top > bottom)
		{
			top = 0;
			bottom = _rows - 1;
		}
		_scrollTop = top;
		_scrollBottom = bottom;
		if (originMode)
		{
			cursorCol = 0;
			cursorRow = _scrollTop;
		}
		else
			clampCursor();
	}

	void clampCursor()
	{
		if (cursorCol < 0)
			cursorCol = 0;
		if (cursorCol >= _cols)
			cursorCol = _cols - 1;
		immutable top = originMode ? _scrollTop : 0;
		immutable bottom = originMode ? _scrollBottom : _rows - 1;
		if (cursorRow < top)
			cursorRow = top;
		if (cursorRow > bottom)
			cursorRow = bottom;
	}

	/// Put a character at the cursor using the current pen, advancing the cursor.
	void putChar(dchar ch)
	{
		if (cursorCol >= _cols)
		{
			if (!autoWrap)
			{
				cursorCol = _cols - 1;
			}
			else
			{
				cursorCol = 0;
				lineFeed();
			}
		}

		if (insertMode)
			insertCells(1);

		at(cursorCol, cursorRow) = Cell(ch, penFg, penBg, penAttrs);
		cursorCol++;
	}

	void backspace()
	{
		if (cursorCol > 0)
			cursorCol--;
	}

	void carriageReturn()
	{
		cursorCol = 0;
	}

	void lineFeed()
	{
		if (cursorRow == _scrollBottom)
			scrollUp(1);
		else if (cursorRow < _rows - 1)
			cursorRow++;
	}

	void reverseIndex()
	{
		if (cursorRow == _scrollTop)
			scrollDown(1);
		else if (cursorRow > 0)
			cursorRow--;
	}

	void nextLine()
	{
		carriageReturn();
		lineFeed();
	}

	void tab()
	{
		// Simple every-8 columns tab stop.
		immutable next = ((cursorCol / 8) + 1) * 8;
		cursorCol = next < _cols ? next : _cols - 1;
	}

	void scrollUp(int n)
	{
		if (n <= 0)
			return;
		foreach (_; 0 .. n)
		{
			pushScrollbackRow(_scrollTop);
			for (int r = _scrollTop; r < _scrollBottom; r++)
				foreach (c; 0 .. _cols)
					at(c, r) = at(c, r + 1);
			clearRow(_scrollBottom);
		}
	}

	void scrollDown(int n)
	{
		if (n <= 0)
			return;
		foreach (_; 0 .. n)
		{
			for (int r = _scrollBottom; r > _scrollTop; r--)
				foreach (c; 0 .. _cols)
					at(c, r) = at(c, r - 1);
			clearRow(_scrollTop);
		}
	}

	void eraseInDisplay(int mode)
	{
		final switch (mode)
		{
		case 0: // cursor to end
			eraseInLine(0);
			foreach (r; cursorRow + 1 .. _rows)
				clearRow(r);
			break;
		case 1: // start to cursor
			foreach (r; 0 .. cursorRow)
				clearRow(r);
			eraseInLine(1);
			break;
		case 2: // entire screen
		case 3: // entire screen + scrollback (xterm)
			foreach (r; 0 .. _rows)
				clearRow(r);
			if (mode == 3)
				_scrollback.length = 0;
			break;
		}
	}

	void eraseInLine(int mode)
	{
		final switch (mode)
		{
		case 0:
			foreach (c; cursorCol .. _cols)
				at(c, cursorRow) = Cell.blank();
			break;
		case 1:
			foreach (c; 0 .. cursorCol + 1)
				at(c, cursorRow) = Cell.blank();
			break;
		case 2:
			clearRow(cursorRow);
			break;
		}
	}

	void insertLines(int n)
	{
		if (n <= 0 || cursorRow < _scrollTop || cursorRow > _scrollBottom)
			return;
		foreach (_; 0 .. n)
		{
			for (int r = _scrollBottom; r > cursorRow; r--)
				foreach (c; 0 .. _cols)
					at(c, r) = at(c, r - 1);
			clearRow(cursorRow);
		}
	}

	void deleteLines(int n)
	{
		if (n <= 0 || cursorRow < _scrollTop || cursorRow > _scrollBottom)
			return;
		foreach (_; 0 .. n)
		{
			for (int r = cursorRow; r < _scrollBottom; r++)
				foreach (c; 0 .. _cols)
					at(c, r) = at(c, r + 1);
			clearRow(_scrollBottom);
		}
	}

	void insertCells(int n)
	{
		if (n <= 0)
			return;
		if (n > _cols - cursorCol)
			n = _cols - cursorCol;
		for (int c = _cols - 1; c >= cursorCol + n; c--)
			at(c, cursorRow) = at(c - n, cursorRow);
		foreach (c; cursorCol .. cursorCol + n)
			at(c, cursorRow) = Cell.blank();
	}

	void deleteCells(int n)
	{
		if (n <= 0)
			return;
		if (n > _cols - cursorCol)
			n = _cols - cursorCol;
		for (int c = cursorCol; c < _cols - n; c++)
			at(c, cursorRow) = at(c + n, cursorRow);
		foreach (c; _cols - n .. _cols)
			at(c, cursorRow) = Cell.blank();
	}

	void eraseChars(int n)
	{
		if (n <= 0)
			return;
		immutable end = cursorCol + n;
		foreach (c; cursorCol .. (end < _cols ? end : _cols))
			at(c, cursorRow) = Cell.blank();
	}

	/// Render visible rows as plain text (trailing spaces and blank rows stripped).
	string dumpText() const
	{
		import std.array : appender;
		auto lines = new string[](_rows);
		foreach (r; 0 .. _rows)
		{
			int end = _cols;
			while (end > 0 && at(end - 1, r).ch == ' ')
				end--;
			import std.array : appender;
			auto line = appender!string();
			foreach (c; 0 .. end)
				line.put(at(c, r).ch);
			lines[r] = line.data;
		}
		int last = cast(int)_rows - 1;
		while (last >= 0 && lines[last].length == 0)
			last--;
		if (last < 0)
			return "";
		auto app = appender!string();
		foreach (r; 0 .. last + 1)
		{
			app.put(lines[r]);
			if (r < last)
				app.put('\n');
		}
		return app.data;
	}

	private void clearRow(int row)
	{
		foreach (c; 0 .. _cols)
			at(c, row) = Cell.blank();
	}

	private void pushScrollbackRow(int row)
	{
		if (_scrollbackLimit == 0)
			return;
		auto line = new Cell[](_cols);
		foreach (c; 0 .. _cols)
			line[c] = at(c, row);
		_scrollback ~= line;
		while (_scrollback.length > _scrollbackLimit)
			_scrollback = _scrollback[1 .. $];
	}
}

unittest
{
	auto s = new Screen(4, 2, 10);
	s.putChar('A');
	s.putChar('B');
	assert(s.at(0, 0).ch == 'A');
	assert(s.at(1, 0).ch == 'B');
	assert(s.cursorCol == 2);
	s.carriageReturn();
	s.lineFeed();
	s.putChar('C');
	assert(s.at(0, 1).ch == 'C');
	s.lineFeed(); // scroll
	assert(s.scrollbackLines == 1);
	assert(s.scrollbackAt(0)[0].ch == 'A');
	assert(s.dumpText() == "C");
}
