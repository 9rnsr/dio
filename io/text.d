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
    import core.sys.windows.windows, std.windows.syserror;

    extern(Windows) DWORD GetFileType(HANDLE hFile);
    enum uint FILE_TYPE_UNKNOWN = 0x0000;
    enum uint FILE_TYPE_DISK    = 0x0001;
    enum uint FILE_TYPE_CHAR    = 0x0002;
    enum uint FILE_TYPE_PIPE    = 0x0003;
    enum uint FILE_TYPE_REMOTE  = 0x8000;

    struct ConsoleInput
    {
        bool pull(ref wchar[] buf)
        {
            DWORD size = void;
            HANDLE hFile = GetStdHandle(STD_INPUT_HANDLE);
            assert(GetFileType(hFile) == FILE_TYPE_CHAR);

            if (ReadConsoleW(hFile, buf.ptr, buf.length, &size, null))
            {
                debug(File)
                    std.stdio.writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
                        cast(uint)hFile, buf.length, size, GetLastError());
                debug(File)
                    std.stdio.writefln("C buf[0 .. %d] = [%(%02X %)]", size, buf[0 .. size]);
                buf = buf[size .. $];
                return (size > 0);  // valid on only blocking read
            }
            else
            {
                switch (GetLastError())
                {
                    case ERROR_BROKEN_PIPE:
                        return false;
                    default:
                        break;
                }

                debug(File)
                    std.stdio.writefln("pull ng : hFile=%08X, size=%s, GetLastError()=%s",
                        cast(uint)hFile, size, GetLastError());
                throw new Exception("pull(ref buf[]) error");

            //  // for overlapped I/O
            //  eof = (GetLastError() == ERROR_HANDLE_EOF);
            }
        }
    }

    class StdInRange
    {
    private:
        HANDLE hStdin;
        InputRange!dchar input;
        InputRange!dchar cin;

        this()
        {
            cin = inputRangeObject(ConsoleInput().buffered.ranged);
            checkHandle();
        }

        bool checkHandle()
        {
            HANDLE hFile = GetStdHandle(STD_INPUT_HANDLE);
            if (hFile == hStdin)
                return false;

            hStdin = hFile;
            if (GetFileType(hFile) == FILE_TYPE_CHAR)
                input = cin;
            else
                input = inputRangeObject(File(hFile).buffered.coerced!char.ranged);
            return true;
        }

    public:
        /**
        If we cannot read character from original device, check redirection.
        */
        bool empty()
        {
            if (!input.empty)
                return false;

            return checkHandle() ? input.empty : true;
        }
        alias input this;
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
    OutputRange!dchar dout;     /// ditto
    OutputRange!dchar derr;     /// ditto
//}
/*shared */static this()
{
    import util.typecons;

  version(Windows)
  {
  //stdin  = adaptTo!(SourceDevice!ubyte)(File(GetStdHandle(STD_INPUT_HANDLE )).sourced);
    stdout = adaptTo!(  SinkDevice!ubyte)(File(GetStdHandle(STD_OUTPUT_HANDLE)).sinked);
    stderr = adaptTo!(  SinkDevice!ubyte)(File(GetStdHandle(STD_ERROR_HANDLE )).sinked);

    din  = new StdInRange();// inputRangeObject      (stdin   .buffered  .coerced!char.ranged);
    dout = outputRangeObject!dchar(stdout/*.buffered*/.coerced!char.ranged);
    derr = outputRangeObject!dchar(stderr/*.buffered*/.coerced!char.ranged);
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
