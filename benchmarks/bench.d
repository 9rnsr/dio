import io.port, io.file;
import std.algorithm, std.range, std.random, std.datetime;

void main()
{
	auto results = map!(f => f())([
        //&benchReadCharsFromFile,
        &benchReadLinesFromFile,
        &benchWriteCharsToFile,
        &benchWriteCharsToStdout,
    ]).array();

    writefln("rate\tdio\t\t\tstd.stdio");
    foreach (t; results)
    {
        writefln("%1.4f\t%s\t%s",
            cast(real)t[1].length / cast(real)t[0].length,
            t[0],
            t[1]);
    }
}

auto benchReadCharsFromFile()
{
    enum count = 4096;
    auto fname = genXorthiftFile(count);

    return benchmark!(
        () @trusted
        {
            import io.port, io.file;
            auto f = textPort(File(fname));
            string s;
            foreach (i; 0 .. count)
            {
                readf(f, "%s\n", &s);
            }
        },
        () @trusted
        {
            auto f = std.stdio.File(fname);
            string s;
            foreach (i; 0 .. count)
            {
                f.readf("%s\n", &s);
            }
        }
    )(500);
}

auto benchReadLinesFromFile()
{
    enum count = 4096;
    auto fname = genXorthiftFile(count);

    return benchmark!(
        () @trusted
        {
            foreach (ln; File(fname).textPort().lines)
            {}
        },
        () @trusted
        {
            foreach (ln; std.stdio.File(fname).byLine())
            {}
        }
    )(20);  // cannot repeat 500
}

auto genXorthiftFile(size_t linecount)
{
    import std.path, std.conv;
    string fname = "xorshift.txt";

    auto rng = Xorshift(1);
    auto f = std.stdio.File(fname, "w");
    foreach (i; 0 .. linecount)
    {
        f.writeln(rng.front);
        rng.popFront();
    }

    return fname;
}

auto benchWriteCharsToFile()
{
    enum count = 4096;
    auto fname = "charout.txt";

    return benchmark!(
        () @trusted
        {
            auto f = File(fname, "w").textPort();
            foreach (i; 0 .. count)
            {
                writef(f, "%s,", i);
            }
            writeln(f);     // flush buffer
        },
        () @trusted
        {
            import std.stdio;
            auto f = File(fname, "w");
            foreach (i; 0 .. count)
            {
                f.writef("%s,", i);
            }
            f.writeln();    // flush buffer
        }
    )(500);
}

auto benchWriteCharsToStdout()
{
    enum count = 4096;

    return benchmark!(
        () @trusted
        {
            foreach (i; 0 .. count)
            {
                writef("%s,", i);
            }
            writeln();      // flush buffer
        },
        () @trusted
        {
            import std.stdio;
            foreach (i; 0 .. count)
            {
                writef("%s,", i);
            }
            writeln();      // flush line buffer
        }
    )(500);
}
