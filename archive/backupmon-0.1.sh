#!/bin/sh
# Functional Backup Script by: @Jeffrey Young, August 9, 2023
# Heavily modified and restore functionality added by @Viktor Jaep, 2023

USERNAME="admin"
PASSWORD="admin"
UNC="\\\\192.168.36.19\\Backups"
UNCDRIVE="/tmp/mnt/server"
BKDIR="/router/GTAX6000Backup"
EXCLUSION="/jffs/scripts/exclusions.txt"
DAY="$(date +%d)"
EXTDRIVE="/tmp/mnt/$(nvram get usb_path_sda1_label)"

# Color variables
CBlack="\e[1;30m"
InvBlack="\e[1;40m"
CRed="\e[1;31m"
InvRed="\e[1;41m"
CGreen="\e[1;32m"
InvGreen="\e[1;42m"
CDkGray="\e[1;90m"
InvDkGray="\e[1;100m"
InvLtGray="\e[1;47m"
CYellow="\e[1;33m"
InvYellow="\e[1;43m"
CBlue="\e[1;34m"
InvBlue="\e[1;44m"
CMagenta="\e[1;35m"
CCyan="\e[1;36m"
InvCyan="\e[1;46m"
CWhite="\e[1;37m"
InvWhite="\e[1;107m"
CClear="\e[0m"

# -------------------------------------------------------------------------------------------------------------------------

promptyn () {   # No defaults, just y or n
  while true; do
    read -p "[y/n]? " -n 1 -r yn
      case "${yn}" in
        [Yy]* ) return 0 ;;
        [Nn]* ) return 1 ;;
        * ) echo -e "\n Please answer y or n.";;
      esac
  done
}

# Preparebar and Progressbar is a script that provides a nice progressbar to show script activity
preparebar() {
  # $1 - bar length
  # $2 - bar char
  barlen=$1
  barspaces=$(printf "%*s" "$1")
  barchars=$(printf "%*s" "$1" | tr ' ' "$2")
}

progressbaroverride() {
  # $1 - number (-1 for clearing the bar)
  # $2 - max number
  # $3 - system name
  # $4 - measurement
  # $5 - standard/reverse progressbar
  # $6 - alternate display values
  # $7 - alternate value for progressbar exceeding 100%

  insertspc=" "

  if [ $1 -eq -1 ]; then
    printf "\r  $barspaces\r"
  else
      barch=$(($1*barlen/$2))
      barsp=$((barlen-barch))
      progr=$((100*$1/$2))
  fi

    if [ ! -z $6 ]; then AltNum=$6; else AltNum=$1; fi

      printf "  ${CWhite}${InvDkGray}$AltNum${4} / ${progr}%%${CClear} ${CGreen}[Selection? ${InvGreen} ${CClear}${CGreen}]\r${CClear}" "$barchars" "$barspaces"

    # Borrowed this wonderful keypress capturing mechanism from @Eibgrad... thank you! :)
    key_press=''; read -rsn1 -t 1 key_press < "$(tty 0>&2)"

    if [ $key_press ]; then
        case $key_press in
            [Xx]) echo ""; echo ""; sleep 1; restore;;
            'e')  # Exit gracefully
                  clear
                  echo -e "${CClear}"
                  exit 0
                  ;;
        esac
    fi

}

# -------------------------------------------------------------------------------------------------------------------------

