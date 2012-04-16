SRCS=io\core.d \
	io\file.d \
	io\socket.d \
	io\buffer.d \
	io\filter.d \
	io\text.d \
	io\wrapper.d \
	sys\windows.d \
	util\typecons.d \
	util\meta.d \
	util\metastrings_expand.d

DFLAGS=-property -w -I.

DDOCDIR=html\d
DOCS=\
	$(DDOCDIR)\io_core.html \
	$(DDOCDIR)\io_file.html \
	$(DDOCDIR)\io_socket.html \
	$(DDOCDIR)\io_buffer.html \
	$(DDOCDIR)\io_filter.html \
	$(DDOCDIR)\io_text.html \
	$(DDOCDIR)\io_wrapper.html
DDOC=io.ddoc
DDOCFLAGS=-D -Dd$(DDOCDIR) -c -o- $(DFLAGS)

IOLIB=lib\io.lib
DEBLIB=lib\io_debug.lib


# lib

lib: $(IOLIB)
$(IOLIB): $(SRCS)
	mkdir lib
	dmd -lib -of$(IOLIB) $(SRCS)
	#dmd -lib -of$@ $(DFLAGS) -O -release -noboundscheck $(SRCS)

#deblib: $(DEBLIB)
#$(DEBLIB): $(SRCS)
#	mkdir lib
#	dmd -lib -of$@ $(DFLAGS) -g $(SRCS)

clean:
	del lib\*.lib
	del test\*.obj
	del test\*.exe


# test

runtest: lib test\unittest.exe test\pipeinput.exe
	test\unittest.exe
	test\pipeinput.bat

test\unittest.exe: emptymain.d $(SRCS)
	dmd $(DFLAGS) -of$@ -unittest emptymain.d $(SRCS)
test\pipeinput.exe: test\pipeinput.d test\pipeinput.dat test\pipeinput.bat lib
	dmd $(DFLAGS) -of$@ test\pipeinput.d $(IOLIB)


# ddoc

html: makefile $(DOCS) $(SRCS)

$(DDOCDIR)\io_core.html: $(DDOC) io\core.d
	dmd $(DDOCFLAGS) -Dfio_core.html $(DDOC) io\core.d

$(DDOCDIR)\io_file.html: $(DDOC) io\file.d
	dmd $(DDOCFLAGS) -Dfio_file.html $(DDOC) io\file.d

$(DDOCDIR)\io_socket.html: $(DDOC) io\socket.d
	dmd $(DDOCFLAGS) -Dfio_socket.html $(DDOC) io\socket.d

$(DDOCDIR)\io_buffer.html: $(DDOC) io\buffer.d
	dmd $(DDOCFLAGS) -Dfio_buffer.html $(DDOC) io\buffer.d

$(DDOCDIR)\io_filter.html: $(DDOC) io\filter.d
	dmd $(DDOCFLAGS) -Dfio_filter.html $(DDOC) io\filter.d

$(DDOCDIR)\io_text.html: $(DDOC) io\text.d
	dmd $(DDOCFLAGS) -Dfio_text.html $(DDOC) io\text.d

$(DDOCDIR)\io_wrapper.html: $(DDOC) io\wrapper.d
	dmd $(DDOCFLAGS) -Dfio_wrapper.html $(DDOC) io\wrapper.d
