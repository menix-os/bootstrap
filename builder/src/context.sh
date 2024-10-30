export PREFIX="${INSTALL_DIR}/usr"
export PREFIX_HOST="${HOST_DIR}/usr/local"

PATH="${PREFIX_HOST}/bin":${PATH}

export OS_TRIPLET="${ARCH}-pc-menix"

BIN_DIR="${PREFIX}/bin"
SBIN_DIR="${PREFIX}/sbin"
LIB_DIR="${PREFIX}/lib"
ETC_DIR="/etc"
VAR_DIR="/var"

if [ "${DEBUG}" == "1" ]; then
	HOST_CFLAGS="-O0 -g -pipe -fstack-clash-protection"
	HOST_CXXFLAGS="${HOST_CFLAGS} -Wp,-D_GLIBCXX_ASSERTIONS"
	HOST_LDFLAGS="-Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now"

	TARGET_CFLAGS="$HOST_CFLAGS"
	TARGET_CXXFLAGS="$HOST_CXXFLAGS"
	TARGET_LDFLAGS="$HOST_LDFLAGS"
else
	HOST_CFLAGS="-O3 -pipe -fstack-clash-protection"
	HOST_CXXFLAGS="${HOST_CFLAGS} -Wp,-D_GLIBCXX_ASSERTIONS"
	HOST_LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now"

	TARGET_CFLAGS="$HOST_CFLAGS"
	TARGET_CXXFLAGS="$HOST_CXXFLAGS"
	TARGET_LDFLAGS="$HOST_LDFLAGS"
fi

case "${ARCH}" in
    x86_64)
        TARGET_CFLAGS="$TARGET_CFLAGS -march=x86-64 -mtune=generic -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
        TARGET_CXXFLAGS="$TARGET_CXXFLAGS -march=x86-64 -mtune=generic -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
        ;;
esac

meson_configure() {
	CFLAGS="$TARGET_CFLAGS" \
	CXXFLAGS="$TARGET_CXXFLAGS" \
	LDFLAGS="$TARGET_LDFLAGS" \
	meson_configure_noflags "$@"
}

meson_configure_noflags() {
	if [ "${DEBUG}" == "1" ]; then
		MESON_BUILD_TYPE="debug"
	else
		MESON_BUILD_TYPE="release"
	fi

	meson setup ${SOURCE_DIR} ${BUILD_DIR} \
		--cross-file "${SUPPORT_DIR}/meson-${ARCH}.txt" \
		--prefix=${PREFIX} \
		--sysconfdir=${ETC_DIR} \
		--localstatedir=${VAR_DIR} \
		--libdir=${LIB_DIR} \
		--sbindir=${SBIN_DIR} \
		--buildtype=${MESON_BUILD_TYPE} \
		"$@"
}

autotools_configure() {
    if [ -z "${CONFIGURE_SCRIPT}" ]; then
        CONFIGURE_SCRIPT="${SOURCE_DIR}/configure"
    fi
        ac_cv_func_malloc_0_nonnull=yes \
        ac_cv_func_calloc_0_nonnull=yes \
        ac_cv_func_realloc_0_nonnull=yes \
    ${CONFIGURE_SCRIPT} \
        --host=${OS_TRIPLET} \
        --with-sysroot=${SYSROOT_DIR} \
        --prefix=${PREFIX} \
        --sysconfdir=${ETC_DIR} \
        --localstatedir=${VAR_DIR} \
        --bindir=${BIN_DIR} \
        --sbindir=${SBIN_DIR} \
        --libdir=${LIB_DIR} \
        --enable-shared \
        "$@"
}
