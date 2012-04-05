module io.file;

import io.core;
version(Windows)
{
  import core.sys.windows.windows, std.windows.syserror;
  enum : uint { ERROR_BROKEN_PIPE = 109 }
}

debug
{
  import std.stdio : writeln, writefln;
}

/**
File is seekable device
*/
struct File
{
    import std.utf;
    import std.typecons;
private:
    HANDLE hFile;
    size_t* pRefCounter;

public:
    /**
    */
    this(HANDLE h)
    {
        hFile = h;
        pRefCounter = new size_t;
        *pRefCounter = 1;
    }
    this(string fname, in char[] mode = "r")
    {
        int share = FILE_SHARE_READ | FILE_SHARE_WRITE;
        int access = void;
        int createMode = void;

        // fopenにはOPEN_ALWAYSに相当するModeはない？
        switch (mode)
        {
            case "r":
                access = GENERIC_READ;
                createMode = OPEN_EXISTING;
                break;
            case "w":
                access = GENERIC_WRITE;
                createMode = CREATE_ALWAYS;
                break;
            case "a":
                assert(0);

            case "r+":
                access = GENERIC_READ | GENERIC_WRITE;
                createMode = OPEN_EXISTING;
                break;
            case "w+":
                access = GENERIC_READ | GENERIC_WRITE;
                createMode = CREATE_ALWAYS;
                break;
            case "a+":
                assert(0);

            // do not have binary mode(binary access only)
        //  case "rb":
        //  case "wb":
        //  case "ab":
        //  case "rb+": case "r+b":
        //  case "wb+": case "w+b":
        //  case "ab+": case "a+b":
            default:
                break;
        }

        hFile = CreateFileW(
            std.utf.toUTFz!(const(wchar)*)(fname), access, share, null, createMode, 0, null);
        pRefCounter = new size_t();
        *pRefCounter = 1;
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
                //delete pRefCounter;   // trivial: delegate management to GC.
                CloseHandle(cast(HANDLE)hFile);
            }
            //pRefCounter = null;       // trivial: do not need
        }
    }

    /**
    Request n number of elements.
    $(D buf) is treated as an output range.
    Returns:
        $(UL
            $(LI $(D true ) : You can request next pull.)
            $(LI $(D false) : No element exists.))
    */
    bool pull(ref ubyte[] buf)
    {
        DWORD size = void;
        debug std.stdio.writefln("ReadFile : buf.ptr=%08X, len=%s", cast(uint)buf.ptr, buf.length);
        if (ReadFile(hFile, buf.ptr, buf.length, &size, null))
        {
            debug(File)
                std.stdio.writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
                    cast(uint)hFile, buf.length, size, GetLastError());
            buf = buf[size.. $];
            return (size > 0);  // valid on only blocking read
        }
        else
        {
            switch (GetLastError())
            {
                case ERROR_BROKEN_PIPE:
                    return false;
                default:
                    break;
            }

            debug(File)
                std.stdio.writefln("pull ng : hFile=%08X, size=%s, GetLastError()=%s",
                    cast(uint)hFile, size, GetLastError());
            throw new Exception("pull(ref buf[]) error");

        //  // for overlapped I/O
        //  eof = (GetLastError() == ERROR_HANDLE_EOF);
        }
    }

    /**
    */
    bool push(ref const(ubyte)[] buf)
    {
        DWORD size = void;
        if (WriteFile(hFile, buf.ptr, buf.length, &size, null))
        {
            buf = buf[size .. $];
            return true;    // (size == buf.length);
        }
        else
        {
            throw new Exception("push error");  //?
        }
    }

    /**
    */
    ulong seek(long offset, SeekPos whence)
    {
      version(Windows)
      {
        int hi = cast(int)(offset>>32);
        uint low = SetFilePointer(hFile, cast(int)offset, &hi, whence);
        if ((low == INVALID_SET_FILE_POINTER) && (GetLastError() != 0))
            throw new /*Seek*/Exception("unable to move file pointer");
        ulong result = (cast(ulong)hi << 32) + low;
      }
      else version (Posix)
      {
        auto result = lseek(hFile, cast(int)offset, whence);
        if (result == cast(typeof(result))-1)
            throw new /*Seek*/Exception("unable to move file pointer");
      }
      else
      {
        static assert(false, "not yet supported platform");
      }

        return cast(ulong)result;
    }
}
static assert(isSource!File);
static assert(isSink!File);

version(unittest)
{
    import std.algorithm;
}
unittest
{
    auto file = File(__FILE__);
    ubyte[] buf = new ubyte[64];
    ubyte[] b = buf;
    while (file.pull(b)) {}
    buf = buf[0 .. $-b.length];

    assert(buf.length == 64);
    debug std.stdio.writefln("buf = [%(%02x %)]\n", buf);
    assert(startsWith(buf, "module io.file;\n"));
}
