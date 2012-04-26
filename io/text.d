// module io.text;
/**
This module provides some text operations, and formatted read/write.

Example:
---
long num;
write("num>"), readf("%s\r\n", &num);
writefln("num = %s\n", num);

string str;
write("str>"), readf("%s\r\n", &str);
writefln("str = [%(%02X %)]", str);
---
 */
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
Lined receives buffered $(I source) of char, and makes input range of lines separated $(D delim).
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
        if (isBufferedSource!Dev && isSomeChar!Char)
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
    auto p = source.sourced.coerced!Char.buffered(bufferSize);

    return Lined!(typeof(p), Delim, String)(p, delim);
}

version(unittest)
{
    import io.file;
    static import std.stdio;
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
    assert(line == "// module io.text;");
}

version(Windows)
{
    import sys.windows;

    interface TextInputRange : InputRange!dchar
    {
    }

    interface TextOutputRange
    {
        void put(const(char)[]);
        void put(const(wchar)[]);
        void put(const(dchar)[]);

        bool flush();
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

        string s;
        readf(din, "%s\r\n", &s);

        //std.stdio.writefln("s   = [%(%02X %)]\r\n", s);   // as Unicode code points
        //std.stdio.writefln("s   = [%(%02X %)]\r\n", cast(ubyte[])s);    // as UTF-8
        //std.stdio.writefln("str = [%(%02X %)]\r\n", cast(ubyte[])str);  // as UTF-8
        assert(s == str);
    }

    class StdOutputRange(bool console) : TextOutputRange
    {
    private:
        File file;
        HANDLE function() getHandle;
        union
        {
            Ranged!(Buffered!(Sinked!(Coerced!(wchar, File*)))) cout;
            Ranged!(Buffered!(Sinked!(Coerced!( char, File*)))) bout;
        }
        static if (console)
        {
            enum makeOutput = q{ (&file).coerced!wchar.sinked.buffered.ranged };
            alias cout output;
        }
        else
        {
            enum makeOutput = q{ (&file).coerced!char.sinked.buffered.ranged };
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
            output.flush();
        }
        void put(const(wchar)[] data)
        {
            output.put(data);
            output.flush();
        }
        void put(const(dchar)[] data)
        {
            output.put(data);
            output.flush();
        }

        bool flush()
        {
            return output.flush();
        }
    }

    unittest
    {
        import std.algorithm, std.range, std.typetuple, std.conv;

        HANDLE hStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
        assert(GetFileType(hStdOut) == FILE_TYPE_CHAR);
        enum orgstr = "Ma Chérieあいうえお"w;
        enum orglen = orgstr.length;    // UTF-16 code unit count

        foreach (Str; TypeTuple!(string, wstring, dstring))
        {
            // get cursor positioin
            CONSOLE_SCREEN_BUFFER_INFO csbinfo;
            GetConsoleScreenBufferInfo(hStdOut, &csbinfo);
            COORD curpos = csbinfo.dwCursorPosition;

            Str str = to!Str(orgstr);

            // output to console
            writeln(dout, str);

            wchar[orglen*2] buf;    // prited columns may longer than code-unit count.
            DWORD cnt;
            ReadConsoleOutputCharacterW(hStdOut, buf.ptr, buf.length, curpos, &cnt);
            assert(equal(str, buf[0 .. orglen]));

            //static if (is(Str ==  string)) alias ubyte EB;
            //static if (is(Str == wstring)) alias ushort EB;
            //static if (is(Str == dstring)) alias uint EB;
            //std.stdio.writefln("str = [%(%02X %)]", cast(EB[])str);
            //std.stdio.writefln("buf = [%(%02X %)]", buf[0 .. orglen]);
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


/**
Output $(D args) to $(D writer).
*/
void write(Writer, T...)(ref Writer writer, T args)
    if (is(typeof({ put(writer, ""); })) && T.length > 0)
{
    import std.conv, std.traits;
    foreach (i, ref arg; args)
    {
        static if (isSomeString!(typeof(arg)))
            put(writer, arg);
        else
            put(writer, to!string(arg));
    }
}
/// ditto
void writef(Writer, T...)(ref Writer writer, T args)
    if (is(typeof({ put(writer, ""); })) && T.length > 0)
{
    import std.format;
    formattedWrite(writer, args);
}
/// ditto
void writeln(Writer, T...)(ref Writer writer, T args)
    if (is(typeof({ put(writer, ""); })))
{
    write(writer, args, "\n");
}
/// ditto
void writefln(Writer, T...)(ref Writer writer, T args)
    if (is(typeof({ put(writer, ""); })) && T.length > 0)
{
    writef(writer, args, "\n");
}

/**
Output $(D args) to $(D io.text.dout).
*/
void write(T...)(T args)
    if (T.length > 0 && !is(typeof({ put(args[0], ""); })))
{
    write(dout, args);
}
/// ditto
void writef(T...)(T args)
    if (T.length > 0 && !is(typeof({ put(args[0], ""); })))
{
    writef(dout, args);
}

/// ditto
void writeln(T...)(T args)
    if (T.length == 0 || !is(typeof({ put(args[0], ""); })))
{
    writeln(dout, args);
}
/// ditto
void writefln(T...)(T args)
    if (T.length > 0 && !is(typeof({ put(args[0], ""); })))
{
    writefln(dout, args);
}

/**
*/
uint readf(Reader, Data...)(ref Reader reader, in char[] format, Data data) if (isInputRange!Reader)
{
    import std.format;
    return formattedRead(reader, format, data);
}

/**
*/
uint readf(Data...)(in char[] format, Data data)
{
    return readf(din, format, data);
}
