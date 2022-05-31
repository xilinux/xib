PREFIX=/usr

install:
	install -Dm755 xib.sh ${DESTDIR}${PREFIX}/bin/xib
	install -Dm755 xibd.sh ${DESTDIR}${PREFIX}/bin/xibd
	install -Dm644 xib_profile.conf ${DESTDIR}/etc/xib_profile.conf

