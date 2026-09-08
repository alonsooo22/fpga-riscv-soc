FROM verilator/verilator:v5.050

USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV SYSTEMC_HOME=/usr/local/systemc-2.3.1
ENV VERILATOR_SRC=/usr/local/share/verilator/include

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        binutils-dev \
        ca-certificates \
        file \
        gcc-riscv64-unknown-elf \
        g++ \
        git \
        libelf-dev \
        binutils-riscv64-unknown-elf \
        pkg-config \
        python3 \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY systemc-2.3.1a.tar.gz /tmp/systemc-2.3.1a.tar.gz

RUN mkdir -p /tmp/systemc-src \
    && tar -xzf /tmp/systemc-2.3.1a.tar.gz --strip-components=1 -C /tmp/systemc-src \
    && cd /tmp/systemc-src \
    && ./configure --prefix="${SYSTEMC_HOME}" --enable-debug=no \
    && make -j"$(nproc)" \
    && make install \
    && sed -i '/using std::gets;/d' "${SYSTEMC_HOME}/include/systemc.h" \
    && rm -rf /tmp/systemc-src /tmp/systemc-2.3.1a.tar.gz

ENV SYSTEMC_INCLUDE=/usr/local/systemc-2.3.1/include
ENV SYSTEMC_LIBDIR=/usr/local/systemc-2.3.1/lib-linux64
ENV LD_LIBRARY_PATH=/usr/local/systemc-2.3.1/lib-linux64

WORKDIR /workspace/ultra-riscv

ENTRYPOINT ["/bin/bash"]
