/++
	Feed stdin (or a hardcoded demo) through vt-d and print the cell grid as text.
+/
import std.stdio;
import vt;

void main(string[] args)
{
	auto em = new Emulator(80, 24);
	if (args.length > 1 && args[1] == "--demo")
	{
		em.feed("\033[2J\033[H");
		em.feed("\033[1;36mvt-d\033[0m demo\n");
		em.feed("\033[31mred\033[0m \033[32mgreen\033[0m \033[34mblue\033[0m\n");
		em.feed("cursor @ ");
	}
	else
	{
		foreach (chunk; stdin.byChunk(4096))
			em.feed(chunk);
	}
	writeln(em.screen.dumpText());
	if (em.screen.title.length)
		stderr.writefln("title: %s", em.screen.title);
}
