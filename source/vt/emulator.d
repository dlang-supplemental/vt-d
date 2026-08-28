/++
	Byte-stream VT/ANSI parser that mutates a Screen.

	v0.1 coverage: CSI cursor/erase/scroll/SGR, common ESC intermediates,
	OSC 0/2 title, UTF-8 printable text, C0 controls.
+/
module vt.emulator;

import std.conv : to;
import std.utf : decode, UTFException;

import vt.attrs;
import vt.cell;
import vt.color;
import vt.screen;

/// Feed bytes into a Screen.
final class Emulator
{
	Screen screen;

	private enum State
	{
		ground,
		escape,
		csiEntry,
		csiParam,
		oscString,
		utf8Collect,
	}

	private State _state = State.ground;
	private ubyte[] _utf8buf;
	private int _utf8need;
	private int[] _params;
	private bool _csiPrivate; // '?' after CSI
	private char[] _osc;
	private int _savedCol;
	private int _savedRow;
	private Attrs _savedAttrs;
	private Color _savedFg;
	private Color _savedBg;

	this(int cols, int rows, size_t scrollbackLimit = 1000)
	{
		screen = new Screen(cols, rows, scrollbackLimit);
	}

	this(Screen screen)
	{
		assert(screen !is null);
		this.screen = screen;
	}

	/// Reset parser + screen (hard).
	void reset()
	{
		_state = State.ground;
		_utf8buf.length = 0;
		_utf8need = 0;
		_params.length = 0;
		_csiPrivate = false;
		_osc.length = 0;
		screen.hardReset();
	}

	/// Feed raw bytes (may be incomplete UTF-8 / escape sequences).
	void feed(const(ubyte)[] data)
	{
		foreach (b; data)
			feedByte(b);
	}

	/// Feed a string as UTF-8 bytes.
	void feed(const(char)[] text)
	{
		feed(cast(const(ubyte)[]) text);
	}

	private void feedByte(ubyte b)
	{
		final switch (_state)
		{
		case State.ground:
			handleGround(b);
			break;
		case State.escape:
			handleEscape(b);
			break;
		case State.csiEntry:
		case State.csiParam:
			handleCsi(b);
			break;
		case State.oscString:
			handleOsc(b);
			break;
		case State.utf8Collect:
			handleUtf8(b);
			break;
		}
	}

	private void handleGround(ubyte b)
	{
		if (b == 0x1B)
		{
			_state = State.escape;
			return;
		}
		if (b < 0x20)
		{
			handleC0(b);
			return;
		}
		if (b == 0x7F) // DEL
			return;

		if (b < 0x80)
		{
			screen.putChar(cast(dchar) b);
			return;
		}

		// UTF-8 lead
		if ((b & 0xE0) == 0xC0)
		{
			_utf8need = 2;
			_utf8buf = [b];
			_state = State.utf8Collect;
		}
		else if ((b & 0xF0) == 0xE0)
		{
			_utf8need = 3;
			_utf8buf = [b];
			_state = State.utf8Collect;
		}
		else if ((b & 0xF8) == 0xF0)
		{
			_utf8need = 4;
			_utf8buf = [b];
			_state = State.utf8Collect;
		}
		// else ignore invalid lead
	}

	private void handleUtf8(ubyte b)
	{
		if ((b & 0xC0) != 0x80)
		{
			// invalid continuation — resync
			_state = State.ground;
			_utf8buf.length = 0;
			handleGround(b);
			return;
		}
		_utf8buf ~= b;
		if (_utf8buf.length == _utf8need)
		{
			try
			{
				size_t idx = 0;
				immutable ch = decode(cast(char[]) _utf8buf, idx);
				screen.putChar(ch);
			}
			catch (UTFException)
			{
				// drop
			}
			_utf8buf.length = 0;
			_utf8need = 0;
			_state = State.ground;
		}
	}

	private void handleC0(ubyte b)
	{
		switch (b)
		{
		case 0x07: // BEL — ignored at ground (OSC uses ST/BEL)
			break;
		case 0x08: // BS
			screen.backspace();
			break;
		case 0x09: // HT
			screen.tab();
			break;
		case 0x0A: // LF
		case 0x0B: // VT
		case 0x0C: // FF
			screen.lineFeed();
			break;
		case 0x0D: // CR
			screen.carriageReturn();
			break;
		default:
			break;
		}
	}

