/*
Source,Pool,Sinkの3つを基本I/Fと置く
→Buffered-sinkは明示的に扱えるようにする？

それぞれがやり取りする要素の型は任意だが、Fileはubyteをやり取りする
(D言語的にはvoid[]でもいいかも→Rangeを考えるとやりたくない)

基本的なFilter
・Encodedはubyteを任意型にcastする機能を提供する
・Bufferedはバッファリングを行う

filter chainのサポート
Bufferedの例:
	(1) 構築済みのdeviceをwrapする
		auto f = File("test.txt", "r");
		auto sf = sinked(f);
		auto bf = bufferd(sf, 2048);
	(2) 静的に決定したfilterを構築する
		alias Buffered!Sinked BufferedSink;
		auto bf = BufferedSink!File("test.txt", "r", 2048)

*/
module xtk.device;

import std.array, std.algorithm, std.range, std.traits;
import std.exception;
import std.stdio;
version(Windows) import xtk.windows;

import xtk.format : format;

import xtk.workaround;

debug = Workarounds;
debug (Workarounds)
{
	debug = Issue5661;	// replace of std.algorithm.move
	debug = Issue5663;	// replace of std.array.Appender.put

	debug (Issue5661)	alias issue5661fix_move move;
	debug (Issue5663)	alias issue5663fix_Appender Appender;
}

import xtk.traits : isTemplate;

/**
Returns $(D true) if $(D_PARAM D) is a $(I source). A Source must define the
primitive $(D pull).
*/
template isSource(D)
{
	enum isSource = __traits(hasMember, D, "pull");
}

///ditto
template isSource(D, E)
{
	enum isSource = is(typeof({
		D d;
		E[] buf;
		while (d.pull(buf)){}
	}()));
}

/**
In definition, initial state of pool has 0 length $(D available).$(BR)
You can assume that pool is not $(D fetch)-ed yet.$(BR)
定義では、poolの初期状態は長さ0の$(D available)を持つ。$(BR)
これはpoolがまだ一度も$(D fetch)されたことがないと見なすことができる。$(BR)
*/
template isPool(D)
{
	enum isPool = is(typeof({
		D d;
		while (d.fetch())
		{
			auto buf = d.available;
			size_t n;
			d.consume(n);
		}
	}()));
}

/**
Returns $(D true) if $(D_PARAM D) is a $(I sink). A Source must define the
primitive $(D push).
*/
template isSink(D)
{
	enum isSink = __traits(hasMember, D, "push");
}

///ditto
template isSink(D, E)
{
	enum isSink = is(typeof({
		D d;
		const(E)[] buf;
		do{}while (d.push(buf))
	}()));
}

/**
Device supports both primitives of source and sink.
*/
template isDevice(D)
{
	enum isDevice = isSource!D && isSink!D;
}

/**
Retruns element type of device.
Naming:
	More good naming.
*/
template UnitType(D)
	if (isSource!D || isPool!D || isSink!D)
{
	static if (isSource!D)
		alias Unqual!(typeof(ParameterTypeTuple!(typeof(D.init.pull))[0].init[0])) UnitType;
	static if (isPool!D)
		alias Unqual!(typeof(D.init.available[0])) UnitType;
	static if (isSink!D)
	{
		alias Unqual!(typeof(ParameterTypeTuple!(typeof(D.init.push))[0].init[0])) UnitType;
	}
}

// seek whence...
enum SeekPos {
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
		pRefCounter = new size_t();
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
		//	case "rb":
		//	case "wb":
		//	case "ab":
		//	case "rb+":	case "r+b":
		//	case "wb+":	case "w+b":
		//	case "ab+":	case "a+b":
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
		if (pRefCounter) ++(*pRefCounter);
	}
	~this()
	{
		if (pRefCounter)
		{
			if (--(*pRefCounter) == 0)
			{
				//delete pRefCounter;	// trivial: delegate management to GC.
				CloseHandle(cast(HANDLE)hFile);
			}
			//pRefCounter = null;		// trivial: do not need
		}
	}

	/**
	Request n number of elements.
	Returns:
		$(UL
			$(LI $(D true ) : You can request next pull.)
			$(LI $(D false) : No element exists.))
	*/
	bool pull(ref ubyte[] buf)
	{
		DWORD size = void;
		debug writefln("ReadFile : buf.ptr=%08X, len=%s", cast(uint)buf.ptr, len);
		if (ReadFile(hFile, buf.ptr, buf.length, &size, null))
		{
			debug(File)
				writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
					cast(uint)hFile, buf.length, size, GetLastError());
			buf = buf[0 .. size];
			return (size > 0);	// valid on only blocking read
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

			//debug(File)
				writefln("pull ng : hFile=%08X, size=%s, GetLastError()=%s",
					cast(uint)hFile, size, GetLastError());
			throw new Exception("pull(ref buf[]) error");

		//	// for overlapped I/O
		//	eof = (GetLastError() == ERROR_HANDLE_EOF);
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
			return true;	// (size == buf.length);
		}
		else
		{
			throw new Exception("push error");	//?
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
	  else
	  version (Posix)
	  {
		auto result = lseek(hFile, cast(int)offset, whence);
		if (result == cast(typeof(result))-1)
			throw new /*Seek*/Exception("unable to move file pointer");
	  }
		return cast(ulong)result;
	}
}
static assert(isSource!File);
static assert(isSink!File);
static assert(isDevice!File);


/**
Modifiers to limit primitives of $(D_PARAM D) to source.
*/
Sourced!D sourced(D)(D device)
{
	return Sourced!D(device);
}

