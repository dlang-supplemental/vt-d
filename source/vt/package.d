/++
	VT/ANSI escape parser and character-cell screen model.

	Pure logic library: feed a byte stream, get a grid of cells.
	No PTY, windowing, or rendering backends.

	Companion PTY bindings live in `pty-d` (ConPTY / posix_openpt).
+/
module vt;

public import vt.attrs;
public import vt.cell;
public import vt.color;
public import vt.emulator;
public import vt.screen;
