module io.buffer;

import io.core;
import std.algorithm : min, max;

/**
*/
@property auto buffered(Dev)(Dev device, size_t bufferSize = 4096)
    if (isSource!Dev || isSink!Dev)
{
    static struct Buffered
    {

    private:
        Dev device;
        ubyte[] buffer;
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
                static if (isDevice!Dev)    base_pos += ava_end;
                static if (isDevice!Dev)    rsv_start = rsv_end = 0;
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
        @property const(ubyte)[] available() const
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
        private @property ubyte[] usable()
        {
          static if (isDevice!Dev)
            return buffer[ava_start .. $];
          else
            return buffer[rsv_end .. $];
        }
        private @property const(ubyte)[] reserves()
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

            const(ubyte)[] rsv = buffer[rsv_start .. rsv_end];
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
        bool push(const(ubyte)[] data)
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
    assert(startsWith(file.available, "module io.buffer;\n"));
}
