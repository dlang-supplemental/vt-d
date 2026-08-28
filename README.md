# vt-d

VT/ANSI escape parser and character-cell screen model for D.

**DUB:** [vt-d](https://code.dlang.org/packages/vt-d) · **Repo:** [dlang-supplemental/vt-d](https://github.com/dlang-supplemental/vt-d)

Pure logic: feed a byte stream → `Screen` of cells (glyph, colors, attrs). No PTY (see [pty-d](https://github.com/dlang-supplemental/pty-d)), no windowing, no GPU.

```d
import vt;

void main()
{
    auto em = new Emulator(80, 24);
    em.feed("\033[31;1mHello\033[0m\n");
    assert(em.screen.at(0, 0).ch == 'H');
}
```

```sdl
dependency "vt-d" version="~>0.1.0"
```

Full docs: see [README.adoc](README.adoc). MIT licensed.
