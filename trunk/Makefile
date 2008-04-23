PERLSCRIPT=ftpbackup
MAN=ftpbackup.1
INSTALL_BIN=install -s
KEY=26C1A1AC


all: $(MAN)

clean:
	rm -f $(MAN) *.orig *.~*

dist-clean: clean
	fakeroot debian/rules clean

install:
	mkdir -p $(PREFIX)/usr/bin
	install $(PERLSCRIPT) $(PREFIX)/usr/bin
	
	mkdir -p $(PREFIX)/usr/share/man/man1
	install $(MAN) $(PREFIX)/usr/share/man/man1

uninstall:
	rm -f $(PREFIX)/usr/bin/$(PERLSCRIPT)
	rm -f $(PREFIX)/usr/share/man/man1/$(MAN)

newversion:
	perl -i.orig -pne 'if (/my \$$VERSION/) {s/\.(\d)*/sprintf(".%d",1+$$1)/e}' ${PERLSCRIPT}

oldversion:
	perl -i.orig -pne 'if (/my \$$VERSION/) {s/\.(\d)*/sprintf(".%d",$$1-1)/e}' ${PERLSCRIPT}

undo:
	-mv -f ${PERLSCRIPT}.orig ${PERLSCRIPT}

deb:
	dpkg-buildpackage -rfakeroot -k${KEY}

release: clean newversion all deb

ftpbackup.1:
	pod2man --center=" " --release="ftpbackup" $(PERLSCRIPT) > $@;
	pod2text $(PERLSCRIPT) > README
