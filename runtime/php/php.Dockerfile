# We use the compiler image we built in order to compile the libraries
# and executables required for the base bref image.

FROM bref/runtime/compiler:latest as php_builder

# Use the bash shell, instead of /bin/sh
SHELL ["/bin/bash", "-c"]

# We need a base path for all the sourcecode we will build from.
ENV BUILD_DIR="/tmp/build"

# We need a base path for the builds to install to. This path must
# match the path that bref will be unpackaged to in Lambda.
ENV INSTALL_DIR="/opt/bref"

# Apply stack smash protection to functions using local buffers and alloca()
# ## # Enable size optimization (-Os)
# # Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# # Adds GNU HASH segments to generated executables (this is used if present, and is much faster than sysv hash; in this configuration, sysv hash is also generated)

# We need some default compiler variables setup
ENV PKG_CONFIG_PATH="${INSTALL_DIR}/lib64/pkgconfig:${INSTALL_DIR}/lib/pkgconfig" \
    PKG_CONFIG="/usr/bin/pkg-config" \
    PATH="${INSTALL_DIR}/bin:${PATH}"


ENV LD_LIBRARY_PATH="${INSTALL_DIR}/lib64:${INSTALL_DIR}/lib"

# Ensure we have all the directories we require in the container.
RUN mkdir -p ${BUILD_DIR}  \
    ${INSTALL_DIR}/bin \
    ${INSTALL_DIR}/doc \
    ${INSTALL_DIR}/etc/php \
    ${INSTALL_DIR}/etc/php/conf.d \
    ${INSTALL_DIR}/include \
    ${INSTALL_DIR}/lib \
    ${INSTALL_DIR}/lib64 \
    ${INSTALL_DIR}/libexec \
    ${INSTALL_DIR}/sbin \
    ${INSTALL_DIR}/share


###############################################################################
# ZLIB Build
# https://github.com/madler/zlib/releases
# Needed for:
#   - openssl
#   - php
# Used By:
#   - xml2
ARG zlib
ENV VERSION_ZLIB=${zlib}
ENV ZLIB_BUILD_DIR=${BUILD_DIR}/xml2

RUN set -xe; \
    mkdir -p ${ZLIB_BUILD_DIR}; \
