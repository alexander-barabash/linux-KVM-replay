include config.mak

ARCH_DIR = $(if $(filter $(ARCH),x86_64 i386),x86,$(ARCH))
ARCH_CONFIG := $(shell echo $(ARCH_DIR) | tr '[:lower:]' '[:upper:]')
# NONARCH_CONFIG used for unifdef, and only cover X86 and IA64 now
NONARCH_CONFIG = $(filter-out $(ARCH_CONFIG),X86 IA64)

KVERREL = $(patsubst /lib/modules/%/build,%,$(KERNELDIR))

DESTDIR = /

MAKEFILE_PRE = $(ARCH_DIR)/Makefile.pre

INSTALLDIR = $(patsubst %/build,%/extra,$(KERNELDIR))
ORIGMODDIR = $(patsubst %/build,%/kernel,$(KERNELDIR))

HEADERDIR = /usr/local/include/kvm-kmod

rpmrelease = devel

LINUX = ./linux-2.6

all:: prerequisite
#	include header priority 1) $LINUX 2) $KERNELDIR 3) include-compat
	$(MAKE) -C $(KERNELDIR) M=`pwd` \
		LINUXINCLUDE="-I`pwd`/include -Iinclude \
		$(if $(KERNELSOURCEDIR),\
			-Iinclude2 -I$(KERNELSOURCEDIR)/include -I$(KERNELSOURCEDIR)/arch/${ARCH_DIR}/include, \
			-Iarch/${ARCH_DIR}/include) -I`pwd`/include-compat -I`pwd`/${ARCH_DIR} \
		-include include/linux/autoconf.h \
		-include `pwd`/$(ARCH_DIR)/external-module-compat.h" \
		"$$@"

include $(MAKEFILE_PRE)

.PHONY: sync sync-kmod sync-hdr

KVM_VERSION_GIT = $(if $(and $(filter kvm-devel,$(KVM_VERSION)), \
			 $(wildcard $(LINUX)/.git)), \
			   $(shell git --git-dir=$(LINUX)/.git describe), \
			   $(KVM_VERSION))

sync-kmod:
	./sync -v $(KVM_VERSION_GIT) -l $(LINUX)

sync-hdr:
	for a in ia64 x86; do \
		$(MAKE) -C $(LINUX) INSTALL_HDR_PATH=`pwd`/.tmp-hdrs SRCARCH="$$a" headers_install; \
		mkdir -p usr/include/asm-"$$a"; \
		cp .tmp-hdrs/include/asm/kvm.h usr/include/asm-"$$a"; \
	done
	mkdir -p usr/include/linux
	cp .tmp-hdrs/include/linux/kvm.h usr/include/linux
	rm -rf .tmp-hdrs

sync: sync-kmod sync-hdr

install:
	mkdir -p $(DESTDIR)/$(INSTALLDIR)
	cp $(ARCH_DIR)/*.ko $(DESTDIR)/$(INSTALLDIR)
	for i in $(DESTDIR)/$(ORIGMODDIR)/drivers/kvm/*.ko \
		 $(DESTDIR)/$(ORIGMODDIR)/arch/$(ARCH_DIR)/kvm/*.ko; do \
		if [ -f "$$i" ]; then mv "$$i" "$$i.orig"; fi; \
	done
	/sbin/depmod -a $(DEPMOD_VERSION) -b $(DESTDIR)
	install -m 644 -D scripts/65-kvm.rules $(DESTDIR)/etc/udev/rules.d/65-kvm.rules
	install -m 644 -D usr/include/asm-$(ARCH_DIR)/kvm.h $(DESTDIR)/$(HEADERDIR)/asm/kvm.h
	install -m 644 -D usr/include/linux/kvm.h $(DESTDIR)/$(HEADERDIR)/linux/kvm.h

tmpspec = .tmp.kvm-kmod.spec

rpm-topdir := $$(pwd)/rpmtop

RPMDIR = $(rpm-topdir)/RPMS

rpm:	all
	mkdir -p $(rpm-topdir)/BUILD $(RPMDIR)/$$(uname -i)
	sed 's/^Release:.*/Release: $(rpmrelease)/; s/^%define kverrel.*/%define kverrel $(KVERREL)/' \
	     kvm-kmod.spec > $(tmpspec)
	rpmbuild --define="kverrel $(KVERREL)" \
		 --define="objdir $$(pwd)/$(ARCH_DIR)" \
		 --define="_rpmdir $(RPMDIR)" \
		 --define="_topdir $(rpm-topdir)" \
		-bb $(tmpspec)

clean:
	$(MAKE) -C $(KERNELDIR) M=`pwd` $@

distclean: clean
	rm -f config.mak include/asm include-compat/asm
