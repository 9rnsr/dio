SRCS=io\core.d io\file.d io\socket.d io\buffer.d io\filter.d io\text.d io\wrapper.d
DFLAGS=-property -w

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

unittest: unittest.exe

unittest.exe: makefile $(SRCS) emptymain.d
	dmd -unittest $(DFLAGS) $(SRCS) emptymain.d -ofunittest.exe

rununittest: unittest.exe
	unittest

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