	private void handleEscape(ubyte b)
	{
		switch (b)
		{
		case '[':
			_params.length = 0;
			_csiPrivate = false;
			_state = State.csiEntry;
			return;
		case ']':
			_osc.length = 0;
			_state = State.oscString;
			return;
		case 'c': // RIS
			reset();
			return;
		case '7': // DECSC
			_savedCol = screen.cursorCol;
			_savedRow = screen.cursorRow;
			_savedAttrs = screen.penAttrs;
			_savedFg = screen.penFg;
			_savedBg = screen.penBg;
			_state = State.ground;
			return;
		case '8': // DECRC
			screen.cursorCol = _savedCol;
			screen.cursorRow = _savedRow;
			screen.penAttrs = _savedAttrs;
			screen.penFg = _savedFg;
			screen.penBg = _savedBg;
			screen.clampCursor();
			_state = State.ground;
			return;
		case 'D': // IND
			screen.lineFeed();
			_state = State.ground;
			return;
		case 'E': // NEL
			screen.nextLine();
			_state = State.ground;
			return;
		case 'M': // RI
			screen.reverseIndex();
			_state = State.ground;
			return;
		default:
			_state = State.ground;
			return;
		}
	}

	private void handleCsi(ubyte b)
	{
		if (_state == State.csiEntry && b == '?')
		{
			_csiPrivate = true;
			_state = State.csiParam;
			return;
		}

		if (b >= '0' && b <= '9')
		{
			if (_params.length == 0)
				_params ~= 0;
			_params[$ - 1] = _params[$ - 1] * 10 + (b - '0');
			_state = State.csiParam;
			return;
		}
		if (b == ';')
		{
			_params ~= 0;
			_state = State.csiParam;
			return;
		}

		// Final byte
		dispatchCsi(cast(char) b);
		_state = State.ground;
		_params.length = 0;
		_csiPrivate = false;
	}

	private int param(size_t i, int defaultValue) const
	{
		if (i >= _params.length)
			return defaultValue;
		return _params[i] == 0 ? defaultValue : _params[i];
	}

	private void dispatchCsi(char finalByte)
	{
		if (_csiPrivate)
		{
			dispatchPrivateCsi(finalByte);
			return;
		}

		switch (finalByte)
		{
		case 'A': // CUU
			screen.cursorRow -= param(0, 1);
			screen.clampCursor();
			break;
		case 'B': // CUD
			screen.cursorRow += param(0, 1);
			screen.clampCursor();
			break;
		case 'C': // CUF
			screen.cursorCol += param(0, 1);
			screen.clampCursor();
			break;
		case 'D': // CUB
			screen.cursorCol -= param(0, 1);
			screen.clampCursor();
			break;
		case 'E': // CNL
			screen.cursorRow += param(0, 1);
			screen.cursorCol = 0;
			screen.clampCursor();
			break;
		case 'F': // CPL
			screen.cursorRow -= param(0, 1);
			screen.cursorCol = 0;
			screen.clampCursor();
			break;
		case 'G': // CHA
			screen.cursorCol = param(0, 1) - 1;
			screen.clampCursor();
			break;
		case 'H': // CUP
		case 'f': // HVP
			{
				immutable row = param(0, 1) - 1;
				immutable col = param(1, 1) - 1;
				if (screen.originMode)
					screen.cursorRow = screen.scrollTop + row;
				else
					screen.cursorRow = row;
				screen.cursorCol = col;
				screen.clampCursor();
			}
			break;
		case 'J': // ED
			screen.eraseInDisplay(param(0, 0));
			break;
		case 'K': // EL
			screen.eraseInLine(param(0, 0));
			break;
		case 'L': // IL
			screen.insertLines(param(0, 1));
			break;
		case 'M': // DL
			screen.deleteLines(param(0, 1));
			break;
		case 'P': // DCH
			screen.deleteCells(param(0, 1));
			break;
		case 'S': // SU
			screen.scrollUp(param(0, 1));
			break;
		case 'T': // SD
			screen.scrollDown(param(0, 1));
			break;
		case 'X': // ECH
			screen.eraseChars(param(0, 1));
			break;
		case '@': // ICH
			screen.insertCells(param(0, 1));
			break;
		case 'd': // VPA
			{
				immutable row = param(0, 1) - 1;
				if (screen.originMode)
					screen.cursorRow = screen.scrollTop + row;
				else
					screen.cursorRow = row;
				screen.clampCursor();
			}
			break;
		case 'm': // SGR
			applySgr();
			break;
		case 'r': // DECSTBM
			{
				immutable top = param(0, 1) - 1;
				immutable bottom = (_params.length < 2 || _params[1] == 0)
					? screen.rows - 1
					: _params[1] - 1;
				screen.setScrollRegion(top, bottom);
				screen.cursorCol = 0;
				screen.cursorRow = screen.originMode ? screen.scrollTop : 0;
			}
			break;
		case 'h': // SM
			setMode(true);
			break;
		case 'l': // RM
			setMode(false);
			break;
		default:
			break;
		}
	}

