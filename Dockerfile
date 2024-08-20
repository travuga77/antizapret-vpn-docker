FROM ubuntu:24.04 AS base

ENV APT_LISTCHANGES_FRONTEND=none
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /root

RUN <<-"EOT" bash -ex
    apt-get update
    apt-get install -y \
        --no-install-suggests \
        --no-install-recommends \
            ca-certificates \
            curl \
            wget \
            libnl-genl-3-dev \
            libssl-dev \
            libcap-ng-dev \
            liblz4-dev
    rm -frv /var/lib/apt/lists/*
EOT



FROM base AS openvpn

WORKDIR /src

RUN <<-"EOT" bash -ex
    apt-get update
    apt-get install -y \
        --no-install-suggests \
        --no-install-recommends \
            build-essential \
            cmake \
            gcc \
            git \
            make \
            pkg-config
    rm -frv /var/lib/apt/lists/*
EOT

RUN <<-"EOT" bash -ex
    OPENVPN_VER=2.6.12
    BASE_URL=https://raw.githubusercontent.com/Tunnelblick/Tunnelblick/master/third_party/sources/openvpn/openvpn-$OPENVPN_VER

    wget $BASE_URL/openvpn-$OPENVPN_VER.tar.gz

    tar -f *.tar.gz -zxv --strip-components=1 -C .

    patches=(
        02-tunnelblick-openvpn_xorpatch-a.diff
        03-tunnelblick-openvpn_xorpatch-b.diff
        04-tunnelblick-openvpn_xorpatch-c.diff
        05-tunnelblick-openvpn_xorpatch-d.diff
        06-tunnelblick-openvpn_xorpatch-e.diff
    )

    for patch in ${patches[@]}; do
        wget $BASE_URL/patches/$patch
        git apply $patch
    done

    ./configure \
        --enable-shared \
        --enable-static=yes \
        --disable-dependency-tracking \
        --disable-debug \
        --disable-lzo \
        --disable-plugin-auth-pam

    make -j$(nproc)
    make install DESTDIR=/dist

    rm -frv *
EOT



FROM base AS release

RUN <<-"EOT" bash -ex
    apt-get update
    apt-get install -y \
        --no-install-suggests \
        --no-install-recommends \
            bsdmainutils \
            dnsutils \
            ferm \
            gawk \
            host \
            idn \
            inetutils-ping \
            ipcalc \
            ipcalc-ng \
            iptables \
            iproute2 \
            knot-resolver \
            moreutils \
            nano \
            openssl \
            patch \
            procps \
            python3-dnslib \
            sipcalc \
            supervisor \
            vim-tiny
    rm -frv /var/lib/apt/lists/*
EOT

RUN <<-"EOT" bash -ex
    ANTIZAPRET_VER=6eae76b095ef4d719043a109c05d94900aaa3791
    ANTIZAPRET_URL=https://bitbucket.org/anticensority/antizapret-pac-generator-light/get/$ANTIZAPRET_VER.tar.gz

    EASYRSA_VER=3.2.0
    EASYRSA_URL=https://github.com/OpenVPN/easy-rsa/releases/download/v$EASYRSA_VER/EasyRSA-$EASYRSA_VER.tgz

    mkdir antizapret && curl -s -L $ANTIZAPRET_URL | tar -zxv --strip-components=1 -C $_
    mkdir easyrsa && curl -s -L $EASYRSA_URL | tar -zxv --strip-components=1 -C $_
EOT

COPY rootfs /

RUN <<-"EOF" bash -ex
    cp -rv /etc/openvpn /etc/openvpn-default

    patch antizapret/parse.sh patches/parse.patch

    sed -i "/\b\(googleusercontent\|cloudfront\|deviantart\)\b/d" /root/antizapret/config/exclude-regexp-dist.awk
    for list in antizapret/config/*-dist.txt; do
        sed -E '/^(#.*)?[[:space:]]*$/d' $list | sort | uniq | sponge $list
    done

    for list in antizapret/config/*-custom.txt; do
        rm -f $list
    done
    rm antizapret/{*.md,generate-pac.sh}

    ln -sf /root/antizapret/doall.sh /usr/bin/doall
    ln -sf /root/antizapret/dnsmap.py /usr/bin/dnsmap

    mkdir -pv /var/cache/knot-resolver
    touch /var/cache/knot-resolver/{data,lock}.mdb
    chown knot-resolver:knot-resolver -R /var/cache/knot-resolver
EOF

COPY --from=openvpn /dist /

ENTRYPOINT ["/init"]
