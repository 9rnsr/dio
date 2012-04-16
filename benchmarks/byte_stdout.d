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
        auto rnd = Xorshift(1);
        foreach (i; 0 .. count)
        {
            //io.wrapper.write(rnd.front);
            io.wrapper.write(uniform(' ', 'z', rnd));
        }
    }
    void teststd() @trusted
    {
        auto rnd = Xorshift(1);
        foreach (i; 0 .. count)
        {
            //std.stdio.write(rnd.front);
            std.stdio.write(uniform(' ', 'z', rnd));
        }
    }

    auto times = benchmark!(testio, teststd)(1);
    io.wrapper.writef(io.text.derr, "times[0] = %s\r\n", times[0]);
    io.wrapper.writef(io.text.derr, "times[1] = %s, rate = %s\r\n", times[1],
        cast(real)times[1].length / cast(real)times[0].length);
}

