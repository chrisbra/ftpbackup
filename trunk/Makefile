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
	install $(MANS) $(PREFIX)/usr/share/man/man1

ftpbackup.1:
	pod2man --center=" " --release="ftpbackup" $(PERLSCRIPT) > $@;
