module io.core;

/**
Retruns element type of device.
*/
template DeviceElementType(Dev)
{
    import std.traits;

    static if (is(ParameterTypeTuple!(typeof(Dev.init.pull)) PullArgs))
    {
        alias Unqual!(ForeachType!(PullArgs[0])) DeviceElementType;
    }
    else static if (is(typeof(Dev.init.available) AvailableType))
    {
        alias Unqual!(ForeachType!AvailableType) DeviceElementType;
    }
    else static if (is(ParameterTypeTuple!(typeof(Dev.init.push)) PushArgs))
    {
        alias Unqual!(ForeachType!(PushArgs[0])) DeviceElementType;
    }
}

/**
Returns $(D true) if $(D Dev) is a $(I source). It must define the
primitive $(D pull).

$(D pull) operation provides synchronous but non-blocking input.
*/
template isSource(Dev)
{
    enum isSource = is(typeof(
    {
        Dev d;
        alias DeviceElementType!Dev E;
        E[] buf;
        while (d.pull(buf)) {}
    }));
}

/**
Returns $(D true) if $(D Dev) is a $(I pool). It must define the
three primitives, $(D fetch), $(D available), and $(D consume).

In definition, initial state of pool has 0 length $(D available).
It assumes that the pool is not $(D fetch)-ed yet.
*/
template isPool(Dev)
{
    enum isPool = is(typeof(
    {
        Dev d;
        alias DeviceElementType!Dev E;
        while (d.fetch())
        {
            const(E)[] buf = d.available;
            size_t n;
            d.consume(n);
        }
    }));
}

/**
Returns $(D true) if $(D Dev) is a $(I sink). It must define the
primitive $(D push).

$(D push) operation provides synchronous but non-blocking output.
*/
template isSink(Dev)
{
    enum isSink = is(typeof(
    {
        Dev d;
        alias DeviceElementType!Dev E;
        const(E)[] buf;
        do {} while (d.push(buf));
    }));
}

// seek whence...
enum SeekPos
{
    Set,
    Cur,
    End
}

/**
Check that $(D Dev) is seekable $(I source) or $(I sink).
Seekable device supports $(D seek) primitive.
*/
template isSeekable(Dev)
{
    enum isSeekable = is(typeof({
        Dev d;
        d.seek(0, SeekPos.Set);
    }()));
}

/**
Device supports both primitives of $(I source) and $(I sink).
*/
template isDevice(Dev)
{
    enum isDevice = isSource!Dev && isSink!Dev;
}


/**
Disable sink interface of $(D device).
If $(D device) has pool interface, keep it.
*/
@property auto sourced(Dev)(Dev device)
    if (isSource!Dev && isSink!Dev)
{
    struct Sourced
    {
    private:
        alias DeviceElementType!Dev E;
        Dev device;

    public:
        this(Dev d)
        {
            //move(d, device);
            device = d;
        }

        bool pull(ref E[] buf)
        {
            return device.pull(buf);
        }

      static if (isPool!Dev)
      {
        bool fetch()
        {
            return device.fetch();
        }
        @property const(E)[] available() const
        {
            return device.available;
        }
        void consume(size_t n)
        {
            device.consume(n);
        }
      }
    }

    return Sourced(device);
}

/// ditto
@property auto sourced(Dev)(Dev device)
    if (isSource!Dev && !isSink!Dev)
{
    return device;
}

version(unittest)
{
    import io.file;
    import io.buffer;
}
unittest
{
    alias typeof(File.init.sourced) InputFile;
    static assert( isSource!InputFile);
    static assert(!isSink!InputFile);

    alias typeof(InputFile.init.sourced) InputFile2;
    static assert( isSource!InputFile2);
    static assert(!isSink!InputFile2);
    static assert(is(InputFile == InputFile2));

    alias typeof(File.init.buffered.sourced) BufferedInputFile;
    static assert( isSource!BufferedInputFile);
    static assert( isPool!BufferedInputFile);
    static assert(!isSink!BufferedInputFile);
}

/**
Disable source interface of $(D device).
*/
@property auto sinked(Dev)(Dev device)
    if (isSource!Dev && isSink!Dev)
{
    struct Sinked
    {
    private:
        alias DeviceElementType!Dev E;
        Dev device;

    public:
        this(Dev d)
        {
            device = d;
        }

        bool push(ref const(E)[] buf)
        {
            return device.push(buf);
        }
    }

    return Sinked(device);
}

/// ditto
@property auto sinked(Dev)(Dev device)
    if (!isSource!Dev && isSink!Dev)
{
    return device;
}

