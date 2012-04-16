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
    assert(line == "module io.text;");
}

version(Windows)
{
    import sys.windows;

    static File _win_cstdin;
    static File _win_fstdin;
    static InputRange!dchar _win_cin;
    static InputRange!dchar _win_fin;

    static initializeStdIn()
    {
        _win_cin = new StdInRange!true();
        _win_fin = new StdInRange!false();

        HANDLE hFile = GetStdHandle(STD_INPUT_HANDLE);
        if (GetFileType(hFile) == FILE_TYPE_CHAR)
        {
            _win_cstdin.attach(hFile);
            return _win_cin;
        }
        else
        {
            _win_fstdin.attach(hFile);
            return _win_fin;
        }
    }

    class StdInRange(bool console) : InputRange!dchar
    {
    private:
        static if (console)
        {
            enum RangedDevice = q{ (&_win_cstdin).coerced!wchar.sourced.buffered.ranged };
            alias Ranged!(Buffered!(Sourced!(Coerced!(wchar, File*)))) InputType;
            alias _win_cstdin file;
        }
        else
        {
            enum RangedDevice = q{ (&_win_fstdin).coerced!char.sourced.buffered.ranged };
            alias Ranged!(Buffered!(Sourced!(Coerced!( char, File*)))) InputType;
            alias _win_fstdin file;
        }

        InputType input;

        this()
        {
            input = mixin(RangedDevice);
        }

    public:
        bool empty()
        {
            if (!input.empty)
                return false;

            /*
            If cannot read any characters, check redirection.
            */
            bool nextEmpty()
            {
                HANDLE hFile = GetStdHandle(STD_INPUT_HANDLE);
                if (hFile == file)
                    return true;    // continue

                if (console && GetFileType(hFile) != FILE_TYPE_CHAR)
                {   // switch console to non-console
                    assert(this is _win_cin);
                    _win_cstdin.detach();
                    _win_fstdin.attach(hFile);
                    .din = _win_fin;
                }
                else if (!console && GetFileType(hFile) == FILE_TYPE_CHAR)
                {   // switch non-console to console
                    assert(this is din);
                    _win_fstdin.detach();
                    _win_cstdin.attach(hFile);
                    .din = _win_cin;
                }
                else
                {
                    file.attach(hFile);
                }
                return .din.empty;
            }
            return nextEmpty();
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
        readf(din, "%s\r\n", &s);

        //std.stdio.writefln("s   = [%(%02X %)]\r\n", s);   // as Unicode code points
        //std.stdio.writefln("s   = [%(%02X %)]\r\n", cast(ubyte[])s);    // as UTF-8
        //std.stdio.writefln("str = [%(%02X %)]\r\n", cast(ubyte[])str);  // as UTF-8
        assert(s == str);
    }

    static File _win_cstdout;
    static File _win_fstdout;
    static TextOutputRange _win_cout;
    static TextOutputRange _win_fout;

    static File _win_cstderr;
    static File _win_fstderr;
    static TextOutputRange _win_cerr;
    static TextOutputRange _win_ferr;

    static initializeStdOut(DWORD nStdHandle)
    {
        if (nStdHandle == STD_OUTPUT_HANDLE)
        {
            _win_cout = new StdOutRange!true(nStdHandle);
            _win_fout = new StdOutRange!false(nStdHandle);

            HANDLE hFile = GetStdHandle(STD_OUTPUT_HANDLE);
            if (GetFileType(hFile) == FILE_TYPE_CHAR)
            {
                _win_cstdout.attach(hFile);
                return _win_cout;
            }
            else
            {
                _win_fstdout.attach(hFile);
                return _win_fout;
            }
        }
        else
        {
            _win_cerr = new StdOutRange!true(nStdHandle);
            _win_ferr = new StdOutRange!false(nStdHandle);

            HANDLE hFile = GetStdHandle(STD_OUTPUT_HANDLE);
            if (GetFileType(hFile) == FILE_TYPE_CHAR)
            {
                _win_cstderr.attach(hFile);
                return _win_cerr;
            }
            else
            {
                _win_fstderr.attach(hFile);
                return _win_ferr;
            }
        }
    }

    interface TextOutputRange
    {
        void put(const(char)[]);
        void put(const(wchar)[]);
        void put(const(dchar)[]);
    }

    class StdOutRange(bool console) : TextOutputRange
    {
    private:
        static if (console)
        {
            enum RangedDevice = q{ (&cout).coerced!wchar.sinked/*.buffered*/.ranged };
            //alias Ranged!(Buffered!(Sinked!(Coerced!(wchar, File*)))) OutputType;
            alias Ranged!(Sinked!(Coerced!(wchar, File*))) OutputType;
            alias _win_cstdout file;
        }
        else
        {
            enum RangedDevice = q{ (&fout).coerced!char.sinked/*.buffered*/.ranged };
            //alias Ranged!(Buffered!(Sinked!(Coerced!( char, File*)))) OutputType;
            alias Ranged!(Sinked!(Coerced!( char, File*))) OutputType;
            alias _win_fstdout file;
        }

        OutputType output;

        this(DWORD nStdHandle)
        {
            if (nStdHandle == STD_OUTPUT_HANDLE)
            {
                alias _win_cstdout cout;
                alias _win_fstdout fout;
                output = mixin(RangedDevice);
            }
            else
            {
                alias _win_cstderr cout;
                alias _win_fstderr fout;
                output = mixin(RangedDevice);
            }
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
            import io.wrapper;
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
    // /**
    // Pre-defined devices for standard input, output, and error output.
    // */
    // SourceDevice!ubyte stdin;
      SinkDevice!ubyte stdout;  /// ditto
      SinkDevice!ubyte stderr;  /// ditto

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
  //stdin  = adaptTo!(SourceDevice!ubyte)(File(GetStdHandle(STD_INPUT_HANDLE )).sourced);
    stdout = adaptTo!(  SinkDevice!ubyte)(File(GetStdHandle(STD_OUTPUT_HANDLE)).sinked);
    stderr = adaptTo!(  SinkDevice!ubyte)(File(GetStdHandle(STD_ERROR_HANDLE )).sinked);

    din  = initializeStdIn();// inputRangeObject      (stdin   .buffered  .coerced!char.ranged);
    dout = initializeStdOut(STD_OUTPUT_HANDLE);//outputRangeObject!dchar(stdout/*.buffered*/.coerced!char.ranged);
    derr = initializeStdOut(STD_ERROR_HANDLE);//outputRangeObject!dchar(stderr/*.buffered*/.coerced!char.ranged);
  }
}
static ~this()
{
    derr.clear();
    dout.clear();
    din.clear();

    stderr.clear();
    stdout.clear();
    //stdin.clear();
}
