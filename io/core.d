module io.core;

/**
Returns $(D true) if $(D_PARAM D) is a $(I source). A Source must define the
primitive $(D pull).

$(D pull) operation provides synchronous but non-blocking input.
*/
template isSource(Dev)
{
    enum isSource = is(typeof(
    {
        Dev d;
        ubyte[] buf;
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
    enum isPool = is(typeof(
    {
        Dev d;
        while (d.fetch())
        {
            auto buf = d.available;
            size_t n;
            d.consume(n);
        }
    }));
}

/**
Returns $(D true) if $(D_PARAM D) is a $(I sink). A Source must define the
primitive $(D push).

$(D push) operation provides synchronous but non-blocking output.
*/
template isSink(Dev)
{
    enum isSink = is(typeof(
    {
        Dev d;
        const(ubyte)[] buf;
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
Check that $(D_PARAM D) is seekable source or sink.
Seekable device supports $(D seek) primitive.
*/
template isSeekable(D)
{
    enum isSeekable = is(typeof({
        D d;
        d.seek(0, SeekPos.Set);
    }()));
}

/**
Device supports both primitives of source and sink.
*/
template isDevice(D)
{
	enum isDevice = isSource!D && isSink!D;
}
