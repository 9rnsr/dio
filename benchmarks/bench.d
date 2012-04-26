import io.port, io.file;
import std.random, std.datetime;

void main()
{
    benchReadCharsFromFile();
    benchReadLinesFromFile();
    benchWriteCharsToFile();
}

void benchReadCharsFromFile()
{
    enum count = 4096;
    auto fname = genXorthiftFile(count);

    auto times = benchmark!(
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
    writefln(derr, "times[0] = %s, times[1] = %s, rate = %s",
        times[0], times[1], cast(real)times[1].length / cast(real)times[0].length);
}

void benchReadLinesFromFile()
{
    enum count = 4096;
    auto fname = genXorthiftFile(count);

    auto times = benchmark!(
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
    writefln(derr, "times[0] = %s, times[1] = %s, rate = %s",
        times[0], times[1], cast(real)times[1].length / cast(real)times[0].length);
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

void benchWriteCharsToFile()
{
    enum count = 4096;
    auto fname = "charout.txt";

    auto times = benchmark!(
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
    writefln(derr, "times[0] = %s, times[1] = %s, rate = %s",
        times[0], times[1], cast(real)times[1].length / cast(real)times[0].length);
    derr.flush();
}

