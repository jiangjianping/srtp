# Makefile for secure rtp 
#
# David A. McGrew
# Cisco Systems, Inc.

# targets:
#
# runtest       runs test applications 
# test		builds test applications
# libcrypt.a	static library implementing crypto engine
# libsrtp.a	static library implementing srtp
# clean		removes objects, libs, and executables
# distribution  cleans and builds a .tgz
# tags          builds etags file from all .c and .h files

.PHONY: all test build_table_apps

all: libsrtp.so test

runtest: build_table_apps test
	@echo "running libsrtp test applications..."
	crypto/test/cipher_driver$(EXE) -v
	crypto/test/kernel_driver$(EXE) -v
	test/rdbx_driver$(EXE) -v
	test/srtp_driver$(EXE) -v
	test/roc_driver$(EXE) -v
	test/replay_driver$(EXE) -v
	test/dtls_srtp_driver$(EXE)
	cd test; ./rtpw_test.sh
	@echo "libsrtp test applications passed."
	$(MAKE) -C crypto runtest

# makefile variables

CC	= gcc
INCDIR	= -Icrypto/include -I$(srcdir)/include -I$(srcdir)/crypto/include
DEFS	= -DHAVE_CONFIG_H 
CPPFLAGS= 
CFLAGS	= -Wall -O0 -g
#CFLAGS	= -Wall -O4 -fexpensive-optimizations -funroll-loops
LIBS	= 
LDFLAGS	=  -L.
COMPILE = $(CC) $(DEFS) $(INCDIR) $(CPPFLAGS) $(CFLAGS)
SRTPLIB	= -lsrtp

RANLIB	= ranlib
INSTALL	= /usr/bin/install -c

# EXE defines the suffix on executables - it's .exe for Windows, and
# null on linux, bsd, and OS X and other OSes.
EXE	= 
# gdoi is the group domain of interpretation for isakmp, a group key
# management system which can provide keys for srtp
gdoi	= 
# Random source.
RNG_OBJS = rand_source.o

srcdir = .
top_srcdir = .
top_builddir = 

prefix = /home/guillaume/dev/inst
exec_prefix = ${prefix}
includedir = ${prefix}/include
libdir = ${exec_prefix}/lib


# implicit rules for object files and test apps

%.o: %.c
	$(COMPILE) -fPIC -c $< -o $@

%$(EXE): %.c
	$(COMPILE) $(LDFLAGS) $< -o $@ $(SRTPLIB) $(LIBS)


# libcrypt.a (the crypto engine) 
ciphers = crypto/cipher/cipher.o crypto/cipher/null_cipher.o      \
          crypto/cipher/aes.o crypto/cipher/aes_icm.o             \
          crypto/cipher/aes_cbc.o

hashes  = crypto/hash/null_auth.o crypto/hash/sha1.o \
          crypto/hash/hmac.o crypto/hash/auth.o # crypto/hash/tmmhv2.o 

replay  = crypto/replay/rdb.o crypto/replay/rdbx.o               \
          crypto/replay/ut_sim.o 

math    = crypto/math/datatypes.o crypto/math/stat.o

ust     = crypto/ust/ust.o 

rng     = crypto/rng/$(RNG_OBJS) crypto/rng/prng.o crypto/rng/ctr_prng.o

err     = crypto/kernel/err.o

kernel  = crypto/kernel/crypto_kernel.o  crypto/kernel/alloc.o   \
          crypto/kernel/key.o $(rng) $(err) # $(ust) 

cryptobj =  $(ciphers) $(hashes) $(math) $(stat) $(kernel) $(replay)

# libsrtp.a (implements srtp processing)

srtpobj = srtp/srtp.o 

libsrtp.a: $(srtpobj) $(cryptobj) $(gdoi)
	ar cr libsrtp.a $^
	$(RANLIB) libsrtp.a

libsrtp.so: $(srtpobj) $(cryptobj) $(gdoi)
	$(CC) $(LDFLAGS) -shared -Wl,-soname,libsrtp.so.0 -o libsrtp.so.0.0  $^

# libcryptomath.a contains general-purpose routines that are used to
# generate tables and verify cryptoalgorithm implementations - this
# library is not meant to be included in production code

cryptomath = crypto/math/math.o crypto/math/gf2_8.o 

libcryptomath.a: $(cryptomath)
	ar cr libcryptomath.a $(cryptomath)
	$(RANLIB) libcryptomath.a


# test applications 

crypto_testapp = crypto/test/aes_calc$(EXE) crypto/test/cipher_driver$(EXE) \
	crypto/test/datatypes_driver$(EXE) crypto/test/kernel_driver$(EXE) \
	crypto/test/rand_gen$(EXE) crypto/test/sha1_driver$(EXE) \
	crypto/test/stat_driver$(EXE)

