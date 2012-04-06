module io.filter;

import io.core;

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
