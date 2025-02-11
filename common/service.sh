#!/system/bin/sh
# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
MODDIR=${0%/*}

logfile=/data/local/tmp/emagic.log
log() {
    echo "$(date -u +"%Y-%m-%d %H:%M:%S") eMagic | ${*}" >>$logfile
    /system/bin/log -t eMagic -p i "${@}"
}

log "##################### Boot #####################"
log "Waiting for boot to complete..."


until [ -d /sdcard/Download ]; do
    sleep 10
done

# wait until zygote exists, and
pgrep zygote >/dev/null && {
    # wait until sys.boot_comlpeted returns 1
    until [ .$(getprop sys.boot_completed) = .1 ]; do
        sleep 10
    done
}

log "System boot completed!"

if [ -f "$MODDIR/ATVServices.sh" ]; then
    sleep 20
    log "Starting ATVServices.sh"
    . "$MODDIR/ATVServices.sh"
fi
