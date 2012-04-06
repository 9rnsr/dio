module io.filter;

import io.core;

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
        /**
        */
        this(Dev d)
        {
            //move(d, device);
            device = d;
        }

        /**
        */
        bool pull(ref E[] buf)
        {
            return device.pull(buf);
        }

      static if (isPool!Dev)
      {
        /**
        */
        bool fetch()
        {
            return device.fetch();
        }

        /// ditto
        @property const(E)[] available() const
        {
            return device.available;
        }

        /// ditto
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
        /**
        */
        this(Dev d)
        {
            //move(d, device);
            device = d;
        }

        /**
        */
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

/*
*/
@property auto coerced(E, Dev)(Dev device)
    if (isSource!Dev || isSink!Dev)
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
        /**
        */
        this(Dev d)
        {
            device = d;
        }

      static if (isSource!Dev)
        /**
        */
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
        /**
        primitives of pool.
        */
        bool fetch()
        {
            return device.fetch();
        }

        /// ditto
        @property const(E)[] available() const
        {
            return cast(const(E)[])device.available;
        }

        /// ditto
        void consume(size_t n)
        {
            device.consume(E.sizeof * n);
        }
      }

      static if (isSink!Dev)
        /**
        primitive of sink.
        */
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
        /**
        */
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

/*
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
        /**
        */
        this(Dev d)
        {
            device = d;
          static if (isPool!Dev)
            eof = !device.fetch();
        }

      static if (isPool!Dev)
      {
        /**
        primitives of input range.
        */
        @property bool empty() const
        {
            return eof;
        }

        /// ditto
        @property inout(E) front() inout
        {
            return device.available[0];
        }

        /// ditto
        void popFront()
        {
            device.consume(1);
            if (device.available.length == 0)
                eof = !device.fetch();
        }
      }

      static if (isSink!Dev)
      {
        /**
        primitive of output range.
        */
        void put(const(E) data)
        {
            put((&data)[0 .. 1]);
        }
        /// ditto
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
    assert(startsWith(file, "module io.filter;\n"));
}
