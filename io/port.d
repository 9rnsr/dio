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

File stdin;
File stdout;
File stderr;

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

@property auto din() { return stdin.textPort(); }
@property auto dout() { return stdout.textPort(); }
@property auto derr() { return stderr.textPort(); }

/**
基底のデバイスにフィルタを掛けてテキストIOが可能なPortを構成する。
このポートによるIOでは以下の変換が行われる
・UTF-8/16/32変換、ubyteを入出力可能なデバイスはUTF-8として扱われる
・改行変換、入力時は\r,\n,\r\nを\nに変換し、出力時は指定の改行に置き換える
・バッファリング、入力では固定サイズのバッファリングが、出力時は
  行単位でのバッファリングがデフォルトで行われる
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

        // deviceがFileかつConsoleの場合、これをubyte->UTF16にcoerceして扱う
        // ユーザーが同様のことを「ユーザー定義の」file deviceで行う場合、
        // wcharを入出力するdeviceとしてtextPortに渡してやればよい
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

/*
(Lock original device automatically.)
 */
struct TextPort(Dev)
if ((isBufferedSource!Dev ||
     isBufferedSink!Dev) &&
    isSomeChar!(DeviceElementType!Dev))
{
private:
    alias Unqual!(DeviceElementType!Dev) B;
    alias Select!(isNarrowChar!B, dchar, B) E;

    Dev device;
    bool eof;
    dchar front_val; bool front_ok;

public:
    // character input range
  static if (isSource!Dev)
  {
    @property bool empty()
    {
        while (device.available.length == 0 && !eof)
            eof = !device.fetch();
        assert(eof || device.available.length > 0);
        return eof;
    }

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

    void popFront()
    {
        //device.consume(1);
        front_ok = false;
    }

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

    // character output range
  static if (isSink!Dev)
  {
    enum const(B)[] NativeNewline = "\r\n";

    void put()(dchar data)
    {
        put((&data)[0 .. 1]);
    }

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