	private void dispatchPrivateCsi(char finalByte)
	{
		// DECSET / DECRST — params are mode numbers
		immutable enable = finalByte == 'h';
		if (finalByte != 'h' && finalByte != 'l')
			return;
		foreach (mode; _params)
		{
			switch (mode)
			{
			case 25: // DECTCEM
				screen.cursorVisible = enable;
				break;
			case 6: // DECOM
				screen.originMode = enable;
				screen.cursorCol = 0;
				screen.cursorRow = enable ? screen.scrollTop : 0;
				break;
			case 7: // DECAWM
				screen.autoWrap = enable;
				break;
			case 4: // IRM (also non-private) — accept under ?
				screen.insertMode = enable;
				break;
			default:
				break;
			}
		}
	}

	private void setMode(bool enable)
	{
		foreach (mode; _params)
		{
			switch (mode)
			{
			case 4: // IRM
				screen.insertMode = enable;
				break;
			default:
				break;
			}
		}
	}

	private void applySgr()
	{
		if (_params.length == 0)
		{
			screen.penAttrs.reset();
			screen.penFg = Color.defaultColor();
			screen.penBg = Color.defaultColor();
			return;
		}

		size_t i = 0;
		while (i < _params.length)
		{
			immutable p = _params[i];
			switch (p)
			{
			case 0:
				screen.penAttrs.reset();
				screen.penFg = Color.defaultColor();
				screen.penBg = Color.defaultColor();
				break;
			case 1:
				screen.penAttrs.bold = true;
				break;
			case 2:
				screen.penAttrs.faint = true;
				break;
			case 3:
				screen.penAttrs.italic = true;
				break;
			case 4:
				screen.penAttrs.underline = true;
				break;
			case 5:
			case 6:
				screen.penAttrs.blink = true;
				break;
			case 7:
				screen.penAttrs.inverse = true;
				break;
			case 8:
				screen.penAttrs.invisible = true;
				break;
			case 9:
				screen.penAttrs.strikethrough = true;
				break;
			case 22:
				screen.penAttrs.bold = false;
				screen.penAttrs.faint = false;
				break;
			case 23:
				screen.penAttrs.italic = false;
				break;
			case 24:
				screen.penAttrs.underline = false;
				break;
			case 25:
				screen.penAttrs.blink = false;
				break;
			case 27:
				screen.penAttrs.inverse = false;
				break;
			case 28:
				screen.penAttrs.invisible = false;
				break;
			case 29:
				screen.penAttrs.strikethrough = false;
				break;
			case 30: .. case 37:
				screen.penFg = Color.ansi(cast(ubyte)(p - 30));
				break;
			case 39:
				screen.penFg = Color.defaultColor();
				break;
			case 40: .. case 47:
				screen.penBg = Color.ansi(cast(ubyte)(p - 40));
				break;
			case 49:
				screen.penBg = Color.defaultColor();
				break;
			case 90: .. case 97:
				screen.penFg = Color.ansi(cast(ubyte)(p - 90 + 8));
				break;
			case 100: .. case 107:
				screen.penBg = Color.ansi(cast(ubyte)(p - 100 + 8));
				break;
			case 38:
			case 48:
				{
					immutable isFg = p == 38;
					Color c;
					size_t consumed;
					if (!parseExtendedColor(i, c, consumed))
					{
						i++;
						continue;
					}
					if (isFg)
						screen.penFg = c;
					else
						screen.penBg = c;
					i += consumed;
					continue;
				}
			default:
				break;
			}
			i++;
		}
	}

	/// Parse 38/48 extended color starting at index i (the 38/48 itself).
	/// Returns false if truncated; consumed is number of params eaten including 38/48.
	private bool parseExtendedColor(size_t i, out Color c, out size_t consumed)
	{
		if (i + 1 >= _params.length)
			return false;
		immutable mode = _params[i + 1];
		if (mode == 5)
		{
			if (i + 2 >= _params.length)
				return false;
			c = Color.ansi(cast(ubyte) _params[i + 2]);
			consumed = 3;
			return true;
		}
		if (mode == 2)
		{
			if (i + 4 >= _params.length)
				return false;
			c = Color.rgbColor(
				cast(ubyte) _params[i + 2],
				cast(ubyte) _params[i + 3],
				cast(ubyte) _params[i + 4]);
			consumed = 5;
			return true;
		}
		return false;
	}

