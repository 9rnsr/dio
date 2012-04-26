/**
*/
module io.port;

import io.core, io.file;
import util.typecons;
import std.range, std.traits;

//import core.stdc.stdio : printf;


private template isNarrowChar(T)
{
    enum isNarrowChar = is(Unqual!T == char) || is(Unqual!T == wchar);
}

/**
*/
File stdin;
File stdout;    /// ditto
File stderr;    /// ditto

static this()
{
    version(Windows)
    {
        import sys.windows;
        stdin  = File(GetStdHandle(STD_INPUT_HANDLE));
        stdout = File(GetStdHandle(STD_OUTPUT_HANDLE));
        stderr = File(GetStdHandle(STD_ERROR_HANDLE));
    }
}

/**
*/
@property auto din() { return stdin.textPort(); }
@property auto dout() { return stdout.textPort(); } /// ditto
@property auto derr() { return stderr.textPort(); } /// ditto

/**
Configure text I/O port with following translations:
$(UL
$(LI Unicode transcoding. If original device element is ubyte, treats as UTF-8 device.)
$(LI New-line conversion, replace $(D '\r'), $(D '\n'), $(D '\r\n') to $(D '\n') for input, and vice versa.)
$(LI Buffering. For output, line buffering is done.)
)
*/
auto textPort(Dev)(Dev device)
if (isSomeChar!(DeviceElementType!Dev) ||
    is(DeviceElementType!Dev == ubyte))
{
    alias typeof({ return Dev.init.coerced!char.buffered; }()) LowDev;

    version(Windows)
    {
        import sys.windows;
        enum isWindows = true;
    }
    else
        enum isWindows = false;
    static if (isWindows && is(typeof(device.handle) : HANDLE))
    {
        import std.conv;
        alias typeof({ return Dev.init.coerced!wchar.buffered; }()) ConDev;

        // Type erasure for console device
        static struct WindowsTextPort
        {
        private:
            bool con;
            union
            {
                TextPort!ConDev cport;
                TextPort!LowDev fport;
            }

        public:
            this(this)
            {
                con ? typeid(cport).postblit(&cport)
                    : typeid(fport).postblit(&fport);
            }
            ~this()
            {
                con ? clear(cport) : clear(fport);
            }

          static if (isSource!Dev)
          {
            @property bool empty()
            {
                return con ? cport.empty : fport.empty;
            }
            @property dchar front()
            {
                return con ? cport.front : fport.front;
            }
            void popFront()
            {
                return con ? cport.popFront() : fport.popFront();
            }
            int opApply(scope int delegate(dchar) dg)
            {
                return con ? cport.opApply(dg) : fport.opApply(dg);
            }

            //auto lines(LineType = const(char)[])()
            //{
            //    return con ? cport.lines!LineType : fport.lines!LineType;
            //}
          }

          static if (isSink!Dev)
          {
            void put(dchar data) { return con ? cport.put(data) : fport.put(data); }
            void put(const( char)[] data) { return con ? cport.put(data) : fport.put(data); }
            void put(const(wchar)[] data) { return con ? cport.put(data) : fport.put(data); }
            void put(const(dchar)[] data) { return con ? cport.put(data) : fport.put(data); }
          }
        }

        WindowsTextPort wport;

        // If original device is character file, I/O UTF-16 encodings.
        if (GetFileType(device.handle) == FILE_TYPE_CHAR)
        {
            wport.con = true;
            emplace(&wport.cport, device.coerced!wchar.buffered);
        }
        else
        {
            wport.con = false;
            emplace(&wport.fport, device.coerced!char.buffered);
        }
        return wport;
    }
    else
    {
        return TextPort!LowDev(device.coerced!char.buffered);
    }
}

/**
Implementation of text port.
 */
struct TextPort(Dev)
{
private:
    alias Unqual!(DeviceElementType!Dev) B;
    alias Select!(isNarrowChar!B, dchar, B) E;
    static assert(isBufferedSource!Dev || isBufferedSink!Dev);
    static assert(isSomeChar!B);

