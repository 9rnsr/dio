import io.core, io.port;
void main()
{
    long num;
    write("num>"), readf("%s\n", &num);
    writefln("num = %s\n", num);
    assert(num == 10);

    string str;
    write("str>"), readf("%s\n", &str);
    writefln("str = [%(%02X %)]", str);
    assert(str == "test");
}