/// ditto
template Sourced(alias D) if (isTemplate!D)
{
	template Sourced(Args...)
	{
		alias .Sourced!(D!Args) Sourced;
	}
}

/// ditto
struct Sourced(D)
	if (isSource!D && isSink!D)
{
private:
	alias UnitType!D E;
	D device;

public:
	/**
	*/
	this(Device)(Device d) if (is(Device == D))
	{
		move(d, device);
	}
	/**
	Delegate construction to $(D_PARAM D).
	*/
	this(A...)(A args)
	{
		__ctor(D(args));
	}

	/**
	*/
	bool pull(ref E[] buf)
	{
		return device.pull(buf);
	}
}

// ditto
template Sourced(D) if (isSource!D && !isSink!D)
{
	alias D Sourced;
}


/**
Modifiers to limit primitives of $(D_PARAM D) to sink.
*/
Sinked!D sinked(D)(D device)
{
	return Sinked!D(device);
}

/// ditto
template Sinked(alias D) if (isTemplate!D)
{
	template Sinked(Args...)
	{
		alias .Sinked!(D!Args) Sinked;
	}
}

/// ditto
struct Sinked(D)
	if (isSource!D && isSink!D)
{
private:
	alias UnitType!D E;
	D device;

public:
	/**
	*/
	this(Device)(Device d) if (is(Device == D))
	{
		move(d, device);
	}
	/**
	Delegate construction to $(D_PARAM D).
	*/
	this(A...)(A args)
	{
		__ctor(D(args));
	}

	/**
	*/
	bool push(ref const(E)[] buf)
	{
		return device.push(buf);
	}
}

// ditto
template Sinked(D) if (!isSource!D && isSink!D)
{
	alias D Sinked;
}


/**
*/
Encoded!(Device, E) encoded(E, Device)(Device device)
{
	return typeof(return)(move(device));
}

/// ditto
template Encoded(alias D) if (isTemplate!D)
{
	template Encoded(Args...)
	{
		alias .Encoded!(D!Args) Encoded;
	}
}

/// ditto
struct Encoded(Device, E)
{
private:
	Device device;

public:
	/**
	*/
	this(D)(D d) if (is(D == Device))
	{
		move(d, device);
	}
	/**
	*/
	this(A...)(A args)
	{
		__ctor(Device(args));
	}

  static if (isSource!Device)
	/**
	*/
	bool pull(ref E[] buf)
	{
		auto v = cast(ubyte[])buf;
		auto result = device.pull(v);
		if (result)
		{
//			writefln("encoded.pull : buf = %(%02X %)", cast(ubyte[])buf);
			static if (E.sizeof > 1) assert(v.length % E.sizeof == 0);
			buf = cast(E[])v;
		}
		return result;
	}

  static if (isPool!Device)
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

  static if (isSink!Device)
	/**
	primitive of sink.
	*/
	bool push(ref const(E)[] data)
	{
		auto v = cast(const(ubyte)[])data;
		auto result = device.push(v);
		static if (E.sizeof > 1) assert(v.length % E.sizeof == 0);
		data = data[$ - v.length / E.sizeof .. $];
		return result;
	}

  static if (isSeekable!Device)
	/**
	*/
	ulong seek(long offset, SeekPos whence)
	{
		return device.seek(offset, whence);
	}
}


/**
*/
Buffered!(D) buffered(D)(D device, size_t bufferSize = 4096)
{
	return typeof(return)(move(device), bufferSize);
}

/// ditto
template Buffered(alias D) if (isTemplate!D)
{
	template Buffered(Args...)
	{
		alias .Buffered!(D!Args) Buffered;
	}
}

