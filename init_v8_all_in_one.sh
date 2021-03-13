#!/bin/bash

# Ask Questions here:
#    https://github.com/v8-riscv/v8-riscv-tools

# Note: This script is used for the V8 RISCV Developers.
#       Users are expected to read and modify the script self.
#       If you want to get you hands dirty on v8-riscv project,
#       the better way is to follow the project's wiki page, step by step.


set -e

# NOTE: Suppose your network are not in mainland China, otherwise you may see
# some connection issues which block your way to success.

# Config: modify it if you don't like the default path.
# IMPORTANT: please assert there is no space in pwd folder, or the script may
#            does undefined behaviors.
V8_ROOT=$PWD/v8-riscv
RV_HOME=$HOME/opt/riscv
DEPOT_DIR=$PWD/depot_tools

[ -d "$DEPOT_DIR" ] || git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_DIR"

export PATH="$DEPOT_DIR:$PATH"

# I suppose you are using bash and I suppose you'd like the export.
# Comment the line below if you don't need it.

echo "export PATH='$DEPOT_DIR:$PATH'" >> ~/.bashrc

# ref: https://github.com/v8-riscv/v8/wiki/get-the-source

# if $V8_PORT exists, mkdir is intend to fail the script.
mkdir -p $V8_ROOT
cd $V8_ROOT
fetch v8

gclient sync

# Currently the RISC-V is a tier-3 backend of chromium/v8, which means
# that new commits in upstream might break riscv64 backend without
# notice. So we maintain a stable branch for RISC-V.
cd $V8_ROOT/v8
git remote | grep -q riscv || \
	git remote add riscv https://github.com/v8-riscv/v8.git
	# or alternatively using ssh if you are developer
	#git remote add riscv git@github.com:v8-riscv/v8.git
git fetch riscv
git checkout riscv/riscv64

wget -O build.patch https://raw.githubusercontent.com/v8-riscv/v8-riscv-tools/main/riscv64-cross-build.patch
git apply build.patch

# Install deps. may need sudo
# tip: remember add `--no-chromeos-fonts` if you are in mainland China
echo "Now the source code is ready."
echo "Next action is to install deps, which may need sudo permission."
echo "Open a new terminal/window and enter:"
echo
echo "$V8_ROOT/v8/build/install-build-deps.sh --no-chromeos-fonts"
echo
echo "After you get the deps installation done, Press ENTER:"
read -p "(or Ctrl-C to cancel this script:) >>>"

###########################################################
# Simulator Build
###########################################################

cd $V8_ROOT/v8
gn gen out/riscv64.sim \
    --args='is_component_build=false
    is_debug=true target_cpu="x64"
    v8_target_cpu="riscv64"
    use_goma=false goma_dir="None"'

ninja -C out/riscv64.sim -j $(nproc)

# Umcomment these lines if you want to run simulator testing
# python2 ./tools/dev/gm.py riscv64.release.check
# bash ./v8-riscv-tools/test-riscv.sh

###########################################################
# Cross Compile to RISC-V64
###########################################################

echo "Congrats! Now you just have built a V8 for RISC-V (simulator mode)!"
echo "Everything looks good!"
echo "Now we are diving into cross compilation and testing, which could be a bit painful."
echo "Feel free to stop here. Press ENTER to continue, Crtl-C to cancel:"
read -p ">>>"

# +++++++++++++++++++++++++++++++++++++++++
# RISC-V GNU Toolchain
# +++++++++++++++++++++++++++++++++++++++++

echo "Ubuntu 18.04 does not have the latest riscv64 toolchain in place."
echo "It has gcc-7 and gcc-8, while the latest is gcc-10.2"
echo "We are going to build a latest toolchain for cross building."

mkdir -p $RV_HOME

cd $V8_ROOT/
git clone https://github.com/riscv/riscv-gnu-toolchain
pushd riscv-gnu-toolchain
git submodule update --init --recursive
./configure --prefix=$RV_HOME
make linux -j $(nproc) || make linux -j 1
popd


export PATH=$PATH:$RV_HOME/bin
echo "export PATH=$PATH:$RV_HOME/bin" >> $HOME/.bashrc


