PERLSCRIPT=ftpbackup
MAN=ftpbackup.1
INSTALL_BIN=install -s

all: $(MAN)

clean:
	rm -f $(MAN)

install:
	mkdir -p $(PREFIX)/usr/bin
	install $(PERLSCRIPT) $(PREFIX)/usr/bin
	
	mkdir -p $(PREFIX)/usr/share/man/man1
	install $(MAN) $(PREFIX)/usr/share/man/man1

uninstall:
	rm -f $(PREFIX)/usr/bin/$(PERLSCRIPT)
	rm -f $(PREFIX)/usr/share/man/man1/$(MAN)

ftpbackup.1:
	pod2man --center=" " --release="ftpbackup" $(PERLSCRIPT) > $@;
