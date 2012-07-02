SRCDIR=src
SRCS=$(SRCDIR)/io/core.d \
	$(SRCDIR)/io/file.d \
	$(SRCDIR)/io/socket.d \
	$(SRCDIR)/io/port.d

DFLAGS=-property -w -I$(SRCDIR) -g

DDOCDIR=html/d
DOCS=\
	$(DDOCDIR)/io_core.html \
	$(DDOCDIR)/io_file.html \
	$(DDOCDIR)/io_socket.html \
	$(DDOCDIR)/io_port.html
DDOC=io.ddoc
DDOCFLAGS=-D -Dd$(DDOCDIR) -c -o- $(DFLAGS)

IOLIB=lib/libio.a
DEBLIB=lib/libio_debug


# lib

all: $(IOLIB)
$(IOLIB): $(SRCS)
	@[ -d lib ] || mkdir lib
	dmd -lib -of$(IOLIB) $(SRCS)

#deblib: $(DEBLIB)
#$(DEBLIB): $(SRCS)
#	mkdir lib
#	dmd -lib -of$@ $(DFLAGS) -g $(SRCS)

clean:
	rm -rf lib
	rm -f test/*.o
	rm -f html/d/*.html


# test

runtest: $(IOLIB) test/unittest test/pipeinput
	test/unittest
	test/pipeinput.sh

test/unittest: emptymain.d $(SRCS)
	dmd $(DFLAGS) -of$@ -unittest emptymain.d $(SRCS)
test/pipeinput: test/pipeinput.d test/pipeinput.dat test/pipeinput.sh $(IOLIB)
	dmd $(DFLAGS) -of$@ test/pipeinput.d $(IOLIB)


# benchmark

runbench: $(IOLIB) test/default_bench
	test/default_bench
runbench_opt: $(IOLIB) test/release_bench
	test/release_bench

test/default_bench: test/bench.d
	dmd $(DFLAGS) -of$@ test/bench.d $(IOLIB)
test/release_bench.exe: test/bench.d
	dmd $(DFLAGS) -O -release -noboundscheck -of$@ test/bench.d $(IOLIB)


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