version(unittest)
{
    import io.file;
    import io.buffer;
}
unittest
{
    alias typeof(File.init.sinked) OutputFile;
    static assert(!isSource!OutputFile);
    static assert( isSink!OutputFile);

    alias typeof(OutputFile.init.sinked) OutputFile2;
    static assert(!isSource!OutputFile2);
    static assert( isSink!OutputFile2);
    static assert(is(OutputFile == OutputFile2));

    alias typeof(File.init.buffered.sinked) BufferedOutputFile;
    static assert(!isSource!BufferedOutputFile);
    static assert(!isPool!BufferedOutputFile);
    static assert( isSink!BufferedOutputFile);
}

/**
Change device element type from $(D ubyte) to $(D E).
While device operation, remain bytes are cached.
*/
@property auto coerced(E, Dev)(Dev device)
    if ((isSource!Dev || isSink!Dev) &&
        is(DeviceElementType!Dev == ubyte))
{
    struct Coerced
    {
    private:
        Dev device;
      static if (E.sizeof > 1)
      {
        ubyte[E.sizeof] remain;
        size_t begin, end;
      }

    public:
        this(Dev d)
        {
            device = d;
        }

      static if (isSource!Dev)
        bool pull(ref E[] buf)
        {
            auto v = cast(ubyte[])buf;

          static if (E.sizeof > 1)
            if (auto r = end - begin)
            {
                v[0 .. r] = remain[begin .. end];
                v = v[r .. $];
                begin = end = 0;
            }

            auto result = device.pull(v);
            if (result)
            {
                //writefln("encoded.pull : buf = %(%02X %)", cast(ubyte[])buf);
              static if (E.sizeof > 1)
                if (auto r = E.sizeof - v.length % E.sizeof)
                {
                    remain[0..r] = v[$-r .. $];
                    v = v[0 .. $-r];
                    begin = 0, end = r;
                    v = v[0 .. $-r];
                }
                buf = cast(E[])v;
            }
            return result;
        }

      static if (isPool!Dev)
      {
        bool fetch()
        {
            return device.fetch();
        }
        @property const(E)[] available() const
        {
            return cast(const(E)[])device.available;
        }
        void consume(size_t n)
        {
            device.consume(E.sizeof * n);
        }
      }

      static if (isSink!Dev)
        bool push(ref const(E)[] data)
        {
          static if (E.sizeof > 1)
            if (auto r = end - begin)
            {
                const(ubyte)[] v = remain[begin .. end];
                auto result = device.push(v);
                begin = end - v.length;
                if (v.length)
                    return result;
            }
            auto v = cast(const(ubyte)[])data;
            auto result = device.push(v);
            data = data[$ - v.length / E.sizeof .. $];
            return result;
        }

      static if (isSeekable!Dev)
        ulong seek(long offset, SeekPos whence)
        {
            return device.seek(offset, whence);
        }
    }

    return Coerced(device);
}

version(unittest)
{
    import io.file;
    import io.buffer;
}
unittest
{
    alias typeof(File.init.coerced!char) CharFile;
    static assert(is(DeviceElementType!CharFile == char));

    alias typeof(File.init.buffered.coerced!char) BufferedFile;
    static assert(is(DeviceElementType!BufferedFile == char));
}

/**
Generate possible range interface from $(D device).
If $(D device) is a $(I pool), input range interface is available.
If $(D device) is a $(I sink), output range interface is available.
*/
@property auto ranged(Dev)(Dev device)
    if (isPool!Dev || isSink!Dev)
{
    static struct Ranged
    {
    private:
        alias DeviceElementType!Dev E;

        Dev device;
        bool eof;

    public:
        this(Dev d)
        {
            device = d;
          static if (isPool!Dev)
            eof = !device.fetch();
        }

      static if (isPool!Dev)
      {
        @property bool empty() const
        {
            return eof;
        }
        @property inout(E) front() inout
        {
            return device.available[0];
        }
        void popFront()
        {
            device.consume(1);
            if (device.available.length == 0)
                eof = !device.fetch();
        }
      }

      static if (isSink!Dev)
      {
        void put(const(E) data)
        {
            put((&data)[0 .. 1]);
        }
        void put(const(E)[] data)
        {
            while (data.length > 0)
            {
                if (!device.push(data))
                    throw new Exception("");
            }
        }
      }
    }

    return Ranged(device);
}

version(unittest)
{
    import io.file;
    import io.buffer;
    import std.algorithm;
}
unittest
{
    auto file = File(__FILE__).buffered.coerced!char.ranged;
    assert(startsWith(file, "module io.core;\n"));
}
