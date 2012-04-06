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
