SRCS=io\core.d io\file.d

DFLAGS=-property -w

unittest: $(SRCS) emptymain.d
	dmd -unittest $(DFLAGS) $(SRCS) emptymain.d -ofunittest.exe

rununittest: unittest
	unittest

