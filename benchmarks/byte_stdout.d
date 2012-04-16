import std.random, std.datetime;

static import io.wrapper, io.text;
static import std.stdio;

void main(string[] args)
{
    //import std.path;
    //string outfile = args.length >= 2
    //    ? args[1]
    //    : text("out.", baseName(__FILE__), ".", __LINE__);

    enum count = 4096/*uint.max*/;

    void testio() @trusted
    {
        foreach (i; 0 .. count)
        {
            io.wrapper.writef("%s,", i);
        }
        io.wrapper.writeln();    // flush buffer?
    }
    void teststd() @trusted
    {
        foreach (i; 0 .. count)
        {
            std.stdio.writef("%s,", i);
        }
        std.stdio.writeln();    // flush line buffer
    }

    auto times = benchmark!(testio, teststd)(1);
    io.wrapper.writef(io.text.derr, "times[0] = %s\r\n", times[0]);
    io.wrapper.writef(io.text.derr, "times[1] = %s, rate = %s\r\n", times[1],
        cast(real)times[1].length / cast(real)times[0].length);
}

