module io.text;

import io.core;
import io.buffer;
import std.traits;
import std.range;

version(Windows)
{
    enum NativeNewLine = "\r\n";
}
else version(Posix)
{
    enum NativeNewLine = "\n";
}
else
{
    static assert(0, "not yet supported");
}

/**
Lined receives pool of char, and makes input range of lines separated $(D delim).
Naming:
    LineReader?
    LineStream?
Examples:
    lined!string(File("foo.txt"))
*/
@property auto lined(String = string, Source)(Source source, size_t bufferSize=2048)
    if (isSource!Source)
{
    alias Unqual!(ForeachType!String) Char;
    auto p = source.coerced!Char.buffered(bufferSize);

    return Lined!(typeof(p), String, String)(p, cast(String)NativeNewLine);
}

/// ditto
auto lined(String = string, Source, Delim)(Source source, in Delim delim, size_t bufferSize=2048)
    if (isSource!Source && isInputRange!Delim)
{
    alias Unqual!(ForeachType!String) Char;
    auto p = source.coerced!Char.buffered(bufferSize);

    return Lined!(typeof(p), Delim, String)(p, delim);
}

struct Lined(Pool, Delim, String : Char[], Char)
    if (isPool!Pool && isSomeChar!Char)
{
private:
    static assert(is(DeviceElementType!Pool == Unqual!Char));
    alias Unqual!Char MutableChar;

    import std.array : Appender;

    Pool pool;
    Delim delim;
    Appender!(MutableChar[]) buffer;
    String line;
    bool eof;

public:
    /**
    */
    this(Pool p, Delim d)
    {
        //move(p, pool);
        //move(d, delim);
        pool = p;
        delim = d;
        popFront();
    }

    /**
    primitives of input range.
    */
    @property bool empty() const
    {
        return eof;
    }

    /// ditto
    @property String front() const
    {
        return line;
    }

    /// ditto
    void popFront()
    in { assert(!empty); }
    body
    {
        const(MutableChar)[] view;
        const(MutableChar)[] nextline;

        bool fetchExact()   // fillAvailable?
        {
            view = pool.available;
            while (view.length == 0)
            {
                //writefln("fetched");
                if (!pool.fetch())
                    return false;
                view = pool.available;
            }
            return true;
        }
        if (!fetchExact())
        {
            eof = true;
            return;
        }

        buffer.clear();

        //writefln("Buffered.popFront : ");
        for (size_t vlen=0, dlen=0; ; )
        {
            if (vlen == view.length)
            {
                buffer.put(view);
                nextline = buffer.data;
                pool.consume(vlen);
                if (!fetchExact())
                    break;

                vlen = 0;
                continue;
            }

            auto e = view[vlen];
            ++vlen;
            if (e == delim[dlen])
            {
                ++dlen;
                if (dlen == delim.length)
                {
                    if (buffer.data.length)
                    {
                        buffer.put(view[0 .. vlen]);
                        nextline = (buffer.data[0 .. $ - dlen]);
                    }
                    else
                        nextline = view[0 .. vlen - dlen];

                    pool.consume(vlen);
                    break;
                }
            }
            else
                dlen = 0;
        }

      static if (is(Char == immutable))
        line = nextline.idup;
      else
        line = nextline;
    }
}

version(unittest)
{
    import io.file;
    import std.stdio : writeln, writefln;
}
unittest
{
    string line;
    foreach (ln; File(__FILE__).lined!string("\n"))
    {
        line = ln;
        break;
    }
    assert(line == "module io.text;");
}