# backup routine by @Jeffrey Young showing a great way to connect to an external network location to dump backups to
backup() {

  if ! [ -d $UNCDRIVE ]; then
      mkdir -p $UNCDRIVE
      chmod 777 $UNCDRIVE
      echo -e "${CYellow}ALERT: External Drive directory not set. Newly created under: $UNCDRIVE ${CClear}"
      sleep 3
  fi

  if ! mount | grep $UNCDRIVE > /dev/null 2>&1; then
      modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      mount -t cifs $UNC $UNCDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"
      echo -e "${CGreen}STATUS: External Drive ($UNC) mounted successfully under: $UNCDRIVE ${CClear}"
      sleep 5
  fi

  if [ -n "`mount | grep $UNCDRIVE`" ]; then

      if ! [ -d "${UNCDRIVE}${BKDIR}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}"; echo -e "${CGreen}STATUS: Backup Directory successfully created."; fi
      if ! [ -d "${UNCDRIVE}${BKDIR}/${DAY}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}/${DAY}"; echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}";fi

      [ -f ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar*
      [ -f ${UNCDRIVE}${BKDIR}/${DAY}/EXTDRIVE.tar* ] && rm ${UNCDRIVE}${BKDIR}/${DAY}/EXTDRIVE.tar*

      if ! [ -z $EXCLUSION ]; then
        tar -zcf ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
      else
        tar -zcf ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar.gz -C /jffs . >/dev/null
      fi
      logger "Backup Script: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar.gz"
      echo -e "${CGreen}STATUS: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar.gz.${CClear}"
      sleep 1

      if ! [ -z $EXCLUSION ]; then
        tar -zcf ${UNCDRIVE}${BKDIR}/${DAY}/EXTDRIVE.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
      else
        tar -zcf ${UNCDRIVE}${BKDIR}/${DAY}/EXTDRIVE.tar.gz -C $EXTDRIVE . >/dev/null
      fi
      logger "Backup Script: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${DAY}/EXTDRIVE.tar.gz"
      echo -e "${CGreen}STATUS: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${DAY}/EXTDRIVE.tar.gz.${CClear}"
      sleep 1

      #added copies of the backup.sh and exlusions.txt list to backup location for easy copy/restore
      cp /jffs/scripts/backup.sh ${UNCDRIVE}${BKDIR}/backup.sh
      echo -e "${CGreen}STATUS: Finished copying backup.sh script to ${UNCDRIVE}${BKDIR}.${CClear}"
      if ! [ -z $EXCLUSION ]; then
        EXCLFILE=$(echo $EXCLUSION | sed 's:.*/::')
        cp $EXCLUSION ${UNCDRIVE}${BKDIR}/$EXCLFILE
        echo -e "${CGreen}STATUS: Finished copying $EXCLFILE script to ${UNCDRIVE}${BKDIR}.${CClear}"
      fi

      sleep 10
      umount $UNCDRIVE
      echo -e "${CGreen}STATUS: External Drive ($UNC) unmounted successfully.${CClear}"

  else

      echo -e "${CRed}ERROR: Failed to run Backup Script -- Drive mount failed.  Please check your configuration!${CClear}"
      logger "Backup Script ERROR: Failed to run Backup Script -- Drive mount failed.  Please check your configuration!"
      sleep 3

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# restore routine
restore() {

  echo -e "${CGreen}[Restore Backup Commencing]..."
  echo ""
  echo -e "${CGreen}Please ensure your have performed the following before restoring your backups:"
  echo -e "${CGreen}1.) Format a new SSD drive on router, calling it the exact same name as before!"
  echo -e "${CGreen}2.) Enable JFFS scripting in the router OS, and perform a reboot."
  echo -e "${CGreen}3.) Restore the backup.sh script (located under your backup folder) into your /jffs/scripts folder."
  echo -e "${CGreen}4.) Ensure that all of the settings/variables are correct before running a restore!"
  echo -e "${CGreen}5.) After the restore finishes, perform another reboot.  Everything should be restored as normal!"
  echo ""
  echo -e "${CCyan}Messages:"

  if ! [ -d $UNCDRIVE ]; then
      mkdir -p $UNCDRIVE
      chmod 777 $UNCDRIVE
      echo -e "${CYellow}ALERT: External Drive directory not set. Created under: $UNCDRIVE ${CClear}"
      sleep 3
  fi

  if ! mount | grep $UNCDRIVE > /dev/null 2>&1; then
      modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      mount -t cifs $UNC $UNCDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"
      echo -e "${CGreen}STATUS: External Drive ($UNC) mounted successfully under: $UNCDRIVE ${CClear}"
      sleep 5
  fi

  if [ -n "`mount | grep $UNCDRIVE`" ]; then

    echo -e "${CGreen}Available Backup Selections:${CClear}"
    ls -ld ${UNCDRIVE}${BKDIR}/*/

    echo ""
    echo -e "${CCyan}Would you like to continue to restore from backup?"
    if promptyn "(y/n): "; then

      echo ""
      echo -e "${CCyan}"
      read -p 'Enter the Day # of the backup you wish to restore? (ex: 27): ' BACKUPDATE1
      if [ -z "$BACKUPDATE1" ]; then BACKUPDATE=0; else BACKUPDATE=$BACKUPDATE1; fi
      if [ $BACKUPDATE -eq 0 ]; then echo ""; echo -e "${CRed}ERROR: Invalid Backup set chosen. Exiting script...${CClear}"; echo ""; exit 0; fi

      echo ""
      echo -e "${CRed}WARNING: You will be restoring a backup of your JFFS and the entire contents of your External"
      echo -e "USB drive back to their original locations.  You will be restoring from this backup location:"
      echo -e "${CBlue}${UNCDRIVE}${BKDIR}/$BACKUPDATE/"
      echo ""
      echo -e "${CCyan}Are you absolutely sure you like to continue to restore from backup?"
      if promptyn "(y/n): "; then
        echo ""
        echo ""
        echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz to /jffs.${CClear}"
        echo "tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz -C /jffs"
        echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/EXTDRIVE.tar.gz to $EXTDRIVE.${CClear}"
        echo "tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/EXTDRIVE.tar.gz -C $EXTDRIVE"
        echo ""
        sleep 10
        umount $UNCDRIVE
        echo -e "${CGreen}STATUS: External Drive ($UNC) unmounted successfully.${CClear}"
        echo -e "${CGreen}Backups were successfully restored to their original locations.  Please reboot now!${CClear}"
        read -rsp $'Press any key to continue...\n' -n1 key
        # Exit gracefully
        echo ""
        echo -e "${CClear}"
        exit 0
      else
        # Exit gracefully
        echo ""
        umount $UNCDRIVE
        echo -e "${CGreen}STATUS: External Drive ($UNC) unmounted successfully.${CClear}"
        echo -e "${CClear}"
        exit 0
      fi

    else
      # Exit gracefully
      echo ""
      umount $UNCDRIVE
      echo -e "${CGreen}STATUS: External Drive ($UNC) unmounted successfully.${CClear}"
      echo -e "${CClear}"
      exit 0
    fi

  fi

}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

clear
echo -e "${CGreen}BACKUPMON v0.1"
echo ""
echo -e "${CCyan}Normal Backup starting in 10 seconds. Press [X] to override and enter RESTORE mode"
echo ""

i=0
while [ $i -ne 10 ]
do
    preparebar 51 "|"
    progressbaroverride $i 10 "" "s" "Standard"
    i=$(($i+1))
done

echo -e "${CGreen}[Normal Backup Commencing]..."
echo ""
echo -e "${CCyan}Messages:"
backup
echo -e "${CClear}"

exit 0
