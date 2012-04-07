//io.core module;
/**
core module for new I/O
*/
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
template Sourced(Dev)
{
    alias typeof((Dev* d = null){ return (*d).sourced; }()) Sourced;
}

/// ditto
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
template Sinked(Dev)
{
    alias typeof((Dev* d = null){ return (*d).sinked; }()) Sinked;
}

/// ditto
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
*/
template Buffered(Dev)
{
    alias typeof((Dev* d){ return (*d).buffered; }()) Buffered;
}

/// ditto
@property auto buffered(Dev)(Dev device, size_t bufferSize = 4096)
    if (isSource!Dev || isSink!Dev)
{
    static struct Buffered
    {
        import std.algorithm : min, max;

    private:
        alias DeviceElementType!Dev E;

        Dev device;
        E[] buffer;
        static if (isSink  !Dev) size_t rsv_start = 0, rsv_end = 0;
        static if (isSource!Dev) size_t ava_start = 0, ava_end = 0;
        static if (isDevice!Dev) long base_pos = 0;

    public:
        /**
        */
        this(Dev d, size_t bufferSize)
        {
            device = d;
            buffer.length = bufferSize;
        }

      static if (isSink!Dev)
        ~this()
        {
            while (reserves.length > 0)
                flush();
        }

      static if (isSource!Dev)
        /**
        primitives of source.
        */
        bool pull(ref E[] buf)
        {
            auto av = available;
            if (buf.length < av.length)
            {
                buf[] = av[0 .. buf.length];
                consume(buf.length);
                buf = buf[$ .. $];
                return true;
            }
            else
            {
                buf[0 .. av.length] = av[];
                consume(av.length);
                return fetch();
            }
        }

      static if (isSource!Dev)
        /**
        primitives of pool.
        */
        bool fetch()
        body
        {
          static if (isDevice!Dev)
            bool empty_reserves = (reserves.length == 0);
          else
            enum empty_reserves = true;

            if (empty_reserves && available.length == 0)
            {
                static if (isDevice!Dev) base_pos += ava_end;
                static if (isDevice!Dev) rsv_start = rsv_end = 0;
                                         ava_start = ava_end = 0;
            }

          static if (isDevice!Dev)
            device.seek(base_pos + ava_end, SeekPos.Set);

            auto v = buffer[ava_end .. $];
            auto result =  device.pull(v);
            if (result)
            {
                ava_end = buffer.length - v.length;
            }
            return result;
        }

      static if (isSource!Dev)
        /// ditto
        @property const(E)[] available() const
        {
            return buffer[ava_start .. ava_end];
        }

      static if (isSource!Dev)
        /// ditto
        void consume(size_t n)
        in { assert(n <= available.length); }
        body
        {
            ava_start += n;
        }

      static if (isSink!Dev)
      {
        /*
        primitives of output pool?
        */
        private @property E[] usable()
        {
          static if (isDevice!Dev)
            return buffer[ava_start .. $];
          else
            return buffer[rsv_end .. $];
        }
        private @property const(E)[] reserves()
        {
            return buffer[rsv_start .. rsv_end];
        }
        // ditto
        private void commit(size_t n)
        {
          static if (isDevice!Dev)
          {
            assert(ava_start + n <= buffer.length);
            ava_start += n;
            ava_end = max(ava_end, ava_start);
            rsv_end = ava_start;
          }
          else
          {
            assert(rsv_end + n <= buffer.length);
            rsv_end += n;
          }
        }
      }

      static if (isSink!Dev)
        /**
        flush buffer.
        primitives of output pool?
        */
        bool flush()
        in { assert(reserves.length > 0); }
        body
        {
          static if (isDevice!Dev)
            device.seek(base_pos + rsv_start, SeekPos.Set);

            const(E)[] rsv = buffer[rsv_start .. rsv_end];
            auto result = device.push(rsv);
            if (result)
            {
                rsv_start = rsv_end - rsv.length;

              static if (isDevice!Dev)
                bool empty_available = (available.length == 0);
              else
                enum empty_available = true;

                if (reserves.length == 0 && empty_available)
                {
                    static if (isDevice!Dev)    base_pos += ava_end;
                    static if (isDevice!Dev)    ava_start = ava_end = 0;
                                                rsv_start = rsv_end = 0;
                }
            }
            return result;
        }

      static if (isSink!Dev)
        /**
        primitive of sink.
        */
        bool push(const(E)[] data)
        {
        //  return device.push(data);

            while (data.length > 0)
            {
                if (usable.length == 0)
                    if (!flush()) goto Exit;
                auto len = min(data.length, usable.length);
                usable[0 .. len] = data[0 .. len];
                data = data[len .. $];
                commit(len);
            }
            if (usable.length == 0)
                if (!flush()) goto Exit;

            return true;
          Exit:
            return false;
        }
    }

    return Buffered(device, bufferSize);
}

version(unittest)
{
    import io.file;
    import std.algorithm;
}
unittest
{
    auto file = File(__FILE__).buffered;
    file.fetch();
    assert(startsWith(file.available, "//io.core module;\n"));
}

/**
Change device element type from $(D ubyte) to $(D E).
While device operation, remain bytes are cached.
*/
template Coerced(E, Dev)
{
    alias typeof((Dev* d = null){ return (*d).coerced!E; }()) Coerced;
}

/// ditto
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
template Ranged(Dev)
{
    alias typeof((Dev* d = null){ return (*d).ranged; }()) Ranged;
}

/// ditto
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
        }

      static if (isPool!Dev)
      {
        @property bool empty()
        {
            /* Delay fetching until we really need inputs. */
            if (device.available.length == 0)
                eof = !device.fetch();
            return eof;
        }
        @property E front()
        {
            while (device.available.length == 0 && !eof)
                eof = !device.fetch();
            if (eof)
                throw new Exception("Unexpected failure of fetching value form underlying device");
            return device.available[0];
        }
        void popFront()
        {
            device.consume(1);
            while (device.available.length == 0 && !eof)
                eof = !device.fetch();
            assert(eof || device.available.length > 0);
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
/+
      static if (is(typeof(device.flush())))
        bool flush()
        {
            return device.flush();
        }
+/
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
    assert(startsWith(file, "//io.core module;\n"));
}
