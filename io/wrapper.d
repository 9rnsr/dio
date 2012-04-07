/*
This module provides thin wrappers of std.stdio.writef?(ln)? family.
 */
module io.wrapper;

import io.core, io.text;
import std.range : isOutputRange, put;

/**
Output $(D args) to $(D writer).
*/
void write(Writer, T...)(Writer writer, T args)
    if (isOutputRange!(Writer, char) && T.length > 0)
{
    import std.conv;
    foreach (i, ref arg; args)
    {
        put(writer, to!string(arg));
    }
}
/// ditto
void writef(Writer, T...)(Writer writer, T args)
    if (isOutputRange!(Writer, char) && T.length > 0)
{
    import std.format;
    formattedWrite(writer, args);
}
/// ditto
void writeln(Writer, T...)(Writer writer, T args)
    if (isOutputRange!(Writer, char))
{
    write(writer, args, "\n");
}
/// ditto
void writefln(Writer, T...)(Writer writer, T args)
    if (isOutputRange!(Writer, char) && T.length > 0)
{
    writef(writer, args, "\n");
}

/**
Output $(D args) to $(D io.text.dout).
*/
void write(T...)(T args)
    if (!isOutputRange!(T[0], char) && T.length > 0)
{
    write(dout, args);
}
/// ditto
void writef(T...)(T args)
    if (!isOutputRange!(T[0], char) && T.length > 0)
{
    writef(dout, args);
}

/// ditto
void writeln(T...)(T args)
    if (T.length == 0 || !isOutputRange!(T[0], char))
{
    writeln(dout, args);
}
/// ditto
void writefln(T...)(T args)
    if (!isOutputRange!(T[0], char) && T.length > 0)
{
    writefln(dout, args);
}

/**
*/
uint readf(Reader, Data...)(Reader reader, in char[] format, Data data) if (isInputRange!Reader)
{
    return formattedRead(reader, format, data);
}

/**
*/
uint readf(Data...)(in char[] format, Data data)
{
    import std.format;
    return readf(din, format, data);
}
