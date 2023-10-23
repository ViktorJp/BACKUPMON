#!/bin/sh
# Original: August 9, 2023 @Jeffrey Young
# Last modified: October 16, 2023 @Viktor Jaep
# This version handles exactly 4 USB drive partitions

USERNAME="**********"
PASSWORD="**********"
UNC="\\\\192.168.189.5\\users"
EXTDRIVE="/tmp/mnt/WDCloud"
BKDIR="/router/AX88UBackup"
DAY="$(date +%d)"
USBDRIVEP1="/tmp/mnt/$(nvram get usb_path_sda1_label)"
USBDRIVEP2="/tmp/mnt/$(nvram get usb_path_sda2_label)"
USBDRIVEP3="/tmp/mnt/$(nvram get usb_path_sda3_label)"
USBDRIVEP4="/tmp/mnt/$(nvram get usb_path_sda4_label)"

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
    [ -f ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP1.tar* ] && rm ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP1.tar*
    [ -f ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP2.tar* ] && rm ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP2.tar*
    [ -f ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP3.tar* ] && rm ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP3.tar*
    [ -f ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP4.tar* ] && rm ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP4.tar*
 
    tar -czf ${EXTDRIVE}${BKDIR}/${DAY}/jffs.tar.gz -C /jffs . >/dev/null
    logger "Script ImageUSB: Finished backing up jffs to ${EXTDRIVE}${BKDIR}/${DAY}/jffs.tar.gz"
 
    tar -zcf ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP1.tar.gz -C $USBDRIVEP1 . >/dev/null
    logger "Script ImageUSB: Finished backing up USB Key P1 to ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP1.tar.gz"
    tar -zcf ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP2.tar.gz -C $USBDRIVEP2 . >/dev/null
    logger "Script ImageUSB: Finished backing up USB Key P2 to ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP2.tar.gz"
    tar -zcf ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP3.tar.gz -C $USBDRIVEP3 . >/dev/null
    logger "Script ImageUSB: Finished backing up USB Key P3 to ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP3.tar.gz"
    tar -zcf ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP4.tar.gz -C $USBDRIVEP4 . >/dev/null
    logger "Script ImageUSB: Finished backing up USB Key P4 to ${EXTDRIVE}${BKDIR}/${DAY}/USBDriveP4.tar.gz"

    sleep 10
    umount $EXTDRIVE
else
    echo "Failed to run ImageUSB script as mount failed"
fi
