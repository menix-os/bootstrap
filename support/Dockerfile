FROM opensuse/tumbleweed:latest AS base

SHELL ["/bin/bash", "-c"]

RUN zypper --non-interactive dup
RUN zypper --non-interactive install \
	# Base tools
	awk \
	bzip2 \
	diff \
	envsubst \
	git \
	help2man \
	libopenssl-3-devel \
	makeinfo \
	mdbook \
	python313 \
	python313-pip \
	rsync \
	sed \
	# Generic build systems
	make \
	meson \
	cmake \
	# Rust toolchain
	rustup \
	# GNU toolchain
	gmp-devel \
	mpfr-devel \
	mpc-devel \
	gcc \
	bison \
	flex \
	gcc-c++ \
	binutils \
	# LLVM toolchain
	llvm \
	llvm-devel \
	clang \
	lld \
	# Other build tools
	nasm \
	mold

# Install xbstrap
RUN pip3 install --break-system-packages xbstrap

# Switch to user
FROM base AS user
ARG USER=1000
RUN useradd -ms /bin/bash menix-buildenv -u $USER
USER menix-buildenv
WORKDIR /home/menix-buildenv

# Install the nightly toolchain. Also install rust-src for build-std.
RUN rustup toolchain install nightly --component rust-src
# Set a default Rust toolchain
RUN rustup default nightly

# Set a git profile for patches
RUN git config --global user.email "menix-buildenv@localhost" \
	&& git config --global user.name "menix-buildenv"

CMD ["bash"]
