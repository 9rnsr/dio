/**
Add some symbols not defined in core module.
*/
module sys.windows;

public import core.sys.windows.windows, std.windows.syserror;

enum : uint { ERROR_BROKEN_PIPE = 109 }

extern(Windows) BOOL FlushFileBuffers(HANDLE hFile);

extern(Windows) DWORD GetFileType(HANDLE hFile);
enum uint FILE_TYPE_UNKNOWN = 0x0000;
enum uint FILE_TYPE_DISK    = 0x0001;
enum uint FILE_TYPE_CHAR    = 0x0002;
enum uint FILE_TYPE_PIPE    = 0x0003;
enum uint FILE_TYPE_REMOTE  = 0x8000;