/// ditto
struct Buffered(D)
	if (isSource!D || isSink!D)
{
private:
	alias UnitType!D E;
	D device;
	E[] buffer;
	static if (isSink  !D) size_t rsv_start = 0, rsv_end = 0;
	static if (isSource!D) size_t ava_start = 0, ava_end = 0;
	static if (isDevice!D) long base_pos = 0;

public:
	/**
	*/
	this(Device)(Device d, size_t bufferSize) if (is(Device == D))
	{
		move(d, device);
		buffer.length = bufferSize;
	}
	/**
	*/
	this(A...)(A args, size_t bufferSize)
	{
		__ctor(D(args), bufferSize);
	}

  static if (isSink!D)
	~this()
	{
		while (reserves.length > 0)
			flush();
	}

  static if (isSource!D)
	/**
	primitives of pool.
	*/
	bool fetch()
	body
	{
	  static if (isDevice!D)
		bool empty_reserves = (reserves.length == 0);
	  else
		enum empty_reserves = true;

		if (empty_reserves && available.length == 0)
		{
			static if (isDevice!D)	base_pos += ava_end;
			static if (isDevice!D)	rsv_start = rsv_end = 0;
									ava_start = ava_end = 0;
		}

	  static if (isDevice!D)
		device.seek(base_pos + ava_end, SeekPos.Set);

		auto v = buffer[ava_end .. $];
		auto result =  device.pull(v);
		if (result)
		{
			ava_end += v.length;
		}
		return result;
	}

  static if (isSource!D)
	/// ditto
	@property const(E)[] available() const
	{
		return buffer[ava_start .. ava_end];
	}

  static if (isSource!D)
	/// ditto
	void consume(size_t n)
	in { assert(n <= available.length); }
	body
	{
		ava_start += n;
	}

  static if (isSink!D)
  {
	/*
	primitives of output pool?
	*/
	private @property E[] usable()
	{
	  static if (isDevice!D)
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
	  static if (isDevice!D)
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

  static if (isSink!D)
	/**
	flush buffer.
	primitives of output pool?
	*/
	bool flush()
	in { assert(reserves.length > 0); }
	body
	{
	  static if (isDevice!D)
		device.seek(base_pos + rsv_start, SeekPos.Set);

		auto rsv = buffer[rsv_start .. rsv_end];
		auto result = device.push(rsv);
		if (result)
		{
			rsv_start = rsv_end - rsv.length;

		  static if (isDevice!D)
			bool empty_available = (available.length == 0);
		  else
			enum empty_available = true;

			if (reserves.length == 0 && empty_available)
			{
				static if (isDevice!D)	base_pos += ava_end;
				static if (isDevice!D)	ava_start = ava_end = 0;
											rsv_start = rsv_end = 0;
			}
		}
		return result;
	}

  static if (isSink!D)
	/**
	primitive of sink.
	*/
	bool push(const(E)[] data)
	{
	//	return device.push(data);

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


/*shared */static this()
{
	din  = Sourced!File(GetStdHandle(STD_INPUT_HANDLE));
	dout = Sinked !File(GetStdHandle(STD_OUTPUT_HANDLE));
	derr = Sinked !File(GetStdHandle(STD_ERROR_HANDLE));
}
//__gshared
//{
	Sourced!File din;
	Sinked !File dout;
	Sinked !File derr;
//}


/**
Convert pool to input range.
Convert sink to output range.
Design:
	Rangeはコンストラクト直後にemptyが取れる、つまりPoolでいうfetch済みである必要があるが、
	Poolは未fetchであることが必要なので互いの要件が矛盾する。よってPoolはInputRangeを
	同時に提供できないため、これをWrapするRangedが必要となる。
Design:
	OutputRangeはデータがすべて書き込まれるまでSinkのpushを繰り返す。

Design:
	RangedはSourceを直接Rangeには変換しない。
	これはバッファリングが必要になるためで、これはBufferedが担当する。
	(バッファリングのサイズはUserSideが解決するべきと考え、deviceモジュールは暗黙に面倒を見ない)
*/
Ranged!D ranged(D)(D device)
{
  static if (isDeviced!D)
	return device.original;
  else
	return Ranged!D(move(device));
}

/// ditto
template Ranged(alias D) if (isTemplate!D)
{
	template Ranged(Args...)
	{
		alias .Ranged!(D!Args) Ranged;
	}
}

/// ditto
struct Ranged(D)
	if (!isDeviced!D && (isPool!D || isSink!D))
{
private:
	alias D Original;
	alias device original;

	alias UnitType!D E;
	D device;
	bool eof;

public:
	/**
	*/
	this(Device)(Device d) if (is(Device == D))
	{
		move(d, device);
	  static if (isPool!D)
		eof = !device.fetch();
	}
	/**
	*/
	this(A...)(A args)
	{
		__ctor(D(args));
	}

  static if (isPool!D)
  {
	/**
	primitives of input range.
	*/
	@property bool empty() const
	{
		return eof;
	}

	/// ditto
	@property E front()
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

  static if (isSink!D)
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
unittest
{
	scope(failure) std.stdio.writefln("unittest@%s:%s failed", __FILE__, __LINE__);

	auto fname = "dummy.txt";
	{	auto r = ranged(Sinked!File(fname, "w"));
		ubyte[] data = [1,2,3];
		r.put(data);
	}
	{	auto r = ranged(buffered(Sourced!File(fname, "r"), 1024));
		auto i = 1;
		foreach (e; r)
		{
			static assert(is(typeof(e) == ubyte));
			assert(e == i++);
		}
	}
	std.file.remove(fname);
}

// ditto
template Ranged(D) if (isDeviced!D)
{
	alias D.Original Ranged;
}
unittest
{
	int[] a;
	auto a2 = ranged(deviced(a));
	static assert(is(typeof(a2) == int[]));
}

/*
*/
template isRanged(R)
{
	static if (is(R _ : Ranged!D, D))
		enum isRanged = true;
	else
		enum isRanged = false;
}
unittest
{
	static struct DummySink
	{
		bool push(ref const(int)[] data){ return false; }
	}
	static assert(isSink!DummySink);

	auto d = DummySink();
	auto r = ranged(d);
	static assert(isRanged!(typeof(r)));
}


/**
converts range to device (source, pool, sink)
Design:
	$(D Deviced) can receive an array, but doesn't treat $(D ElementType!(E[])),
	but also $(D E).
*/
Deviced!R deviced(R)(R range)
{
  static if (isRanged!R)
	return range.original;
  else
	return Deviced!R(move(range));
}

/// ditto
template Deviced(alias D) if (isTemplate!D)
{
	template Deviced(Args...)
	{
		alias .Deviced!(D!Args) Deviced;
	}
}

/// ditto
struct Deviced(R)
	if (!isRanged!R && (isInputRange!R || __traits(hasMember, R, "put")))
{
private:
	alias R Original;
	alias range original;

	R range;
	static if (isInputRange!R)
	{
		static if (isArray!R)
			alias typeof(R.init[0]) E;
		else
			alias ElementType!R E;
	}

public:
	this(R)(R r) if (is(R == R))
	{
		move(r, range);
	}
	this(A...)(A args)
	{
		__ctor(R(args));
	}

  static if (isInputRange!R)
  {
	/**
	*/
	bool pull(ref E[] data)
	{
		if (range.empty)
			return false;
		else
		{
		  static if (isArray!R)
		  {
			auto len = min(range.length, data.length);
			data[0 .. len] = range[0 .. len];
			range = range[len .. $];
		  }
		  else
		  {
			while (data.length && !range.empty)
			{
				data[0] = range.front;
				range.popFront();
			}
		  }
			return true;
		}
	}
  }
  static if (isArray!R)
  {
	/**
	*/
	@property const(E)[] available() const
	{
		return range;
	}
	/**
	*/
	bool fetch()
	{
		return !range.empty;
	}
	/**
	*/
	void consume(size_t n)
	{
		range.popFrontN(n);
	}
  }

	bool push(E)(ref const(E)[] data)
		if (isOutputRange!(R, E))
	{
		if (range.empty)
			return false;

		int written;
		static if (isArray!R)
		{
			written = (data.length > range.length ? range.length : data.length);
			range[0 .. written] = data[0 .. written];
			range = range[written .. $];
		}
		else
		{
			while (!range.empty && !data.empty)
			{
				put(range, data.front);
				++written;
			}
		}
		data = data[written .. $];

		return true;
	}
}
unittest
{
	scope(failure) std.stdio.writefln("unittest@%s:%s failed", __FILE__, __LINE__);

	auto a = [1, 2, 3, 4, 5];
	auto d = deviced(a);

	auto x = [10, 20];
	d.push(x);
	assert(x == []);
	assert(d.available == [3, 4, 5]);

	d.consume(2);
	assert(d.fetch() == true);
	assert(d.available == [5]);

	auto y = [50, 60];
	assert(d.push(y));
	assert(y == [60]);

	assert(d.fetch() == false);
	auto z = [70,80];
	assert(d.push(z) == false);
	assert(z == [70, 80]);

	assert(a == [10, 20, 3, 4, 50]);
}

// ditto
template Deviced(R) if (isRanged!R)
{
	alias R.Original Deviced;
}
unittest
{
	static struct DummySink
	{
		bool push(ref const(int)[] data){ return false; }
	}

	auto d = DummySink();
	auto d2 = deviced(ranged(d));
	static assert(is(typeof(d2) == DummySink));
}

/*
*/
template isDeviced(D)
{
	static if (is(D _ == Deviced!R, R))
		enum isDeviced = true;
	else
		enum isDeviced = false;
}


version(Windows)
{
	enum NativeNewLine = "\r\n";
}
else version(Posix)
{
	enum NativeNewLine = "\n";
}
else
{
	static assert(0, "not yet supported");
}


ByteMap!(T, Mem) bytemap(T, Mem)(Mem mem)
{
	return ByteMap!(T, Mem)(mem);
}

struct ByteMap(T, Mem)
	if (is(T == struct))
{
	Mem mem;

  static if (is(Mem == ubyte[]))
  {
	auto opDispatch(string s, A...)(A args)
	{
		return mixin("(cast(T*)mem.ptr)." ~ mem);
	}
  }
  else
  {
	static assert(is(typeof(mem[0]) == ubyte));

	auto opDispatch(string s, A...)(A args)
	{
		alias typeof(mixin("T.init." ~ s)) R;
		enum ofs = mixin("T.init." ~ s ~ ".offsetof");
		enum siz = mixin("T.init." ~ s ~ ".sizeof");

		static if (is(R == struct))
		{
			return bytemap!R(mem[ofs .. ofs+siz]);
		}
		else
		{
			ubyte[siz] ret;
			foreach (i; 0 .. siz)
				ret[i] = mem[ofs + i];
			return *(cast(typeof(mixin("T.init." ~ s))*)&ret[0]);
		}
	}
  }
}


Slicer!D slicer(D)(D device, size_t chunkSize)
{
	return Slicer!D(move(device), chunkSize);
}

/**
*/
struct Slicer(D)
	if (isSource!D)
{
private:
	alias UnitType!D E;
	D device;
	Chunk* head;
	size_t frontOffset;
	Chunk terminator;
	size_t fetchedLen;
	@property size_t chunkSize() const { return terminator.size; }
	@property Chunk* lastChunk() { return (head !is null) ? terminator.next : null; }
	@property const(Chunk*) lastChunk() const { return (head !is null) ? terminator.next : null; }
	@property void lastChunk(Chunk* chunk) { return terminator.next = chunk; }

	static struct Chunk
	{
		Chunk* next;
		size_t size;
		E[0] _buf;

		@property E[] buf()
		{
			return (cast(E*)(cast(void*)&next + (_buf.offsetof - next.offsetof)))[0 .. size];
		}
	}

	static struct Slice
	{
	private:
		Chunk* chunk;
		size_t ofs;
		size_t len;

	public:
		@property size_t length() const
		{
			return len;
		}

		@property bool empty() const
		{
			return len == 0;
		}
		@property E front()
		in{ assert(!empty); }
		body
		{
			return chunk.buf[ofs];
		}
		void popFront()
		in{ assert(!empty); }
		body
		{
			--len;
			++ofs;
			if (len && ofs == chunk.size)
			{
				chunk = chunk.next;
				ofs = 0;
			}
		}

		ref E opIndex(size_t n)
		{
			return getChunk(n).buf[(ofs + n) % chunk.size];
		}

		Slice opSlice(size_t b, size_t e)
		{
			return Slice(getChunk(b), (ofs + b) % chunk.size, e - b);
		}

	private:
		Chunk* getChunk(size_t n)
		{
			enforce(n <= len);
			auto nth = ofs + n;

		//	if (nth < chunk.size)
		//	{
		//		return chunk;
		//	}
		//	else
		//	{
				auto nth_n = nth / chunk.size;

				auto c = chunk;
				auto i = nth_n;
				while (i)
				{
					--i;
					c = c.next;
					assert(c !is null);
				}

				return c;
		//	}
		}
	}


public:
	this(Device)(Device d, size_t chunkSize) if (is(Device == D))
	{
		move(d, device);
		terminator.size = chunkSize;

		Chunk tmp;
		head = fetchNext(&tmp);
//		writefln("_buf.offsetof = %s", head._buf.offsetof);
//		writefln("head.buf[0] = %s", *(cast(char*)head + head._buf.offsetof));
	}
	this(A...)(A args, size_t chunkSize)
	{
		__ctor(D(args), chunkSize);
	}

	@property bool empty() const
	{
		return head == &terminator;
	}
	@property E front()
	{
		return head.buf[frontOffset];
	}
	void popFront()
	{
		++frontOffset;
		if (frontOffset == chunkSize)
		{
			fetchedLen -= chunkSize;
			head = fetchNext(head), frontOffset = 0;
		}
	}

//	ref E opIndex(size_t n)
//	{
//	}

	Slice opSlice(size_t b, size_t e)
	{
		enforce(b <= e);
		auto bgn = frontOffset + b;
		auto end = frontOffset + e;

		if (fetchFinished && fetchedLen < bgn)
			goto EmptySlice;

		auto bgn_n = bgn / chunkSize;

		auto c = head;
		{
			auto i = bgn_n;
			while (i)
			{
				--i;
				if ((c = fetchNext(c)) == &terminator)
					goto EmptySlice;
			}
			assert(c != &terminator);
			if (fetchedLen <= bgn)
				goto EmptySlice;
		}
		auto bgnChunk = c;
		assert(bgnChunk !is &terminator);
		assert(bgn < fetchedLen,
			xtk.format.format("bgn=%s, fetchedLen=%s", bgn, fetchedLen));

		if (fetchedLen < end)
		{
			if (fetchFinished)
				goto HalfSlice;

			auto i = end / chunkSize - bgn_n;
			while (i)
			{
				--i;
				if ((c = fetchNext(c)) == &terminator)
					goto HalfSlice;
			}
			assert(c != &terminator);
			if (fetchedLen < end)
				goto HalfSlice;
		}
		assert(end <= fetchedLen);
		goto FullSlice;

	EmptySlice:
		bgn = fetchedLen;
	HalfSlice:
		end = fetchedLen;
	FullSlice:
		auto len = end - bgn;
		if (len)
			return Slice(bgnChunk, bgn - bgn_n*chunkSize, len);
		else
			return Slice(null, 0, 0);
	}

private:
	Chunk* fetchNext(Chunk* prev)
	in{ assert(prev !is &terminator); }
	body
	{
//		writefln("fetchNext");
		if (prev.next)
			return prev.next;

		auto mem = new ubyte[Chunk.sizeof + E.sizeof*chunkSize];
		auto chunk = cast(Chunk*)mem.ptr;
		auto buf = chunk.buf.ptr[0 .. chunkSize];
		auto v = buf;
		while (device.pull(v))
		{
			buf = buf[v.length .. $];
			if (buf.length == 0)
				break;
			v = buf;
		}

		if (buf.length == chunkSize)
		{
			// device.pull == false
			delete mem;
			return &terminator;
		}
		else
		{
			// device.pull == true
			lastChunk = chunk;

			auto n = chunkSize - buf.length;
			fetchedLen += n;
			chunk.size = n;
			chunk.next = null;
		}
		return prev.next = chunk;
	}

	bool fetchFinished() const
	{
	//	if (auto last = lastChunk)
		auto last = lastChunk;
		if (last)
			return last.size < terminator.size;
		else
			return false;
	}
}
debug(xtk_unittest)	// 他Projectとの併用時にSlicerの実体化で失敗する場合があるので、ここだけ外せるようにする
unittest
{
	scope(success) std.stdio.writefln("unittest@%s:%s passed", __FILE__, __LINE__);
	scope(failure) std.stdio.writefln("unittest@%s:%s failed", __FILE__, __LINE__);

	auto fname = "deleteme.txt";

	void makefile()
	{
		auto f = File(fname, "w");
		xtk.format.writef(f, "hello world, welcome to party.");
	}

	makefile();
	scope(exit) std.file.remove(fname);

	auto f = slicer(
		encoded!char(Sourced!File(fname, "r")), 4);

	assert(f.front == 'h',
		xtk.format.format("f.front = \\x%02X", f.front));

	assert(equal(f[0..2], "he"));

	assert(equal(f[0..4], "hell"));
	assert(equal(f[4..8], "o wo"));
	assert(equal(f[0..8], "hello wo"));
	assert(equal(f[6..20], "world, welcome"));

	popFrontN(f, 6);
	assert(equal(f[0..5], "world"));
	popFrontN(f, 7);
//	writefln("f[0..17] = %s", f[0..17]);
	assert(equal(f[0..17], "welcome to party."));
	popFrontN(f, 17);
	assert(!f.empty);
}


/**
Lined receives pool of char, and makes input range of lines separated $(D delim).
Naming:
	LineReader?
	LineStream?
Examples:
	lined!string(File("foo.txt"))
*/
auto lined(String=string, Source)(Source source, size_t bufferSize=2048)
	if (isSource!Source)
{
	alias Unqual!(typeof(String.init[0]))	Char;
	alias Encoded!(Source, Char)			Enc;
	alias Buffered!(Enc)					Buf;
	alias Lined!(Buf, String, String)		LinedType;
	return LinedType(Buf(Enc(move(source)), bufferSize), cast(String)NativeNewLine);
/+
	// Revsersing order of filters also works.
	alias Unqual!(typeof(String.init[0]))   Char;
	alias Buffered!(Source)				Buf;
	alias Encoded!(Buf, Char)          Enc;
	alias Lined!(Enc, String, String) LinedType;
	return LinedType(Enc(Buf(move(source), bufferSize)), cast(String)NativeNewLine);
+/
}
/// ditto
auto lined(String=string, Source, Delim)(Source source, in Delim delim, size_t bufferSize=2048)
	if (isSource!Source && isInputRange!Delim)
{
	alias Unqual!(typeof(String.init[0]))	Char;
	alias Encoded!(Source, Char)			Enc;
	alias Buffered!(Enc)					Buf;
	alias Lined!(Buf, Delim, String)		LinedType;
	return LinedType(Buf(Enc(move(source)), bufferSize), move(delim));
}

/// ditto
struct Lined(Pool, Delim, String : Char[], Char)
	if (isPool!Pool && isSomeChar!Char)
{
	//static assert(is(UnitType!Pool == Unqual!Char));	// compile-time evaluation bug？
	alias UnitType!Pool E;
	static assert(is(E == Unqual!Char));

private:
	alias Unqual!Char MutableChar;

	Pool pool;
	Delim delim;
	Appender!(MutableChar[]) buffer;
	String line;
	bool eof;

public:
	/**
	*/
	this(Pool p, Delim d)
	{
		move(p, pool);
		move(d, delim);
		popFront();
	}

	/**
	primitives of input range.
	*/
	@property bool empty() const
	{
		return eof;
	}

	/// ditto
	@property String front() const
	{
		return line;
	}

	/// ditto
	void popFront()
	in { assert(!empty); }
	body
	{
		const(MutableChar)[] view;
		const(MutableChar)[] nextline;

		bool fetchExact()	// fillAvailable?
		{
			view = pool.available;
			while (view.length == 0)
			{
				//writefln("fetched");
				if (!pool.fetch())
					return false;
				view = pool.available;
			}
			return true;
		}
		if (!fetchExact())
			return eof = true;

		buffer.clear();

		//writefln("Buffered.popFront : ");
		for (size_t vlen=0, dlen=0; ; )
		{
			if (vlen == view.length)
			{
				buffer.put(view);
				nextline = buffer.data;
				pool.consume(vlen);
				if (!fetchExact())
					break;

				vlen = 0;
				continue;
			}

			auto e = view[vlen];
			++vlen;
			if (e == delim[dlen])
			{
				++dlen;
				if (dlen == delim.length)
				{
					if (buffer.data.length)
					{
						buffer.put(view[0 .. vlen]);
						nextline = (buffer.data[0 .. $ - dlen]);
					}
					else
						nextline = view[0 .. vlen - dlen];

					pool.consume(vlen);
					break;
				}
			}
			else
				dlen = 0;
		}

	  static if (is(Char == immutable))
		line = nextline.idup;
	  else
		line = nextline;
	}
}
/+unittest
{
	void testParseLines(Str1, Str2)()
	{
		Str1 data = cast(Str1)"head\nmiddle\nend";
		Str2[] expects = ["head", "middle", "end"];

		auto indexer = sequence!"n"();
		foreach (e; zip(indexer, lined!Str2(data, "\n")))
		{
			auto ln = e[0], line = e[1];

			assert(line == expects[ln],
				format(
					"lined!%s(%s) failed : \n"
					"[%s]\tline   = %s\n\texpect = %s",
						Str2.stringof, Str1.stringof,
						ln, line, expects[ln]));
		}
	}

	testParseLines!( string,  string)();
	testParseLines!( string, wstring)();
	testParseLines!( string, dstring)();
	testParseLines!(wstring,  string)();
	testParseLines!(wstring, wstring)();
	testParseLines!(wstring, dstring)();
	testParseLines!(dstring,  string)();
	testParseLines!(dstring, wstring)();
	testParseLines!(dstring, dstring)();
}+/


alias Base64Impl!() Base64;

/**
fetch方法について改良案
ChunkRange提供
//Pool I/F提供版←必要なら置き換え可能
*/
//debug = B64Enc;
//debug = B64Dec;
template Base64Impl(char Map62th = '+', char Map63th = '/', char Padding = '=')
{
	static import std.base64;
	alias std.base64.Base64Impl!(Map62th, Map63th, Padding) StdBase64;

	void debugout(A...)(A args) { stderr.writefln(args); }

	/**
	*/
	Encoder!D encoder(D)(D device, size_t bufferSize = 2048)
	{
		return Encoder!D(move(device), bufferSize);
	}

	/**
	*/
	struct Encoder(D) if (isPool!D && is(UnitType!D == ubyte))
	{
	private:
		D device;
		char[] buf, view;
		ubyte[3] cache; size_t cachelen;
		bool eof;
	//	bool isempty;

	public:
		/**
		Ignore bufferSize (It's determined by pool size below)
		*/
		this(Device)(Device d, size_t bufferSize) if (is(Device == D))
		{
			move(d, device);
	//		isempty = !fetch();
		}
		/**
		*/
		this(A...)(A args, size_t bufferSize)
		{
			__ctor(D(args), bufferSize);
		}

	/+
		/**
		primitives of input range.
		*/
		@property bool empty()
		{
			return isempty;
		}
		/// ditto
		@property const(char)[] front()
		{
			return view;
		}
		/// ditto
		void popFront()
		{
		//	view = view[1 .. $];
		//	// -inline -release前提で、こっちのほうが分岐予測ミスが少ない？
		//	if (view.length == 0)
			view = view[0 .. 0];
				isempty = !fetch();
		}	// +/

	//+
		@property const(char)[] available() const
		{
			return view;
		}
		void consume(size_t n)
		in{ assert(n <= view.length); }
		body
		{
			view = view[n .. $];
		}	// +/

		bool fetch()
		in { assert(view.length == 0); }
		body
		{
			if (eof) return false;

			debug (B64Enc) debugout("");

			// device.fetchの繰り返しによってdevice.availableが最低2バイト以上たまることを要求する
			// Needed that minimum size of the device pool should be more than 2 bytes.
			if (cachelen)	// eating cache
			{
				assert(buf.length >= 4);

				debug (B64Enc) debugout("usecache 0: cache = [%(%02X %)]", cache[0..cachelen]);
			  Continue:
				if (device.fetch())
				{
					auto ava = device.available;
					debug (B64Enc) debugout("usecache 1: ava.length = %s", ava.length);
					if (cachelen + ava.length >= 3)
					{
						final switch (cachelen)
						{
						case 1:	cache[1] = ava[0];
								cache[2] = ava[1];	break;
						case 2:	cache[2] = ava[0];	break;
						}
						StdBase64.encode(cache[], buf[0..4]);
						device.consume(3 - cachelen);
					}
					else
						goto Continue;
				}
				else
				{
					assert(device.available.length == 0);
					debug (B64Enc) debugout("usecache 2: cachelen = %s", cachelen);
					view = StdBase64.encode(cache[0..cachelen], view = buf[0..4]);
					return (eof = true, eof);
				}
			}
			else if (!device.fetch())
			{
				eof = true;
				return false;
			}

			auto ava = device.available;
			immutable capnum = ava.length / 3;
			immutable caplen = capnum * 3;
			immutable buflen = capnum * 4;
			debug (B64Enc) debugout(
					"capture1: ava.length = %s, capnum = %s, caplen = %s, buflen = %s+%s",
					ava.length, capnum, caplen, buflen, cachelen ? 4 : 0);
			if (caplen)
			{
				// cachelen!=0 -> has encoded from cache
				auto bs = cachelen ? 4 : 0, be = bs+buflen;
				if (buf.length < be)
					buf.length = be;
				view = buf[bs + StdBase64.encode(ava[0..caplen], buf[bs..be]).length];
			}
			if ((cachelen = ava.length - caplen) != 0)
			{
				final switch (cachelen)
				{
				case 1:	cache[0] = ava[$-1];	break;
				case 2:	cache[0] = ava[$-2];
						cache[1] = ava[$-1];	break;
				}
				// It will be needed that buf.length >= 4 on next fetch.
				if (buf.length < 4) buf.length = 4;
			}
			device.consume(ava.length);
			debug (B64Enc)
				debugout(
					"capture2: view.length = %s, cachelen = %s, ava.length = %s",
					view.length, cachelen, ava.length);
			return true;
		}
	}

	/**
	*/
	auto decoder(D)(D device, size_t bufferSize = 2048)
	{
		alias UnitType!D U;	// workaround for type evaluation bug
		return Decoder!D(move(device), bufferSize);
	}

	/**
	*/
	struct Decoder(D) if (isPool!D && is(UnitType!D == char))
	{
	private:
		D device;
		ubyte[] buf, view;
		char[4] cache; size_t cachelen;
		bool eof;
	//	bool isempty;

	public:
		/**
		Ignore bufferSize (It's determined by pool size below)
		*/
		this(Device)(Device d, size_t bufferSize) if (is(Device == D))
		{
			move(d, device);
	//		isempty = !fetch();
		}
		/**
		*/
		this(A...)(A args, size_t bufferSize)
		{
			__ctor(D(args), bufferSize);
		}

	/+
		/**
		primitives of input range.
		*/
		@property bool empty() const
		{
			return isempty;
		}
		/// ditto
		@property const(ubyte)[] front()
		{
			return view;
		}
		/// ditto
		void popFront()
		{
		//	view = view[1 .. $];
		//	// -inline -release前提で、こっちのほうが分岐予測ミスが少ない？
		//	if (view.length == 0)
			view = view[0 .. 0];
				isempty = !fetch();
		}	// +/

	//+
		@property const(ubyte)[] available() const
		{
			return view;
		}
		void consume(size_t n)
		in{ assert(n <= view.length); }
		body
		{
			view = view[n .. $];
		}	// +/

		bool fetch()
		{
			if (eof) return false;

			// Needed that minimum size of the device pool should be more than 3 bytes.
			if (cachelen)	// eating cache
			{
				assert(buf.length >= 3);

				debug (B64Dec) debugout("usecache 0: cache = [%(%02X %)]", cache[0..cachelen]);
			  Continue:
				if (device.fetch())
				{
					auto ava = device.available;
					debug (B64Dec) debugout("usecache 1: ava.length = %s", ava.length);
					if (cachelen + ava.length >= 4)
					{
						final switch (cachelen)
						{
						case 1:	cache[1] = ava[0];
								cache[2] = ava[1];
								cache[3] = ava[2];	break;
						case 2:	cache[2] = ava[0];
								cache[3] = ava[1];	break;
						case 3:	cache[3] = ava[0];	break;
						}
						StdBase64.decode(cache[], buf[0..3]);
						device.consume(4 - cachelen);
					}
					else
						goto Continue;
				}
				else
				{
					assert(device.available.length == 0);
					debug (B64Dec) debugout("usecache 2: cachelen = %s", cachelen);
					view = StdBase64.decode(cache[0..cachelen], buf[0..3]);
					return (eof = true, eof);
				}
			}
			else if (!device.fetch())
			{
				eof = true;
				return false;
			}

			auto ava = device.available;
			immutable capnum = ava.length / 4;
			immutable caplen = capnum * 4;
			immutable buflen = capnum * 3;
			debug (B64Dec) debugout(
					"capture1: ava.length = %s, capnum = %s, caplen = %s, buflen = %s, (cache = %s)",
					ava.length, capnum, caplen, buflen, cachelen ? 4 : 0);
			if (caplen)
			{
				// cachelen!=0 -> has encoded from cache
				auto bs = cachelen ? 3 : 0, be = bs+buflen;
				if (buf.length < be)
					buf.length = be;
				view = buf[0 .. bs + StdBase64.decode(ava[0..caplen], buf[bs..be]).length];
			}
			if ((cachelen = ava.length - caplen) != 0)
			{
				final switch (cachelen)
				{
				case 1:	cache[0] = ava[$-1];	break;
				case 2:	cache[0] = ava[$-2];
						cache[1] = ava[$-1];	break;
				case 3:	cache[0] = ava[$-3];
						cache[1] = ava[$-2];
						cache[2] = ava[$-1];	break;
				}
				// It will be needed that buf.length >= 4 on next fetch.
				if (buf.length < 3) buf.length = 3;
			}
			device.consume(ava.length);
			debug (B64Dec)
				debugout(
					"capture2: view.length = %s, cachelen = %s, ava.length = %s",
					view.length, cachelen, ava.length);
			return true;
		}
	}
}


/*
	How to get PageSize:

	STLport
		void _Filebuf_base::_S_initialize()
		{
		#if defined (__APPLE__)
		  int mib[2];
		  size_t pagesize, len;
		  mib[0] = CTL_HW;
		  mib[1] = HW_PAGESIZE;
		  len = sizeof(pagesize);
		  sysctl(mib, 2, &pagesize, &len, NULL, 0);
		  _M_page_size = pagesize;
		#elif defined (__DJGPP) && defined (_CRAY)
		  _M_page_size = BUFSIZ;
		#else
		  _M_page_size = sysconf(_SC_PAGESIZE);
		#endif
		}

		void _Filebuf_base::_S_initialize() {
		  SYSTEM_INFO SystemInfo;
		  GetSystemInfo(&SystemInfo);
		  _M_page_size = SystemInfo.dwPageSize;
		  // might be .dwAllocationGranularity
		}
	DigitalMars C
		stdio.h

		#if M_UNIX || M_XENIX
		#define BUFSIZ		4096
		extern char * __cdecl _bufendtab[];
		#elif __INTSIZE == 4
		#define BUFSIZ		0x4000
		#else
		#define BUFSIZ		1024
		#endif

	version(Windows)
	{
		// from win32.winbase
		struct SYSTEM_INFO
		{
		  union {
		    DWORD dwOemId;
		    struct {
		      WORD wProcessorArchitecture;
		      WORD wReserved;
		    }
		  }
		  DWORD dwPageSize;
		  LPVOID lpMinimumApplicationAddress;
		  LPVOID lpMaximumApplicationAddress;
		  DWORD* dwActiveProcessorMask;
		  DWORD dwNumberOfProcessors;
		  DWORD dwProcessorType;
		  DWORD dwAllocationGranularity;
		  WORD wProcessorLevel;
		  WORD wProcessorRevision;
		}
		extern(Windows) export VOID GetSystemInfo(
		  SYSTEM_INFO* lpSystemInfo);

		void getPageSize()
		{
			SYSTEM_INFO SystemInfo;
			GetSystemInfo(&SystemInfo);
			auto _M_page_size = SystemInfo.dwPageSize;
			writefln("in Win32 page_size = %s", _M_page_size);
		}
	}
*/


/**
*/
ref Dst copy(Src, Dst)(ref Src src, ref Dst dst)
	if (!(isInputRange!Src && isOutputRange!(Dst, ElementType!Src)) &&
		(isPool!Src || isInputRange!Src) && (isSink!Dst || isOutputRange!Dst))
{
	void put_to_dst(E)(const(E)[] data)
	{
		while (data.length > 0)
		{
		  static if (isSink!Dst)
		  {
			if (!dst.push(data))
				throw new Exception("");
		  }
		  static if (isOutputRange!(Dst, typeof(data[0])))
		  {
			dst.put(data);
		  }
		}
	}

	static if (isPool!Src)
	{
		if (src.available.length == 0 && !src.fetch())
			return dst;

		do
		{
			// almost same with Ranged.put
			put_to_dst(src.available);
			src.consume(src.available.length);
		}while (src.fetch())
	}
	static if (isInputRange!Src)
	{
		static assert(isSink!Dst);

		static if (isArray!Src)
		{
			put_to_dst(src[]);
		}
		else
		{
			for (; !src.empty; src.popFront)
			{
				auto e = src.front;
				put_to_dst(&e[0 .. 1]);
			}
		}
	}
	return dst;
}
