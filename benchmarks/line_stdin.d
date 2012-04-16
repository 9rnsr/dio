import std.random, std.datetime;

static import io.wrapper, io.text;
static import std.stdio;

void main(string[] args)
{
    if (args.length != 2)
        return;

    enum count = 4096;

    import std.path, std.conv;
    string fname = text("out.", baseName(__FILE__), ".", __LINE__);

    if (args[1] == "gen")
    {
        auto rng = Xorshift(1);

        auto f = std.stdio.File(fname, "w");
        foreach (i; 0 .. count)
        {
            f.writeln(rng.front);
            rng.popFront();
        }
        return;
    }

    void testio() @trusted
    {
        string s;
        foreach (i; 0 .. count)
        {
            io.wrapper.readf("%s\r\n", &s);
        }
    }
    void teststd() @trusted
    {
        string s;
        foreach (i; 0 .. count)
        {
            std.stdio.readf("%s\n", &s);
        }
    }

    auto times = benchmark!(testio, teststd)(1);
    io.wrapper.writef(io.text.derr, "times[0] = %s\r\n", times[0]);
    io.wrapper.writef(io.text.derr, "times[1] = %s, rate = %s\r\n", times[1],
        cast(real)times[1].length / cast(real)times[0].length);
}

