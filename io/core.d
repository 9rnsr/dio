module io.core;

/**
Returns $(D true) if $(D Dev) is a $(I source). A Source must define the
primitive $(D pull).

$(D pull) operation provides synchronous but non-blocking input.
*/
template isSource(Dev)
{
    enum isSource = .isSource!(Dev, DeviceElementType!Dev);
}
/// ditto
template isSource(Dev, E = ubyte)
{
    enum isSource = is(typeof(
    {
        Dev d;
        E[] buf;
        while (d.pull(buf)) {}
    }));
}

/**
In definition, initial state of pool has 0 length $(D available).$(BR)
You can assume that pool is not $(D fetch)-ed yet.$(BR)
定義では、poolの初期状態は長さ0の$(D available)を持つ。$(BR)
これはpoolがまだ一度も$(D fetch)されたことがないと見なすことができる。$(BR)
*/
template isPool(Dev)
{
    enum isPool = .isPool!(Dev, DeviceElementType!Dev);
}
/// ditto
template isPool(Dev, E)
{
    enum isPool = is(typeof(
    {
        Dev d;
        while (d.fetch())
        {
            const(E)[] buf = d.available;
            size_t n;
            d.consume(n);
        }
    }));
}

/**
Returns $(D true) if $(D Dev) is a $(I sink). A Source must define the
primitive $(D push).

$(D push) operation provides synchronous but non-blocking output.
*/
template isSink(Dev)
{
    enum isSink = .isSink!(Dev, DeviceElementType!Dev);
}
/// ditto
template isSink(Dev, E)
{
    enum isSink = is(typeof(
    {
        Dev d;
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
Check that $(D Dev) is seekable source or sink.
Seekable device supports $(Dev seek) primitive.
*/
template isSeekable(Dev)
{
    enum isSeekable = is(typeof({
        Dev d;
        d.seek(0, SeekPos.Set);
    }()));
}

/**
Device supports both primitives of source and sink.
*/
template isDevice(Dev)
{
    enum isDevice = .isDevice!(Dev, DeviceElementType!Dev);
}
/// ditto
template isDevice(Dev, E)
{
    enum isDevice = isSource!(Dev, E) && isSink!(Dev, E);
}

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
