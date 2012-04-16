import std.random, std.datetime;

void main(string[] args)
{
    enum count = 4096;

    import std.path, std.conv;
    string fname = "out.txt";
    if (args.length == 2 && args[1] == "gen")
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
        import io.core, io.file, io.text;
        auto f = File(fname);
        foreach (s; lined!(const(char)[])(f))
        //foreach (s; lined!string(f))
        {
        }
    }
    void teststd() @trusted
    {
        import std.stdio;
        auto f = File(fname);
        foreach (s; f.byLine)
        {
        }
    }

    auto times = benchmark!(testio, teststd)(10);
    import io.wrapper;
    io.wrapper.writef(io.text.derr, "times[0] = %s\r\n", times[0]);
    io.wrapper.writef(io.text.derr, "times[1] = %s, rate = %s\r\n", times[1],
        cast(real)times[1].length / cast(real)times[0].length);
}

