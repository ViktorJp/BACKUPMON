#!/bin/sh
# Last modifed: August 9, 2023

USERNAME="**********"
PASSWORD="**********"
UNC="\\\\192.168.189.5\\users"
EXTDRIVE="/tmp/mnt/WDCloud"
BKDIR="/router/AX88UBackup"
DAY="$(date +%d)"
USBDRIVE="/tmp/mnt/$(nvram get usb_path_sda1_label)"

if ! [ -d $EXTDRIVE ]; then
    mkdir -p $EXTDRIVE
    chmod 777 $EXTDRIVE
fi

if ! mount | grep $EXTDRIVE > /dev/null 2>&1; then
    modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
    mount -t cifs $UNC $EXTDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"
    sleep 5
fi

if [ -n "`mount | grep $EXTDRIVE`" ]; then
  
    if ! [ -d "${EXTDRIVE}${BKDIR}" ]; then mkdir -p "${EXTDRIVE}${BKDIR}"; fi
    if ! [ -d "${EXTDRIVE}${BKDIR}/${DAY}" ]; then mkdir -p "${EXTDRIVE}${BKDIR}/${DAY}"; fi

    [ -f ${EXTDRIVE}${BKDIR}/${DAY}/jffs.tar* ] && rm ${EXTDRIVE}${BKDIR}/${DAY}/jffs.tar*
    [ -f ${EXTDRIVE}${BKDIR}/${DAY}/USBDrive.tar* ] && rm ${EXTDRIVE}${BKDIR}/${DAY}/USBDrive.tar*
  
    tar -czf ${EXTDRIVE}${BKDIR}/${DAY}/jffs.tar.gz -C /jffs . >/dev/null
    logger "Script ImageUSB: Finished backing up jffs to ${EXTDRIVE}${BKDIR}/${DAY}/jffs.tar.gz"
  
    tar -zcf ${EXTDRIVE}${BKDIR}/${DAY}/USBDrive.tar.gz -C $USBDRIVE . >/dev/null
    logger "Script ImageUSB: Finished backing up USB Key to ${EXTDRIVE}${BKDIR}/${DAY}/USBDrive.tar.gz"

    sleep 10 
    umount $EXTDRIVE
else
    echo "Failed to run ImageUSB script as mount failed"
fi