# if you are using the toolchain installed by 'apt',
# then you should not run this sed script. It is only
# used for self built toolchain.
sed -i 's,riscv64-linux-gnu,riscv64-unknown-linux-gnu,' \
    $V8_ROOT/v8/build/toolchain/linux/BUILD.gn

cd $V8_ROOT/v8
gn gen out/riscv64.native.debug \
    --args='is_component_build=false
    is_debug=true target_cpu="riscv64"
    v8_target_cpu="riscv64" use_goma=false
    goma_dir="None"
    treat_warnings_as_errors=false
    symbol_level = 0'
ninja -C out/riscv64.native.debug -j $(nproc)

# Remove obj and gen files that not needed.
rm -rf out/riscv64.native.debug/obj
rm -rf out/riscv64.native.debug/gen

cd $V8_ROOT/
git clone https://github.com/qemu/qemu.git
cd qemu
git checkout v5.0.0
git submodule update -r --init -f
./configure --target-list=riscv64-softmmu && make -j $(nproc)

# optional
#sudo make install

###########################################################
# Deploy the Fedora Developer Rawhide on QEMU/RISCV64
###########################################################

cd $V8_ROOT/
# NOTE: 100G HDD space needed.
wget https://dl.fedoraproject.org/pub/alt/risc-v/repo/virt-builder-images/images/Fedora-Developer-Rawhide-20191123.n.0-fw_payload-uboot-qemu-virt-smode.elf
wget https://dl.fedoraproject.org/pub/alt/risc-v/repo/virt-builder-images/images/Fedora-Developer-Rawhide-20191123.n.0-sda.raw.xz
unxz -k Fedora-Developer-Rawhide-20191123.n.0-sda.raw.xz

# This is needed for v8 debugging, for the out/ folder has 36GB if the symbol_level remains default value, 2.

sudo apt install libguestfs-tools -y
truncate -r Fedora-Developer-Rawhide-*.raw expanded.raw
truncate -s 60G expanded.raw

# FIXME: we may not need sudo to run this three commands.
sudo virt-resize -v -x --expand /dev/sda4 Fedora-Developer-Rawhide-*.raw expanded.raw
sudo virt-filesystems --long -h --all -a expanded.raw
sudo virt-df -h -a expanded.raw

echo "Now we are ready to Start QEMU."
echo
echo "Open a new terminal (Tab) to start QEMU"
echo "copy these commands in the new terminal:"
echo
echo "export VER=20191123.n.0"
echo "$V8_ROOT/qemu/riscv64-softmmu/qemu-system-riscv64 \\"
echo "  -nographic \\"
echo "  -machine virt \\"
echo "  -smp 4 \\"
echo "  -m 4G \\"
echo "  -kernel Fedora-Developer-Rawhide-${VER}-fw_payload-uboot-qemu-virt-smode.elf \\"
echo "  -object rng-random,filename=/dev/urandom,id=rng0 \\"
echo "  -device virtio-rng-device,rng=rng0 \\"
echo "  -device virtio-blk-device,drive=hd0 \\"
echo "  -drive file=expanded.raw,format=raw,id=hd0 \\"
echo "  -device virtio-net-device,netdev=usernet \\"
echo "  -netdev user,id=usernet,hostfwd=tcp::3333-:22"
echo
echo "Tip: You can quit qemu by pressing 'Ctrl-a x' key sequence."
echo "Tip: fedora forbid root password login. Either upload your pubkey into"
echo "     ROOT/.ssh/authorized_keys or add 'PermitRootLogin=yes' in /etc/ssh/sshd_config"
read -p "Ready? Then Press ENTER:"

scp -r -P 3333 $V8_ROOT/v8/out/riscv64.native.debug $V8_ROOT/v8/tools $V8_ROOT/v8/test root@localhost:~/
ssh -p 3333 root@localhost python2 ./tools/run-tests.py \
    --outdir=riscv64.native.debug \
    -p verbose --report \
    cctest \
    unittests \
    wasm-api-tests \
    mjsunit \
    intl \
    message \
    debugger \
    inspector \
    mkgrokdump 2>&1 | tee v8.build.test.log
