module io.socket;

import std.socket;
import std.typecons : scoped;

/**
Simple wrapper for $(D std.socket.TcpSocket) class.
*/
struct TcpSocket
{
    std.socket.TcpSocket socket;
    size_t* pRefCounter;

    /**
    */
    this(string hostname, ushort port)
    {
        auto ih = scoped!InternetHost();
        if (!ih.getHostByName(hostname))
            throw new HostException("unresolved host name");
        this(new InternetAddress(ih.addrList[$-1], port));

        pRefCounter = new size_t;
        *pRefCounter = 1;
    }
    /**
    */
    this(InternetAddress iaddr)
    {
        socket = new std.socket.TcpSocket(iaddr);
        socket.blocking = false;
    }
    this(this)
    {
        if (pRefCounter)
            ++(*pRefCounter);
    }
    ~this()
    {
        if (pRefCounter)
        {
            if (--(*pRefCounter) == 0)
            {
                if (socket)
                    socket.close();
            }
        }
    }

    /**
    */
    bool pull(ref ubyte[] buf)
    {
        if (buf.length == 0)
            return false;

        sizediff_t n = socket.receive(buf[]);
        if (n < 0)
            return wouldHaveBlocked() ? true : false;
        if (n == 0)
            return false;
        assert(n <= buf.length);
        buf = buf[n .. $];
        return true;
    }

    /**
    */
    bool push(ref const(ubyte)[] buf)
    {
        if (buf.length == 0)
            return false;

        sizediff_t n = socket.send(buf);
        if (n < 0)
            return wouldHaveBlocked() ? true : false;
        assert(n <= buf.length);
        buf = buf[n .. $];
        return true;
    }
}

unittest
{
  softUnittest!SocketException({
    auto sock = TcpSocket("www.digitalmars.com", 80);
    const(ubyte)[] sendbuf = cast(const(ubyte)[])"GET / HTTP/1.0\r\n\r\n";
    while (sock.push(sendbuf)){}

    ubyte[4096] buffer;
    ubyte[] recvbuf = buffer[];
    while (sock.pull(recvbuf)) {}
    recvbuf = buffer[0 .. $-recvbuf.length];
  });
}

version(unittest)
{
    import io.core;
    import io.socket;
    import std.array : array;
}
unittest
{
  softUnittest!SocketException({
    auto sock = TcpSocket("dlang.org", 80);
    auto wr = sock.sinked /*.buffered*/.coerced!char.ranged;
    auto rd = sock.sourced  .buffered  .coerced!char.ranged;

    wr.put("GET / HTTP/1.0\r\n\r\n");
    auto recvbuf = rd.array();
  });
}

// Print a message on exception instead of failing the unittest.
private void softUnittest(E)(void delegate() test, string fn = __FILE__, size_t ln = __LINE__)
{
    import std.exception;
    if (auto e = collectException!E(test()))
    {
        static import std.stdio;
        std.stdio.writefln(" --- %s(%d) test fails depending on environment ---", fn, ln);
        std.stdio.writefln(" (%s)", e);
    }
}
