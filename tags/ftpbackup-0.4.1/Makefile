PERLSCRIPT=ftpbackup
MAN=ftpbackup.1
INSTALL_BIN=install -s
KEY=26C1A1AC

ifndef PREFIX
PREFIX = /usr/local
endif


all: $(MAN)

clean:
	rm -f $(MAN) README *.orig *.~* 

dist-clean: clean
	fakeroot debian/rules clean

install:
	mkdir -p $(PREFIX)/bin
	install $(PERLSCRIPT) $(PREFIX)/bin
	
	mkdir -p $(PREFIX)/share/man/man1
	install $(MAN) $(PREFIX)/share/man/man1

uninstall:
	rm -f $(PREFIX)/bin/$(PERLSCRIPT)
	rm -f $(PREFIX)/share/man/man1/$(MAN)

newversion:
	perl -i.orig -pne 'if (/my \$$VERSION/) {s/\.(\d)*/sprintf(".%d",1+$$1)/e}' ${PERLSCRIPT}

oldversion:
	perl -i.orig -pne 'if (/my \$$VERSION/) {s/\.(\d)*/sprintf(".%d",$$1-1)/e}' ${PERLSCRIPT}

undo:
	-mv -f ${PERLSCRIPT}.orig ${PERLSCRIPT}

commit:
	svn commit -m "increased version number" $(PERLSCRIPT)

deb:
	dpkg-buildpackage -rfakeroot -k${KEY}

release: clean newversion commit all deb

ftpbackup.1:
	pod2man --center=" " --release="ftpbackup" $(PERLSCRIPT) > $@;
	pod2text $(PERLSCRIPT) > README
