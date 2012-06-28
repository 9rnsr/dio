SRCS=io/core.d \
	io/file.d \
	io/socket.d \
	io/port.d \
	util/typecons.d \
	util/meta.d

DFLAGS=-property -w -I.

DDOCDIR=html/d
DOCS=\
	$(DDOCDIR)/io_core.html \
	$(DDOCDIR)/io_file.html \
	$(DDOCDIR)/io_socket.html \
	$(DDOCDIR)/io_port.html
DDOC=io.ddoc
DDOCFLAGS=-D -Dd$(DDOCDIR) -c -o- $(DFLAGS)

IOLIB=lib/libio
DEBLIB=lib/libio_debug


# lib

lib: $(IOLIB)
$(IOLIB): $(SRCS)
	@[ -d lib ] || mkdir lib
	dmd -lib -of$(IOLIB) $(SRCS)

#deblib: $(DEBLIB)
#$(DEBLIB): $(SRCS)
#	mkdir lib
#	dmd -lib -of$@ $(DFLAGS) -g $(SRCS)

clean:
	rm lib/*
	rm test/*.o
	rm test/*.exe
	rm html/d/*.html
	rm benchmarks/*.exe


# test

runtest: lib test/unittest.exe test/pipeinput.exe
	test/unittest.exe
	test/pipeinput.bat

test/unittest.exe: emptymain.d $(SRCS)
	dmd $(DFLAGS) -of$@ -unittest emptymain.d $(SRCS)
test/pipeinput.exe: test/pipeinput.d test/pipeinput.dat test/pipeinput.bat lib
	dmd $(DFLAGS) -of$@ test/pipeinput.d $(IOLIB)


# benchmark

runbench: lib benchmarks/default_bench.exe
	benchmarks/default_bench.exe
runbench_opt: lib benchmarks/release_bench.exe
	benchmarks/release_bench.exe

benchmarks\default_bench.exe: benchmarks/bench.d
	dmd $(DFLAGS) -of$@ benchmarks/bench.d $(IOLIB)
benchmarks/release_bench.exe: benchmarks/bench.d
	dmd $(DFLAGS) -O -release -noboundscheck -of$@ benchmarks/bench.d $(IOLIB)


# ddoc

html: makefile $(DOCS) $(SRCS)

$(DDOCDIR)/io_core.html: $(DDOC) io/core.d
	dmd $(DDOCFLAGS) -Dfio_core.html $(DDOC) io/core.d

$(DDOCDIR)/io_file.html: $(DDOC) io/file.d
	dmd $(DDOCFLAGS) -Dfio_file.html $(DDOC) io/file.d

$(DDOCDIR)/io_socket.html: $(DDOC) io/socket.d
	dmd $(DDOCFLAGS) -Dfio_socket.html $(DDOC) io/socket.d

$(DDOCDIR)/io_port.html: $(DDOC) io/port.d
	dmd $(DDOCFLAGS) -Dfio_port.html $(DDOC) io/port.d
