#!/bin/sh -e

NIC="virtio"
VGA="qxl"
QEMUSYS="$(which qemu-system-x86_64)"
IMG="$(ls -1t *.qcow2 | head -1)"
RAM="1024M"

# support more options
# modified version of https://gist.github.com/adamhotep/895cebf290e95e613c006afbffef09d7
usage() {
    cat <<EOF
    usage: $0 (options) [(image filename)]

    --efi                  Use EFI to boot instead of legacy MBR
    --qemu-bin (path)      Path to QEMU binary, default "${QEMUSYS}"
    --ram (amount)         Amount of VM RAM, default "${RAM}"
    --no-virtio            Emulate devices that don't require virtio drivers (i.e. std VGA/pcnet NIC)
    (image filename)       QEMU image to load, defaut "${IMG}"

    Any additional QEMU arguments can be given with the EXTRA_ARGS environment variable, e.g.
        EXTRA_ARGS="-cdrom refind-cd-0.11.4.iso -boot d" $0
EOF
    exit
}

reset=true
for arg in "$@"
do
    if [ -n "$reset" ]; then
      unset reset
      set --      # this resets the "$@" array so we can rebuild it
    fi
    case "$arg" in
       --help)    set -- "$@" -h ;;
       --efi)   set -- "$@" -e ;;
       --pcnet)   set -- "$@" -p ;;
       --qemu-bin) set -- "$@" -b ;;
       --ram) set -- "$@" -m ;;
       --no-virtio)   set -- "$@" -n ;;
       # pass through anything else
       *)         set -- "$@" "$arg" ;;
    esac
done
# now we can process with getopt
while getopts ":hepb:m:n" opt; do
    case $opt in
        h)  usage ;;
        e) EFIBOOT="T" ;;
#        p) NIC="pcnet" ;;
        p) NIC="rtl8139" ;;
        b) QEMUSYS=$OPTARG ;;
        m) RAM=$OPTARG ;;
        n) NIC="pcnet" ; VGA="std" ;;
        \?) usage ;;
        :)
        echo "option -$OPTARG requires an argument"
        usage
        ;;
    esac
done
shift $((OPTIND-1))

# If there's a positional argument, then use this as image name
[ -n "$1" ] && { IMG="$1"; shift; }

EXTRA_ARGS="${EXTRA_ARGS-}"

if [ "$NIC" = "virtio" ] || [ "$VGA" = "qxl" ]; then
    LOCAL_ISO="$(ls -1t virtio*.iso | head -1)" 2>/dev/null
    if [ -n "${LOCAL_ISO}" ]; then
        echo "Using local ISO file ${LOCAL_ISO}"
        EXTRA_ARGS="${EXTRA_ARGS} -cdrom ${LOCAL_ISO}"
    elif [ -e "/usr/share/virtio-win/virtio-win.iso" ]; then
        # RH now have a package
        echo "Using ISO from virtio-win package."
        EXTRA_ARGS="${EXTRA_ARGS} -cdrom /usr/share/virtio-win/virtio-win.iso"
    else
        echo Fetching virtIO drivers...
        wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
        EXTRA_ARGS="${EXTRA_ARGS} -cdrom virtio-win.iso"
    fi
fi

OVMF_BIN="${OVMF_BIN-/usr/share/qemu/OVMF.fd}"
if [ -n "${EFIBOOT-}" ]; then
    [ -f "${OVMF_BIN}" ] || {
        echo "${OVMF_BIN} is not avialable, install the ovmf package or set OVMF_BIN to the location of OVMF.fd"
        exit 1
    }
    EXTRA_ARGS="${EXTRA_ARGS} -bios ${OVMF_BIN}"
fi

$QEMUSYS -enable-kvm \
    -cpu host \
    -drive "file=$IMG" \
    ${EXTRA_ARGS} \
    -netdev user,id=guesttohost,restrict=on,smb=/var/local/vm/shared \
    -device $NIC,netdev=guesttohost \
    -m "$RAM" \
    -usb -device usb-ehci,id=ehci \
    -device usb-tablet \
    -monitor stdio \
    -vga "${VGA}" \
    -snapshot -no-shutdown
