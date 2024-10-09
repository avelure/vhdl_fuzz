FROM ubuntu:22.04

ENV LLVM_VERSION=15
ENV GCC_VERSION=12

ENV DEBIAN_FRONTEND noninteractive
ENV NO_ARCH_OPT=1
ENV IS_DOCKER=1

ENV BUILD_DEPS \
	git \
	ca-certificates \
	make \
	patch

ENV BUILD_DEPS_AFL \
    gcc-${GCC_VERSION} g++-${GCC_VERSION} gcc-${GCC_VERSION}-plugin-dev \
    clang-${LLVM_VERSION} clang-tools-${LLVM_VERSION} libc++1-${LLVM_VERSION} \
    libc++-${LLVM_VERSION}-dev libc++abi1-${LLVM_VERSION} libc++abi-${LLVM_VERSION}-dev \
    libclang1-${LLVM_VERSION} libclang-${LLVM_VERSION}-dev \
    libclang-common-${LLVM_VERSION}-dev libclang-cpp${LLVM_VERSION} \
    libclang-cpp${LLVM_VERSION}-dev liblld-${LLVM_VERSION} \
    liblld-${LLVM_VERSION}-dev liblldb-${LLVM_VERSION} liblldb-${LLVM_VERSION}-dev \
    libllvm${LLVM_VERSION} libomp-${LLVM_VERSION}-dev libomp5-${LLVM_VERSION} \
    lld-${LLVM_VERSION} lldb-${LLVM_VERSION} llvm-${LLVM_VERSION} \
    llvm-${LLVM_VERSION}-dev llvm-${LLVM_VERSION}-runtime llvm-${LLVM_VERSION}-tools

ENV BUILD_DEPS_GHDL_MCODE \
	gnat-${GCC_VERSION} \
	zlib1g-dev

ENV PERSISTENT_DEPS_GHDL_LLVM \
	gcc-${GCC_VERSION} \
	libgnat-${GCC_VERSION} \
	libllvm${LLVM_VERSION} \
	libc-dev \
	zlib1g-dev
	
ENV PERSISTENT_DEPS_GHDL_MCODE \
	gcc-${GCC_VERSION} \
	libgnat-${GCC_VERSION}

ENV PERSISTENT_DEPS_RUN \
	parallel \
	nano

RUN apt-get -y update && apt-get install -y --no-install-recommends \
    $BUILD_DEPS $BUILD_DEPS_AFL $BUILD_DEPS_GHDL_MCODE \
	$PERSISTENT_DEPS_GHDL_MCODE $PERSISTENT_DEPS_RUN \
    && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${GCC_VERSION} 0 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${GCC_VERSION} 0 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${LLVM_VERSION} 0 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${LLVM_VERSION} 0

ENV LLVM_CONFIG /usr/bin/llvm-config-${LLVM_VERSION}

## Install AFL cov
WORKDIR /

# Fetch latest commit, this avoids building from cache when there is new changes
ADD "https://api.github.com/repos/vanhauser-thc/afl-cov/git/refs/heads/master" afl-cov_latest_commit

RUN git clone --depth=1 https://github.com/vanhauser-thc/afl-cov /afl-cov \
    && (cd afl-cov && make install) && rm -rf afl-cov

## Install AFL
WORKDIR /
ARG AFLPLUSPLUS_BRANCH=stable
ARG CC=gcc-$GCC_VERSION
ARG CXX=g++-$GCC_VERSION
# Compile with performance options that make the binary not transferable to other systems. Recommended (except on macOS)!
ARG PERFORMANCE=1
# Fetch latest commit, this avoids building from cache when there is new changes
ADD "https://api.github.com/repos/AFLplusplus/AFLplusplus/git/refs/heads/${AFLPLUSPLUS_BRANCH}" afl_latest_commit
RUN git clone --depth=1 --branch=${AFLPLUSPLUS_BRANCH} https://github.com/AFLplusplus/AFLplusplus /aflplusplus \
    && (cd /aflplusplus && make all -j $(nproc) && make install) \
	&& rm -rf aflplusplus

## Download GHDL source
WORKDIR /
# Fetch latest commit, this avoids building from cache when there is new changes
ADD "https://api.github.com/repos/ghdl/ghdl/git/refs/heads/master" ghdl_latest_commit
RUN git clone --depth=1 https://github.com/ghdl/ghdl /ghdl && mkdir /ghdl/build

# Apply patch to abort on bug
COPY ./ghdl_bug_abort.patch /ghdl
RUN cd /ghdl && patch -p1 < ./ghdl_bug_abort.patch

## Configure GHDL
ENV CC /usr/local/bin/afl-gcc-fast
ENV CXX /usr/local/bin/afl-g++-fast
ENV GNATMAKE "gnatmake --GCC=/usr/local/bin/afl-gcc-fast --GNATLINK='/usr/bin/gnatlink --GCC=/usr/local/bin/afl-gcc-fast'"

# With LLVM backend
# RUN cd /ghdl/build && ../configure --prefix=/usr/local --with-llvm-config="/usr/bin/llvm-config-${LLVM_VERSION} --link-static" --disable-libghdl --disable-synth && make GNATMAKE="$GNATMAKE -j$(nproc)" && make install

# With mcode backend
RUN cd /ghdl/build && ../configure --prefix=/usr/local --disable-libghdl --disable-synth \
    && make GNATMAKE="$GNATMAKE -j$(nproc)" && make install

COPY ./fuzz.sh /
RUN chmod +x /fuzz.sh

COPY ./rename.sh /
RUN chmod +x /rename.sh

COPY ./find_vhdl_files.sh /
RUN chmod +x /find_vhdl_files.sh