# Download and upack the source code
    curl -Ls  http://zlib.net/zlib-${VERSION_ZLIB}.tar.xz \
  | tar xJC ${ZLIB_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${ZLIB_BUILD_DIR}/

# Configure the build
RUN set -xe; \
    make distclean \
 && CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./configure \
    --prefix=${INSTALL_DIR} \
    --64

RUN set -xe; \
    make install \
 && rm ${INSTALL_DIR}/lib/libz.a

###############################################################################
# OPENSSL Build
# https://github.com/openssl/openssl/releases
# Needs:
#   - zlib
# Needed by:
#   - php
ARG openssl
ENV VERSION_OPENSSL=${openssl}
ENV OPENSSL_BUILD_DIR=${BUILD_DIR}/xml2
ENV CA_BUNDLE_SOURCE="https://curl.haxx.se/ca/cacert.pem"
ENV CA_BUNDLE="${INSTALL_DIR}/ssl/cert.pem"


RUN set -xe; \
    mkdir -p ${OPENSSL_BUILD_DIR}; \
# Download and upack the source code
    curl -Ls  https://github.com/openssl/openssl/archive/OpenSSL_${VERSION_OPENSSL//./_}.tar.gz \
  | tar xzC ${OPENSSL_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${OPENSSL_BUILD_DIR}/


# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./config \
        --prefix=${INSTALL_DIR} \
        --openssldir=${INSTALL_DIR}/ssl \
        --release \
        no-tests \
        shared \
        zlib

RUN set -xe; \
    make install \
 && curl -k -o ${CA_BUNDLE} ${CA_BUNDLE_SOURCE}

###############################################################################
# LIBSSH2 Build
# https://github.com/libssh2/libssh2/releases/
# Needs:
#   - zlib
#   - OpenSSL
# Needed by:
#   - curl
ARG libssh2
ENV VERSION_LIBSSH2=${libssh2}
ENV LIBSSH2_BUILD_DIR=${BUILD_DIR}/libssh2

RUN set -xe; \
    mkdir -p ${LIBSSH2_BUILD_DIR}/bin; \
    # Download and upack the source code
    curl -Ls https://github.com/libssh2/libssh2/releases/download/libssh2-${VERSION_LIBSSH2}/libssh2-${VERSION_LIBSSH2}.tar.gz \
  | tar xzC ${LIBSSH2_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${LIBSSH2_BUILD_DIR}/bin/

# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    cmake .. \
    -DBUILD_SHARED_LIBS=ON \
    -DCRYPTO_BACKEND=OpenSSL \
    -DENABLE_ZLIB_COMPRESSION=ON \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
    -DCMAKE_BUILD_TYPE=RELEASE

RUN set -xe; \
    cmake  --build . --target install

###############################################################################
# CURL Build
# # https://github.com/curl/curl/releases/
# # Needs:
# #   - zlib
# #   - OpenSSL
# #   - curl
# # Needed by:
# #   - php
ARG curl
ENV VERSION_CURL=${curl}
ENV CURL_BUILD_DIR=${BUILD_DIR}/curl

RUN set -xe; \
            mkdir -p ${CURL_BUILD_DIR}/bin; \
curl -Ls https://github.com/curl/curl/archive/curl-${VERSION_CURL//./_}.tar.gz \
| tar xzC ${CURL_BUILD_DIR} --strip-components=1


WORKDIR  ${CURL_BUILD_DIR}/

RUN set -xe; \
    ./buildconf \
 && CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./configure \
    --prefix=${INSTALL_DIR} \
    --with-ca-bundle=${CA_BUNDLE} \
    --enable-shared \
    --disable-static \
    --enable-optimize \
    --disable-warnings \
    --disable-dependency-tracking \
    --with-zlib \
    --enable-http \
    --enable-ftp  \
    --enable-file \
    --enable-ldap \
    --enable-ldaps  \
    --enable-proxy  \
    --enable-tftp \
    --enable-ipv6 \
    --enable-openssl-auto-load-config \
    --enable-cookies \
    --with-gnu-ld \
    --with-ssl \
    --with-libssh2


RUN set -xe; \
    make install

###############################################################################
# LIBXML2 Build
# https://github.com/GNOME/libxml2/releases
# Uses:
#   - zlib
# Needed by:
#   - php
ARG libxml2
ENV VERSION_XML2=${libxml2}
ENV XML2_BUILD_DIR=${BUILD_DIR}/xml2

RUN set -xe; \
    mkdir -p ${XML2_BUILD_DIR}; \
# Download and upack the source code
    curl -Ls http://xmlsoft.org/sources/libxml2-${VERSION_XML2}.tar.gz \
  | tar xzC ${XML2_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${XML2_BUILD_DIR}/

# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./configure \
    --prefix=${INSTALL_DIR} \
    --with-sysroot=${INSTALL_DIR} \
    --enable-shared \
    --disable-static \
    --with-html \
    --with-history \
    --enable-ipv6=no \
    --with-icu \
    --with-zlib=${INSTALL_DIR} \
    --without-python

RUN set -xe; \
    make install \
 && cp xml2-config ${INSTALL_DIR}/bin/xml2-config

###############################################################################
# LIBZIP Build
# https://github.com/nih-at/libzip/releases
# Needed by:
#   - php
ARG libzip
ENV VERSION_ZIP=${libzip}
ENV ZIP_BUILD_DIR=${BUILD_DIR}/zip

RUN set -xe; \
    mkdir -p ${ZIP_BUILD_DIR}/bin/; \
# Download and upack the source code
    curl -Ls https://github.com/nih-at/libzip/archive/rel-${VERSION_ZIP//./-}.tar.gz \
  | tar xzC ${ZIP_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${ZIP_BUILD_DIR}/bin/

# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    cmake .. \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
    -DCMAKE_BUILD_TYPE=RELEASE

RUN set -xe; \
    cmake  --build . --target install

###############################################################################
# LIBSODIUM Build
# https://github.com/jedisct1/libsodium/releases
# Uses:
#
# Needed by:
#   - php
ARG libsodium
ENV VERSION_LIBSODIUM=${libsodium}
ENV LIBSODIUM_BUILD_DIR=${BUILD_DIR}/libsodium

RUN set -xe; \
    mkdir -p ${LIBSODIUM_BUILD_DIR}; \
# Download and upack the source code
    curl -Ls https://github.com/jedisct1/libsodium/archive/${VERSION_LIBSODIUM}.tar.gz \
  | tar xzC ${LIBSODIUM_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${LIBSODIUM_BUILD_DIR}/

# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./autogen.sh \
&& ./configure --prefix=${INSTALL_DIR}

RUN set -xe; \
    make install

###############################################################################
# Postgres Build
# https://github.com/postgres/postgres/releases/
# Needs:
#   - OpenSSL
# Needed by:
#   - php
ARG postgres
ENV VERSION_POSTGRES=${postgres}
ENV POSTGRES_BUILD_DIR=${BUILD_DIR}/postgres

RUN set -xe; \
    mkdir -p ${POSTGRES_BUILD_DIR}/bin; \
    curl -Ls https://github.com/postgres/postgres/archive/REL${VERSION_POSTGRES//./_}.tar.gz \
    | tar xzC ${POSTGRES_BUILD_DIR} --strip-components=1


WORKDIR  ${POSTGRES_BUILD_DIR}/

RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./configure --prefix=${INSTALL_DIR} --with-openssl --without-readline

RUN set -xe; cd ${POSTGRES_BUILD_DIR}/src/interfaces/libpq && make && make install
RUN set -xe; cd ${POSTGRES_BUILD_DIR}/src/bin/pg_config && make && make install
RUN set -xe; cd ${POSTGRES_BUILD_DIR}/src/backend && make generated-headers
RUN set -xe; cd ${POSTGRES_BUILD_DIR}/src/include && make install

###############################################################################
# PHP Build
# https://github.com/php/php-src/releases
# Needs:
#   - zlib
#   - libxml2
#   - openssl
#   - readline
#   - sodium

ARG php
# Setup Build Variables
ENV VERSION_PHP=${php}
ENV PHP_BUILD_DIR=${BUILD_DIR}/php

RUN set -xe; \
    mkdir -p ${PHP_BUILD_DIR}; \
# Download and upack the source code
    curl -Ls https://github.com/php/php-src/archive/php-${VERSION_PHP}.tar.gz \
  | tar xzC ${PHP_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${PHP_BUILD_DIR}/

# Install some dev files for using old libraries already on the system
# readline-devel : needed for the --with-libedit flag
# gettext-devel : needed for the --with-gettext flag
# libicu-devel : needed for
RUN LD_LIBRARY_PATH= yum install -y readline-devel gettext-devel libicu-devel

# Configure the build
# -fstack-protector-strong : Be paranoid about stack overflows
# -fpic : Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# -fpie : Support Address Space Layout Randomization (see -fpic)
# -0s : Optimize for smallest binaries possible.
# -I : Add the path to the list of directories to be searched for header files during preprocessing.
# --enable-option-checking=fatal: make sure invalid --configure-flags are fatal errors instead of just warnings
# --enable-ftp: because ftp_ssl_connect() needs ftp to be compiled statically (see https://github.com/docker-library/php/issues/236)
# --enable-mbstring: because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
# --enable-maintainer-zts: build PHP as ZTS (Zend Thread Safe) to be able to use pthreads
# --with-zlib and --with-zlib-dir: See https://stackoverflow.com/a/42978649/245552
# --enable-opcache-file: allows to use the `opcache.file_cache` option
#
RUN set -xe \
 && ./buildconf --force \
 && CFLAGS="-fstack-protector-strong -fpic -fpie -Os -I${INSTALL_DIR}/include -I/usr/include -ffunction-sections -fdata-sections" \
    CPPFLAGS="-fstack-protector-strong -fpic -fpie -Os -I${INSTALL_DIR}/include -I/usr/include -ffunction-sections -fdata-sections" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib -Wl,-O1 -Wl,--strip-all -Wl,--hash-style=both -pie" \
    ./configure \
        --build=x86_64-pc-linux-gnu \
        --prefix=${INSTALL_DIR} \
        --enable-option-checking=fatal \
        --enable-maintainer-zts \
        --with-config-file-path=${INSTALL_DIR}/etc/php \
        --with-config-file-scan-dir=${INSTALL_DIR}/etc/php/conf.d:/var/task/php/conf.d \
        --enable-fpm \
        --disable-cgi \
        --enable-cli \
        --disable-phpdbg \
        --disable-phpdbg-webhelper \
        --with-sodium \
        --with-readline \
        --with-openssl \
        --with-zlib=${INSTALL_DIR} \
        --with-zlib-dir=${INSTALL_DIR} \
        --with-curl \
        --enable-exif \
        --enable-ftp \
        --enable-soap \
        --with-gettext \
        --enable-mbstring \
        --with-pdo-mysql=shared,mysqlnd \
        --enable-pcntl \
        --enable-zip \
        --with-pdo-pgsql=shared,${INSTALL_DIR} \
        --enable-intl=shared \
        --enable-opcache-file
RUN make -j $(nproc)
# Run `make install` and override PEAR's PHAR URL because pear.php.net is down
RUN set -xe; \
 make install PEAR_INSTALLER_URL='https://github.com/pear/pearweb_phars/raw/master/install-pear-nozlib.phar'; \
 { find ${INSTALL_DIR}/bin ${INSTALL_DIR}/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; }; \
 make clean; \
 cp php.ini-production ${INSTALL_DIR}/etc/php/php.ini

RUN pecl install mongodb
RUN pecl install igbinary
RUN pecl install APCu

RUN pecl install --onlyreqdeps --nobuild redis && cd "$(pecl config-get temp_dir)/redis" && phpize && ./configure --enable-redis-igbinary && make && make install

RUN set -xe; \
    curl -Ls https://elasticache-downloads.s3.amazonaws.com/ClusterClient/PHP-7.0/latest-64bit \
  | tar xzC $(php-config --extension-dir) --strip-components=1

ENV PTHREADS_BUILD_DIR=${BUILD_DIR}/pthreads

# Build from master because there are no pthreads release compatible with PHP 7.3
RUN set -xe; \
    mkdir -p ${PTHREADS_BUILD_DIR}/bin; \
    curl -Ls https://github.com/krakjoe/pthreads/archive/master.tar.gz \
    | tar xzC ${PTHREADS_BUILD_DIR} --strip-components=1

WORKDIR  ${PTHREADS_BUILD_DIR}/

RUN set -xe; \
    phpize \
 && ./configure \
 && make \
 && make install


 RUN set -xe; \
     cd /tmp;\
     curl -Ls https://github.com/phalcon/cphalcon/archive/v3.4.2.tar.gz \
     | tar xzC . \
     && cd cphalcon* && cd build && ./install && cd /tmp && rm -rf /tmp/cphalcon*
     RUN echo 'ip_resolve=4' >> /etc/yum.conf


RUN LD_LIBRARY_PATH= yum install -y freetype-devel libjpeg-turbo-devel libpng-devel libwebp-devel libX11-devel libXpm-devel wget
RUN echo 'ip_resolve=4' >> /etc/yum.conf

ENV IMAGICK_BUILD_DIR=${BUILD_DIR}/imagick
RUN mkdir -p ${IMAGICK_BUILD_DIR}
# Compile libde265 (libheif dependency)
WORKDIR ${IMAGICK_BUILD_DIR}
RUN wget https://github.com/strukturag/libde265/releases/download/v1.0.5/libde265-1.0.5.tar.gz -O libde265.tar.gz
RUN tar xzf libde265.tar.gz
WORKDIR ${IMAGICK_BUILD_DIR}/libde265-1.0.5
RUN ./configure --prefix ${INSTALL_DIR} --exec-prefix ${INSTALL_DIR}
RUN make -j $(nproc)
RUN make install

# Compile libheif
WORKDIR ${IMAGICK_BUILD_DIR}
RUN wget https://github.com/strukturag/libheif/releases/download/v1.6.2/libheif-1.6.2.tar.gz -O libheif.tar.gz
RUN tar xzf libheif.tar.gz
WORKDIR ${IMAGICK_BUILD_DIR}/libheif-1.6.2
RUN ./configure --prefix ${INSTALL_DIR} --exec-prefix ${INSTALL_DIR}
RUN make -j $(nproc)
RUN make install

# Compile the ImageMagick library
WORKDIR ${IMAGICK_BUILD_DIR}
RUN wget https://github.com/ImageMagick/ImageMagick6/archive/6.9.10-68.tar.gz -O ImageMagick.tar.gz
RUN tar xzf ImageMagick.tar.gz
WORKDIR ${IMAGICK_BUILD_DIR}/ImageMagick6-6.9.10-68
RUN ./configure --prefix ${INSTALL_DIR} --exec-prefix ${INSTALL_DIR} --with-webp --with-heic --disable-static
RUN make -j $(nproc)
RUN make install

# Compile the php imagick extension
WORKDIR ${IMAGICK_BUILD_DIR}
RUN pecl download imagick
RUN tar xzf imagick-3.4.4.tgz
WORKDIR ${IMAGICK_BUILD_DIR}/imagick-3.4.4
RUN phpize
RUN ./configure --with-imagick=${INSTALL_DIR}
RUN make -j $(nproc)
RUN make install
RUN cp `php-config --extension-dir`/imagick.so /tmp/imagick.so

# FROM lambci/lambda:provided
# FROM bref/build-php-72 as ext

# The ImageMagick libraries needed by the extension
# COPY --from=ext /opt/bref/lib/libMagickWand-6.Q16.so.6.0.0 /opt/bref/lib/libMagickWand-6.Q16.so.6
# COPY --from=ext /opt/bref/lib/libMagickCore-6.Q16.so.6.0.0 /opt/bref/lib/libMagickCore-6.Q16.so.6

# # ImageMagick dependencies
# COPY --from=ext /usr/lib64/libwebp.so.4.0.2 /opt/bref/lib/libwebp.so.4
# COPY --from=ext /opt/bref/lib/libde265.so.0.0.12 /opt/bref/lib/libde265.so.0
# COPY --from=ext /opt/bref/lib/libheif.so.1.6.2 /opt/bref/lib/libheif.so.1

# COPY --from=ext /tmp/imagick.so /opt/bref-extra/imagick.so
RUN LD_LIBRARY_PATH=  cp /usr/lib64/libwebp.so.4.0.2 /opt/bref/lib/libwebp.so.4
# Strip all the unneeded symbols from shared libraries to reduce size.
RUN find ${INSTALL_DIR} -type f -name "*.so*" -o -name "*.a"  -exec strip --strip-unneeded {} \;
RUN find ${INSTALL_DIR} -type f -executable -exec sh -c "file -i '{}' | grep -q 'x-executable; charset=binary'" \; -print|xargs strip --strip-all

# Cleanup all the binaries we don't want.
RUN find /opt/bref/bin -mindepth 1 -maxdepth 1 ! -name "php" ! -name "pecl" -exec rm {} \+

# Cleanup all the files we don't want either
# We do not support running pear functions in Lambda
RUN rm -rf /opt/bref/lib/php/PEAR \
  rm -rf /opt/bref/share/doc \
  rm -rf /opt/bref/share/man \
  rm -rf /opt/bref/share/gtk-doc \
  rm -rf /opt/bref/include \
  rm -rf /opt/bref/tests \
  rm -rf /opt/bref/doc \
  rm -rf /opt/bref/docs \
  rm -rf /opt/bref/man \
  rm -rf /opt/bref/www \
  rm -rf /opt/bref/cfg \
  rm -rf /opt/bref/libexec \
  rm -rf /opt/bref/var \
  rm -rf /opt/bref/data

# Symlink all our binaries into /opt/bin so that Lambda sees them in the path.
RUN mkdir -p /opt/bin
RUN ln -s /opt/bref/bin/* /opt/bin
RUN ln -s /opt/bref/sbin/* /opt/bin


# Now we get rid of everything that is unnecessary. All the build tools, source code, and anything else
# that might have created intermediate layers for docker. Back to base AmazonLinux we started with.
FROM amazonlinux:latest
ENV INSTALL_DIR="/opt/bref"
ENV PATH="/opt/bin:${PATH}" \
    LD_LIBRARY_PATH="${INSTALL_DIR}/lib64:${INSTALL_DIR}/lib"

RUN mkdir -p /opt
WORKDIR /opt
# Copy everything we built above into the same dir on the base AmazonLinux container.
COPY --from=php_builder /opt /opt
RUN echo 'ip_resolve=4' >> /etc/yum.conf

# Install zip: we will need it later to create the layers as zip files
RUN LD_LIBRARY_PATH= yum -y install zip