    Dev device;
    bool eof;
    dchar front_val; bool front_ok;

public:
  static if (isSource!Dev)
  {
    /**
    Provides character input range if original device is $(I source).
    */
    @property bool empty()
    {
        while (device.available.length == 0 && !eof)
            eof = !device.fetch();
        assert(eof || device.available.length > 0);
        return eof;
    }

    /// ditto
    @property dchar front()
    {
        if (front_ok)
            return front_val;

        static if (isNarrowChar!B)
        {
            import std.utf;
            B c = device.available[0];
            if (c == '\r')
            {
                device.consume(1);
                while (device.available.length == 0 && device.fetch()) {}
                if (device.available.length == 0)
                    goto err;
                c = device.available[0];
            }
            auto n = stride((&c)[0..1], 0);
            if (n == 1)
            {
                device.consume(1);
                front_ok = true;
                front_val = c;
                return c;
            }

            B[B.sizeof == 1 ? 6 : 2] ubuf;
            B[] buf = ubuf[0 .. n];
            while (buf.length > 0 && device.pull(buf)) {}
            if (buf.length)
                goto err;
            size_t i = 0;
            front_val = decode(ubuf[0 .. n], i);
        }
        else
        {
            front_val = device.available[0];
            device.consume(1);
        }
        front_ok = true;
        return front_val;

    err:
        throw new Exception("Unexpected failure of fetching value form underlying device");
    }

    /// ditto
    void popFront()
    {
        //device.consume(1);
        front_ok = false;
    }

    /// for efficient character input range iteration.
    int opApply(scope int delegate(dchar) dg)
    {
        for(; !empty; popFront())
        {
            if (auto r = dg(front))
                return r;
        }
        return 0;
    }

    /** returns line range.
    Example:
    ---
    foreach (ln; stdin.textPort().lines) {}
    ---
    */
    //auto lines(LineType = const(char)[])()
    //{
    //    return con ? cport.lines!LineType : fport.lines!LineType;
    //    //return LinePort!(ForeachType!LineType)(this);
    //}
  }

  static if (isSink!Dev)
  {
    enum const(B)[] NativeNewline = "\r\n";

    /**
    Provides character output range if original device is $(I sink).
    */
    void put()(dchar data)
    {
        put((&data)[0 .. 1]);
    }

    /// ditto
    void put()(const(B)[] data)
    {
        immutable last = data.length - 1;
    retry:
        foreach (i, e; data)
        {
            if (e == '\n')
            {
                auto buf = data[0 .. i];
                while (device.push(buf) && buf.length) {}
                if (buf.length)
                    throw new Exception("");

                buf = NativeNewline;
                while (device.push(buf) && buf.length) {}
                if (buf.length)
                    throw new Exception("");
                device.flush();

                data = data[i .. $];
                goto retry;
            }
        }
        if (data.length)
        {
            while (device.push(data) && data.length) {}
            if (data.length)
                throw new Exception("");
            device.flush();
        }
    }

    /// ditto
    void put()(const(dchar)[] data) if (isNarrowChar!B)
    {
        // with encoding
        import std.utf;
        foreach (c; data)
        {
            if (c == '\n')
            {
                auto buf = NativeNewline;
                while (device.push(buf) && buf.length) {}
                if (buf.length)
                    throw new Exception("");
                device.flush();
                continue;
            }

            B[B.sizeof == 1 ? 4 : 2] ubuf;
            const(B)[] buf = ubuf[0 .. encode(ubuf, c)];
            while (device.push(buf) && buf.length) {}
            if (buf.length)
                throw new Exception("");
        }
    }

    /// ditto
    void put(C)(const(C)[] data) if (isNarrowChar!C && !is(B == C))
    {
        // with transcoding from narrows
        import std.utf;
        size_t i = 0;
        while (i < data.length)
        {
            dchar c = decode(data, i);
            if (c == '\n')
            {
                auto buf = NativeNewline;
                while (device.push(buf) && buf.length) {}
                if (buf.length)
                    throw new Exception("");
                device.flush();
                continue;
            }

            B[B.sizeof == 1 ? 4 : 2] ubuf;
            const(B)[] buf = ubuf[0 .. encode(ubuf, c)];
            while (device.push(buf) && buf.length) {}
            if (buf.length)
                throw new Exception("");
        }
    }
  }
}