testapp = $(crypto_testapp) test/srtp_driver$(EXE) test/replay_driver$(EXE) \
	  test/roc_driver$(EXE) test/rdbx_driver$(EXE) test/rtpw$(EXE) \
	  test/dtls_srtp_driver$(EXE)

$(testapp): libsrtp.a

test/rtpw$(EXE): test/rtpw.c test/rtp.c test/getopt_s.c
	$(COMPILE) $(LDFLAGS) -o $@ $^ $(LIBS) $(SRTPLIB)

test/srtp_driver$(EXE): test/srtp_driver.c test/getopt_s.c
	$(COMPILE) $(LDFLAGS) -o $@ $^ $(LIBS) $(SRTPLIB)

test/rdbx_driver$(EXE): test/rdbx_driver.c test/getopt_s.c
	$(COMPILE) $(LDFLAGS) -o $@ $^ $(LIBS) $(SRTPLIB)

test/dtls_srtp_driver$(EXE): test/dtls_srtp_driver.c test/getopt_s.c
	$(COMPILE) $(LDFLAGS) -o $@ $^ $(LIBS) $(SRTPLIB)

test: $(testapp)
	@echo "Build done. Please run '$(MAKE) runtest' to run self tests."

memtest: test/srtp_driver
	@test/srtp_driver -v -d "alloc" > tmp
	@grep freed tmp | wc -l > freed
	@grep allocated tmp | wc -l > allocated
	@echo "checking for memory leaks (only works with --enable-stdout)"
	cmp -s allocated freed
	@echo "passed (same number of alloc() and dealloc() calls found)"
	@rm freed allocated tmp

# tables_apps are used to generate the tables used in the crypto
# implementations; these need only be generated during porting, not
# for building libsrtp or the test applications

table_apps = tables/aes_tables 

build_table_apps: $(table_apps)

# in the tables/ subdirectory, we use libcryptomath instead of libsrtp

tables/%: tables/%.c libcryptomath.a 
	$(COMPILE) $(LDFLAGS) $< -o $@ $(LIBS) libcryptomath.a

# the target 'plot' runs the timing test (test/srtp_driver -t) then
# uses gnuplot to produce plots of the results - see the script file
# 'timing'

plot:	test/srtp_driver
	test/srtp_driver -t > timing.dat


# bookkeeping: tags, clean, and distribution

tags:
	etags */*.[ch] */*/*.[ch] 


# documentation - the target libsrtpdoc builds a PDF file documenting
# libsrtp

libsrtpdoc:
	$(MAKE) -C doc

.PHONY: clean superclean install

install:
	@if [ -d $(DESTDIR)$(includedir)/srtp ]; then \
	   echo "you should run 'make uninstall' first"; exit 1;  \
	fi
	$(INSTALL) -d $(DESTDIR)$(includedir)/srtp
	$(INSTALL) -d $(DESTDIR)$(libdir)
	cp include/*.h $(DESTDIR)$(includedir)/srtp  
	cp crypto/include/*.h $(DESTDIR)$(includedir)/srtp
	if [ -f libsrtp.a ]; then cp libsrtp.a $(DESTDIR)$(libdir)/; fi
	if [ -f libsrtp.so.0.0 ]; then \
		cp libsrtp.so.0.0 $(DESTDIR)$(libdir)/; \
		ln -s libsrtp.so.0.0 $(DESTDIR)$(libdir)/libsrtp.so.0; \
		ln -s libsrtp.so.0.0 $(DESTDIR)$(libdir)/libsrtp.so; \
	fi

uninstall:
	rm -rf $(DESTDIR)$(includedir)/srtp
	rm -rf $(DESTDIR)$(libdir)/libsrtp.a

clean:
	rm -rf $(cryptobj) $(srtpobj) $(cryptomath) TAGS \
        libcryptomath.a libsrtp.a libsrtp.so.0.0 core *.core test/core
	for a in * */* */*/*; do			\
              if [ -f "$$a~" ] ; then rm -f $$a~; fi;	\
        done;
	for a in $(testapp) $(table_apps); do rm -rf $$a$(EXE); done
	rm -rf *.pict *.jpg *.dat 
	rm -rf freed allocated tmp
	$(MAKE) -C doc clean
	$(MAKE) -C crypto clean


superclean: clean
	rm -rf crypto/include/config.h config.log config.cache config.status \
               Makefile .gdb_history test/.gdb_history .DS_Store
	rm -rf autom4te.cache

distname = srtp-$(shell cat VERSION)

distribution: runtest superclean 
	if ! [ -f VERSION ]; then exit 1; fi
	if [ -f ../$(distname).tgz ]; then               \
           mv ../$(distname).tgz ../$(distname).tgz.bak; \
        fi
	cd ..; tar cvzf $(distname).tgz srtp

# EOF
