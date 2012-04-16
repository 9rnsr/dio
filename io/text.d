module io.text;

import io.core;
import io.file;
import std.traits;
import std.range;

version(Windows)
{
    enum NativeNewLine = "\r\n";
    import core.sys.windows.windows, std.windows.syserror;
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
----
foreach (line; File("foo.txt").lined!string("\n"))
{
    writeln(line);
}
----
*/
@property auto lined(String = string, Source)(Source source, size_t bufferSize=2048)
    if (isSource!Source)
{
    return .lined!String(source, cast(String)NativeNewLine, bufferSize);
}

/// ditto
auto lined(String = string, Source, Delim)(Source source, in Delim delim, size_t bufferSize=2048)
    if (isSource!Source && isInputRange!Delim)
{
    static struct Lined(Dev, Delim, String : Char[], Char)
        if (isPool!Dev && isSomeChar!Char)
    {
    private:
        static assert(is(DeviceElementType!Dev == Unqual!Char));
        alias Unqual!Char MutableChar;

        import std.array : Appender;

        Dev device;
        Delim delim;
        Appender!(MutableChar[]) buffer;
        String line;
        bool eof;

    public:
        this(Dev dev, Delim delim)
        {
            this.device = dev;
            this.delim = delim;
            popFront();
        }

        @property bool empty() const
        {
            return eof;
        }
        @property String front() const
        {
            return line;
        }
        void popFront()
        in { assert(!empty); }
        body
        {
            const(MutableChar)[] view;
            const(MutableChar)[] nextline;

            bool fetchExact()   // fillAvailable?
            {
                view = device.available;
                while (view.length == 0)
                {
                    if (!device.fetch())
                        return false;
                    view = device.available;
                }
                return true;
            }
            if (!fetchExact())
            {
                eof = true;
                return;
            }

            buffer.clear();

            for (size_t vlen=0, dlen=0; ; )
            {
                if (vlen == view.length)
                {
                    buffer.put(view);
                    nextline = buffer.data;
                    device.consume(vlen);
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

                        device.consume(vlen);
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

    alias Unqual!(ForeachType!String) Char;
    auto p = source.coerced!Char.buffered(bufferSize);

    return Lined!(typeof(p), Delim, String)(p, delim);
}

version(unittest)
{
    import io.file;
    import std.stdio : writeln, writefln;
}
unittest
{
    foreach (ln; File(__FILE__).lined!string){}

    string line;
    foreach (ln; File(__FILE__).lined!string("\n"))
    {
        line = ln;
        break;
    }
    assert(line == "module io.text;");
}

version(Windows)
{
    import sys.windows;

    alias InputRange!dchar TextInputRange;

    interface TextOutputRange
    {
        void put(const(char)[]);
        void put(const(wchar)[]);
        void put(const(dchar)[]);
    }

    class StdInputRange(bool console) : TextInputRange
    {
    private:
        File file;
        HANDLE function() getHandle;
        union
        {
            Ranged!(Buffered!(Sourced!(Coerced!(wchar, File*)))) cin;
            Ranged!(Buffered!(Sourced!(Coerced!( char, File*)))) bin;
        }
        static if (console)
        {
            alias cin input;
            enum makeInput = q{ (&file).coerced!wchar.sourced.buffered.ranged };
        }
        else
        {
            alias bin input;
            enum makeInput = q{ (&file).coerced! char.sourced.buffered.ranged };
        }

    public  // needs for emplace
        this(HANDLE function() get)
        {
            getHandle = get;

            auto hFile = getHandle();
            input = mixin(makeInput);
            switching(hFile);
        }
        ~this()
        {
            clear(input);
        }

    private:
        void switching(HANDLE hFile)
        {
            if ((GetFileType(hFile) == FILE_TYPE_CHAR) != console)
            {
                import std.conv;
                alias StdInputRange!(!console) Target;

                // switch behavior for console
                auto payload = (cast(void*)this)[0 .. __traits(classInstanceSize, typeof(this))];
                auto t = emplace!Target(payload, getHandle);
                assert(t is this);
            }
            else
                file.attach(hFile);
        }

    public:
        bool empty()
        {
            if (!input.empty)
                return false;

            /*
            If cannot read any characters, check redirection.
            */
            HANDLE hFile = getHandle();
            if (hFile == file)
                return true;    // continue

            switching(hFile);
            //return input.empty;
            return this.empty();    // needs virtual call
        }

        @property dchar front()
        {
            return input.front;
        }

        dchar moveFront()
        {
            return .moveFront(input);
        }

        void popFront()
        {
            input.popFront();
        }

        int opApply(int delegate(dchar) dg)
        {
            for(; !input.empty; input.popFront())
            {
                if (auto r = dg(input.front))
                    return r;
            }
            return 0;
        }
        int opApply(int delegate(size_t, dchar) dg)
        {
            for(size_t i = 0; !input.empty; input.popFront())
            {
                if (auto r = dg(i++, input.front))
                    return r;
            }
            return 0;
        }
    }

    unittest
    {
        HANDLE hStdIn = GetStdHandle(STD_INPUT_HANDLE);
        assert(GetFileType(hStdIn) == FILE_TYPE_CHAR);
        auto str = "Ma Chérieあいうえお";

        // console input emulation
        DWORD nwritten;
        foreach (wchar wc; str~"\r\n")
        {
            INPUT_RECORD irec;
            irec.EventType = KEY_EVENT;
            irec.KeyEvent.wRepeatCount = 1;
            irec.KeyEvent.wVirtualKeyCode = 0;   // todo
            irec.KeyEvent.wVirtualScanCode = 0;  // todo
            irec.KeyEvent.UnicodeChar = wc;
            irec.KeyEvent.dwControlKeyState = 0; // todo

            irec.KeyEvent.bKeyDown = TRUE;
            WriteConsoleInputW(hStdIn, &irec, 1, &nwritten);

            irec.KeyEvent.bKeyDown = FALSE;
            WriteConsoleInputW(hStdIn, &irec, 1, &nwritten);
        }

        import io.wrapper;
        string s;
        readf("%s\r\n", &s);

        //writefln("s   = [%(%02X %)]\r\n", s);   // as Unicode code points
        //writefln("s   = [%(%02X %)]\r\n", cast(ubyte[])s);    // as UTF-8
        //writefln("str = [%(%02X %)]\r\n", cast(ubyte[])str);  // as UTF-8
        assert(s == str);
    }

    class StdOutputRange(bool console) : TextOutputRange
    {
    private:
        File file;
        HANDLE function() getHandle;
        union
        {
            Ranged!(Sinked!(Coerced!(wchar, File*))) cout;
            Ranged!(Sinked!(Coerced!( char, File*))) bout;
        }
        static if (console)
        {
            enum makeOutput = q{ (&file).coerced!wchar.sinked/*.buffered*/.ranged };
            alias cout output;
        }
        else
        {
            enum makeOutput = q{ (&file).coerced!char.sinked/*.buffered*/.ranged };
            alias bout output;
        }

    public  // needs for emplace
        this(HANDLE function() get)
        {
            getHandle = get;

            auto hFile = getHandle();
            output = mixin(makeOutput);
            switching(hFile);
        }
        ~this()
        {
            clear(output);
        }

    private:
        void switching(HANDLE hFile)
        {
            if ((GetFileType(hFile) == FILE_TYPE_CHAR) != console)
            {
                import std.conv;
                alias StdOutputRange!(!console) Target;

                // switch behavior for console
                auto payload = (cast(void*)this)[0 .. __traits(classInstanceSize, typeof(this))];
                auto t = emplace!Target(payload, getHandle);
                assert(t is this);
            }
            else
                file.attach(hFile);
        }

    public:
        void put(const(char)[] data)
        {
            output.put(data);
        }
        void put(const(wchar)[] data)
        {
            output.put(data);
        }
        void put(const(dchar)[] data)
        {
            output.put(data);
        }
    }
}

//__gshared
//{
    /**
    Pre-defined text range interface for standard input, output, and error output.
    */
    InputRange!dchar din;
    TextOutputRange dout;     /// ditto
    TextOutputRange derr;     /// ditto
//}
/*shared */static this()
{
    import util.typecons;

  version(Windows)
  {
    din  = new StdInputRange!false(()=>GetStdHandle(STD_INPUT_HANDLE));
    dout = new StdOutputRange!false(()=>GetStdHandle(STD_OUTPUT_HANDLE));
    derr = new StdOutputRange!false(()=>GetStdHandle(STD_ERROR_HANDLE));
  }
}
static ~this()
{
    derr.clear();
    dout.clear();
    din.clear();
}