	private void handleOsc(ubyte b)
	{
		if (b == 0x07) // BEL terminator
		{
			finishOsc();
			return;
		}
		// ST = ESC \
		if (_osc.length && _osc[$ - 1] == cast(char) 0x1B && b == '\\')
		{
			_osc.length = _osc.length - 1; // drop ESC
			finishOsc();
			return;
		}
		_osc ~= cast(char) b;
	}

	private void finishOsc()
	{
		_state = State.ground;
		auto body = _osc;
		_osc.length = 0;

		// Strip accidental ESC if present
		while (body.length && body[$ - 1] == 0x1B)
			body = body[0 .. $ - 1];

		size_t semi = body.length;
		foreach (i, ch; body)
		{
			if (ch == ';')
			{
				semi = i;
				break;
			}
		}
		int ps = 0;
		if (semi > 0)
		{
			try
				ps = to!int(body[0 .. semi]);
			catch (Exception)
				return;
		}
		auto pt = semi < body.length ? body[semi + 1 .. $].idup : "";
		switch (ps)
		{
		case 0:
		case 2:
			screen.title = pt;
			break;
		default:
			break;
		}
	}
}

// ---- golden sequence tests ----

unittest
{
	auto em = new Emulator(10, 4);
	em.feed("Hello");
	assert(em.screen.dumpText() == "Hello");
	assert(em.screen.cursorCol == 5);
}

unittest
{
	auto em = new Emulator(20, 5);
	em.feed("\033[2J\033[H"); // clear + home
	em.feed("\033[31;1mHi\033[0m");
	assert(em.screen.at(0, 0).ch == 'H');
	assert(em.screen.at(0, 0).fg == Color.ansi(1));
	assert(em.screen.at(0, 0).attrs.bold);
	assert(em.screen.at(1, 0).ch == 'i');
	assert(em.screen.penFg.kind == ColorKind.default_);
}

unittest
{
	auto em = new Emulator(10, 3);
	em.feed("abc");
	em.feed("\033[1;1H");
	em.feed("\033[2K"); // erase line
	assert(em.screen.at(0, 0).ch == ' ');
	assert(em.screen.at(1, 0).ch == ' ');
	assert(em.screen.at(2, 0).ch == ' ');
}

unittest
{
	auto em = new Emulator(5, 3);
	em.feed("12345");
	em.feed("\n");
	em.feed("abc");
	em.feed("\033[1;1H\033[1J"); // erase from start through cursor (home)
	// After CUP 1;1, erase mode 1 clears start..cursor on that line and rows above
	assert(em.screen.at(0, 0).ch == ' ');
}

unittest
{
	auto em = new Emulator(8, 3);
	em.feed("\033[38;2;10;20;30mX\033[0m");
	assert(em.screen.at(0, 0).fg == Color.rgbColor(10, 20, 30));
	em.feed("\033[48;5;200mY");
	assert(em.screen.at(1, 0).bg == Color.ansi(200));
}

unittest
{
	auto em = new Emulator(10, 4);
	em.feed("\033]2;My Title\007");
	assert(em.screen.title == "My Title");
	em.feed("\033]0;Other\033\\");
	assert(em.screen.title == "Other");
}

unittest
{
	auto em = new Emulator(4, 2, 5);
	em.feed("AAAA\r\nBBBB\r\n"); // scroll on second line feed
	assert(em.screen.scrollbackLines >= 1);
	assert(em.screen.scrollbackAt(0)[0].ch == 'A');
}

unittest
{
	auto em = new Emulator(10, 5);
	em.feed("\033[?25l");
	assert(!em.screen.cursorVisible);
	em.feed("\033[?25h");
	assert(em.screen.cursorVisible);
}

unittest
{
	auto em = new Emulator(10, 5);
	em.feed("\033[3;5r"); // scroll region rows 3-5
	assert(em.screen.scrollTop == 2);
	assert(em.screen.scrollBottom == 4);
	em.feed("\033[H");
	em.feed("top");
	em.feed("\033[5;1H");
	em.feed("bot");
	em.feed("\033[S"); // scroll up in region
	assert(em.screen.at(0, 4).ch == ' '); // bottom cleared
}

unittest
{
	auto em = new Emulator(10, 3);
	em.feed("café"); // UTF-8
	assert(em.screen.at(0, 0).ch == 'c');
	assert(em.screen.at(3, 0).ch == 'é');
}

unittest
{
	import std.algorithm : startsWith;
	auto em = new Emulator(10, 3);
	em.feed("AB");
	em.feed("\033[1D"); // CUB
	em.feed("X");
	assert(em.screen.dumpText().startsWith("AX"));
}
