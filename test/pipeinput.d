import io.core, io.text, io.wrapper;
void main()
{
    long num;
    write("num>"), readf("%s\r\n", &num);
    writefln("num = %s\n", num);
    assert(num == 10);

    string str;
    write("str>"), readf("%s\r\n", &str);
    writefln("str = [%(%02X %)]", str);
    assert(str == "test");
}
