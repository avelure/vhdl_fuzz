FROM ubuntu:rolling

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get -y update && apt-get install -y \
    gcc-11 gcc-11-plugin-dev \
    g++ \
    clang-13 lld-13\
    git \
    make \
    automake \
    texinfo \
    bison flex \
    build-essential \
    bash-completion \
    libtool libtool-bin \
    pkg-config \
	libipt-dev \
	libunwind8-dev \
	binutils-dev \
	zlib1g-dev\
	curl \
	xz-utils \
	gnat-11 \
	nano \
	strace \
	parallel \
&& rm -rf /var/lib/apt/lists/*

WORKDIR /

# install AFL cov
RUN git clone --depth=1 https://github.com/vanhauser-thc/afl-cov /afl-cov
RUN cd /afl-cov && make install && cd ..

# install AFL
ENV LLVM_CONFIG /usr/bin/llvm-config-13
RUN git clone --depth=1 --branch=4.00c https://github.com/AFLplusplus/AFLplusplus /aflplusplus
RUN cd /aflplusplus && make all -j $(nproc) && make install && make clean

# Download GHDL source
WORKDIR /
RUN git clone --depth=1 https://github.com/ghdl/ghdl.git

# Apply patch to abort on bug
COPY ./ghdl_bug_abort.patch /ghdl
WORKDIR /ghdl
RUN patch -p1 < ./ghdl_bug_abort.patch

RUN mkdir build
WORKDIR /ghdl/build

# Configure GHDL
ENV CC /usr/local/bin/afl-gcc-fast
ENV CXX /usr/local/bin/afl-g++-fast

# With LLVM backend
# RUN ../configure --prefix=/usr/local --with-llvm-config="/usr/bin/llvm-config-13 --link-static" --disable-libghdl

# With mcode backend
RUN ../configure --prefix=/usr/local --disable-libghdl

# We must override gnatlink to pass the correct compiler
ENV GNATLINK '/usr/bin/gnatlink\ --GCC=/usr/local/bin/afl-gcc-fast'

RUN make GNATMAKE="gnatmake -j$(nproc) --GCC=/usr/local/bin/afl-gcc-fast --GNATLINK=$GNATLINK"

# Build GHDL VHDL library
RUN make install

COPY ./fuzz.sh /
RUN chmod +x /fuzz.sh

WORKDIR /
# Execute fuzzing script
