# Makefile for pacopts

VERSION = $$(git describe --tags| sed 's/-.*//g;s/^v//;')
PKGNAME = pacopts

BINDIR = /usr/bin

SCRIPTS = $$(find pacopts/ -type f)
MANPAGES = doc/pacopts.1
FILES = pacopts.in \
		pacopts.sh 
		
all: doc

install: all
	
	for i in $(FILES) $(SCRIP); do \
		sed -i 's,@BINDIR@,$(BINDIR),' $$i; \
	done
	
	install -Dm 0755 pacopts.in $(DESTDIR)/usr/bin/pacopts
	install -Dm 0755 pacopts.sh $(DESTDIR)/usr/lib/obarun/pacopts.sh
	install -Dm 0644 pacopts.conf $(DESTDIR)/etc/obarun/pacopts.conf
	
	for i in $(SCRIPTS); do \
		install -Dm 0755 $$i $(DESTDIR)/usr/lib/obarun/pacopts/$$i; \
	done
	
	for i in applytmp.hook applysys.hook; do \
		install -Dm 0644 $$i $(DESTDIR)/usr/share/libalpm/hooks/$$i; \
	done
	
	install -Dm644 doc/pacopts.1 $(DESTDIR)/usr/share/man/man1/pacopts.1
		
	install -Dm644 LICENSE $(DESTDIR)/usr/share/licenses/$(PKGNAME)/LICENSE

doc: $(MANPAGES)
doc/%: doc/%.txt Makefile
	a2x -d manpage \
		-f manpage \
		-a manversion=$(VERSION) \
		-a manmanual="pacopts manual" $<
		
version:
	@echo $(VERSION)
	
.PHONY: install version doc
