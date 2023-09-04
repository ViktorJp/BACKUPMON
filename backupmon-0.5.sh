#!/bin/sh
# Functional Backup Script by: @Jeffrey Young, August 9, 2023
# Heavily modified and restore functionality added by @Viktor Jaep, 2023

Version=0.5
Beta=1
CFGPATH="/jffs/addons/backupmon.d/backupmon.cfg"
DLVERPATH="/jffs/addons/backupmon.d/version.txt"
DAY="$(date +%d)"
EXTDRIVE="/tmp/mnt/$(nvram get usb_path_sda1_label)"
EXTLABEL="$(nvram get usb_path_sda1_label)"
BUILD="$(nvram get buildno | grep -o '^[^.]\+')"
UNCUPDATED="False"

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
# Functions
# -------------------------------------------------------------------------------------------------------------------------

# LogoNM is a function that displays the BACKUPMON script name in a cool ASCII font without menu options
logoNM () {
  echo -e "${CYellow}     ____  ___   ________ ____  ______  __  _______  _   __"
  echo -e "    / __ )/   | / ____/ //_/ / / / __ \/  |/  / __ \/ | / /"
  echo -e "   / __  / /| |/ /   / ,< / / / / /_/ / /|_/ / / / /  |/ /"
  echo -e "  / /_/ / ___ / /___/ /| / /_/ / ____/ /  / / /_/ / /|  /"
  echo -e " /_____/_/  |_\____/_/ |_\____/_/   /_/  /_/\____/_/ |_/  ${CGreen}v$Version${CYellow}${CClear}"
}

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

# -------------------------------------------------------------------------------------------------------------------------

# Preparebar and Progressbar is a script that provides a nice progressbar to show script activity
preparebar() {
  # $1 - bar length
  # $2 - bar char
  barlen=$1
  barspaces=$(printf "%*s" "$1")
  barchars=$(printf "%*s" "$1" | tr ' ' "$2")
}

progressbaroverride() {

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
            [Ss]) (vsetup); source $CFGPATH; echo ""; sleep 1; exit 0;;
            [Ee])  # Exit gracefully
                  clear
                  echo -e "${CClear}"
                  exit 0
                  ;;
        esac
    fi

}

# -------------------------------------------------------------------------------------------------------------------------
# updatecheck is a function that downloads the latest update version file, and compares it with what's currently installed
updatecheck () {

  # Download the latest version file from the source repository
  curl --silent --retry 3 "https://raw.githubusercontent.com/ViktorJp/backupmon/master/version.txt" -o "/jffs/addons/backupmon.d/version.txt"

  if [ -f $DLVERPATH ]
    then
      # Read in its contents for the current version file
      DLVersion=$(cat $DLVERPATH)

      # Compare the new version with the old version and log it
      if [ "$Beta" == "1" ]; then   # Check if Dev/Beta Mode is enabled and disable notification message
        UpdateNotify=0
      elif [ "$DLVersion" != "$Version" ]; then
        UpdateNotify="Update available: v$Version -> v$DLVersion"
        logger "BACKUPMON - A new update (v$DLVersion) is available to download"
      else
        UpdateNotify=0
      fi
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# vconfig is a function that guides you through the various configuration options for wxmon
vconfig () {

  if [ -f $CFGPATH ]; then #Making sure file exists before proceeding
    source $CFGPATH

    while true; do
      clear
      logoNM
      echo ""
      echo -e "${CGreen}----------------------------------------------------------------"
      echo -e "${CGreen}Configuration Utility Options"
      echo -e "${CGreen}----------------------------------------------------------------"
      echo -e "${InvDkGray}${CWhite} 1 ${CClear}${CCyan}: Backup Target Username      :"${CGreen}$USERNAME
      echo -e "${InvDkGray}${CWhite} 2 ${CClear}${CCyan}: Backup Target Password      :"${CGreen}$PASSWORD
      if [ "$UNCUPDATED" == "True" ]; then
        echo -en "${InvDkGray}${CWhite} 3 ${CClear}${CCyan}: Backup Target UNC Path      :"${CGreen};printf '%s' $UNC; printf "%s\n"
      else
        echo -en "${InvDkGray}${CWhite} 3 ${CClear}${CCyan}: Backup Target UNC Path      :"${CGreen}; echo $UNC | sed -e 's,\\,\\\\,g'
      fi
      echo -e "${InvDkGray}${CWhite} 4 ${CClear}${CCyan}: Local Drive Mount Path      :"${CGreen}$UNCDRIVE
      echo -e "${InvDkGray}${CWhite} 5 ${CClear}${CCyan}: Backup Target Dir Path      :"${CGreen}$BKDIR
      echo -e "${InvDkGray}${CWhite} 6 ${CClear}${CCyan}: Backup Exclusion File Name  :"${CGreen}$EXCLUSION
      echo -e "${InvDkGray}${CWhite} | ${CClear}"
      echo -e "${InvDkGray}${CWhite} s ${CClear}${CCyan}: Save & Exit"
      echo -e "${InvDkGray}${CWhite} e ${CClear}${CCyan}: Exit & Discard Changes"
      echo -e "${CGreen}----------------------------------------------------------------"
      echo ""
      printf "Selection: "
      read -r ConfigSelection

      # Execute chosen selections
          case "$ConfigSelection" in

            1) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}1. What is the Backup Target Username?"
              echo -e "${CYellow}(Default = Admin)${CClear}"
              read -p 'Username: ' USERNAME1
              USERNAME=$USERNAME1
            ;;

            2) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}2. What is the Backup Target Password?"
              echo -e "${CYellow}(Default = Admin)${CClear}"
              read -p 'Username: ' PASSWORD1
              PASSWORD=$PASSWORD1
            ;;

            3) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}3. What is the Backup Target UNC Path? This is the path of a local network"
              echo -e "${CCyan}backup device that has a share made available for backup to be pushed to."
              echo -e "${CCyan}Please note: Use proper notation for the network path by starting with"
              echo -en "${CCyan}4 backslashes "; printf "%s" "(\\\\\\\\)"; echo -en " and using 2 backslashes "; printf "%s" "(\\\\)"; echo -e " between any additional"
              echo -e "${CCyan}folders. Example below:"
              echo -en "${CYellow}"; printf "%s" "(Default = \\\\\\\\192.168.50.25\\\\Backups)"
              echo -e "${CClear}"
              read -rp 'Backup Target UNC Path: ' UNC1
              UNC=$UNC1
              UNCUPDATED="True"
            ;;

            4) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}4. What is the Local Drive Mount Path? This is the local path on your router"
              echo -e "${CCyan}typically located under /tmp/mnt which creates a physical directory that is"
              echo -e "${CCyan}mounted to the network backup location. Please note: Use proper notation for"
              echo -e "${CCyan}the path by using single forward slashes between directories. Example below:"
              echo -e "${CYellow}(Default = /tmp/mnt/backups)${CClear}"
              read -p 'Local Drive Mount Path: ' UNCDRIVE1
              UNCDRIVE=$UNCDRIVE1
            ;;

            5) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}5. What is the Backup Target Directory Path? This is the path that is created"
              echo -e "${CCyan}on your network backup location in order to store and order the backups by day."
              echo -e "${CCyan}Please note: Use proper notation for the path by using single forward slashes"
              echo -e "${CCyan}between directories. Example below:"
              echo -e "${CYellow}(Default = /router/GT-AX6000-Backup)${CClear}"
              read -p 'Local Drive Mount Path: ' BKDIR1
              BKDIR=$BKDIR1
            ;;

            6) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}6. What is the Backup Exclusion File Name? This file contains a list of certain"
              echo -e "${CCyan}files that you want to exclude from the backup, such as your swap file.  Please"
              echo -e "${CCyan}note: Use proper notation for the path by using single forward slashes between"
              echo -e "${CCyan}directories. Example below:"
              echo -e "${CYellow}(Default = /jffs/addons/backupmon.d/backupmonexcl.txt)${CClear}"
              read -p 'Local Drive Mount Path: ' EXCLUSION1
              EXCLUSION=$EXCLUSION1
            ;;

            [Ss]) # -----------------------------------------------------------------------------------------
              echo ""
              if [ $UNCUPDATED == "False" ]; then
                UNC=$(echo $UNC | sed -e 's,\\,\\\\,g')
              fi
                { echo 'BKCONFIG="'"Custom"'"'
                  echo 'USERNAME="'"$USERNAME"'"'
                  echo 'PASSWORD="'"$PASSWORD"'"'
                  echo 'UNC="'"$UNC"'"'
                  echo 'UNCDRIVE="'"$UNCDRIVE"'"'
                  echo 'BKDIR="'"$BKDIR"'"'
                  echo 'EXCLUSION="'"$EXCLUSION"'"'
                } > $CFGPATH
              echo ""
              echo -e "${CGreen}Applying config changes to BACKUPMON..."
              logger "BACKUPMON - Successfully wrote a new config file"
              sleep 3
              UNCUPDATED="False"
              return
            ;;

            [Ee]) # -----------------------------------------------------------------------------------------
              UNCUPDATED="False"
              return
            ;;

          esac
    done

  else
      #Create a new config file with default values to get it to a basic running state
      { echo 'BKCONFIG="Default"'
        echo 'USERNAME="admin"'
        echo 'PASSWORD="admin"'
        echo 'UNC="\\\\192.168.50.25\\Backups"'
        echo 'UNCDRIVE="/tmp/mnt/backups"'
        echo 'BKDIR="/router/GT-AX6000-Backup"'
        echo 'EXCLUSION=""'
      } > $CFGPATH

      #Re-run wxmon -config to restart setup process
      vconfig

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# vuninstall is a function that uninstalls and removes all traces of wxmon from your router...
vuninstall () {
  clear
  logoNM
  echo ""
  echo -e "${CYellow}Uninstall Utility${CClear}"
  echo ""
  echo -e "${CCyan}You are about to uninstall BACKUPMON!  This action is irreversible."
  echo -e "${CCyan}Do you wish to proceed?${CClear}"
  if promptyn "(y/n): "; then
    echo ""
    echo -e "\n${CCyan}Are you sure? Please type 'Y' to validate you want to proceed.${CClear}"
      if promptyn "(y/n): "; then
        clear
        rm -f -r /jffs/addons/backupmon.d
        rm -f /jffs/scripts/backupmon.sh
        echo ""
        echo -e "\n${CGreen}BACKUPMON has been uninstalled...${CClear}"
        echo ""
        exit 0
      else
        echo ""
        echo -e "\n${CGreen}Exiting Uninstall Utility...${CClear}"
        sleep 1
        return
      fi
  else
    echo ""
    echo -e "\n${CGreen}Exiting Uninstall Utility...${CClear}"
    sleep 1
    return
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# vupdate is a function that provides a UI to check for script updates and allows you to install the latest version...
vupdate () {
  updatecheck # Check for the latest version from source repository
  clear
  logoNM
  echo ""
  echo -e "${CYellow}Update Utility${CClear}"
  echo ""
  echo -e "${CCyan}Current Version: ${CYellow}$Version${CClear}"
  echo -e "${CCyan}Updated Version: ${CYellow}$DLVersion${CClear}"
  echo ""
  if [ "$Version" == "$DLVersion" ]
    then
      echo -e "${CCyan}You are on the latest version! Would you like to download anyways?${CClear}"
      echo -e "${CCyan}This will overwrite your local copy with the current build.${CClear}"
      if promptyn "(y/n): "; then
        echo ""
        echo -e "${CCyan}Downloading BACKUPMON ${CYellow}v$DLVersion${CClear}"
        curl --silent --retry 3 "https://raw.githubusercontent.com/ViktorJp/backupmon/master/backupmon-$DLVersion.sh" -o "/jffs/scripts/backupmon.sh" && chmod 755 "/jffs/scripts/backupmon.sh"
        echo ""
        echo -e "${CCyan}Download successful!${CClear}"
        logger "BACKUPMON - Successfully downloaded BACKUPMON v$DLVersion"
        echo ""
        echo -e "${CYellow}Please exit, restart and configure new options using: 'backupmon.sh -config'.${CClear}"
        echo -e "${CYellow}NOTE: New features may have been added that require your input to take${CClear}"
        echo -e "${CYellow}advantage of its full functionality.${CClear}"
        echo ""
        read -rsp $'Press any key to continue...\n' -n1 key
        return
      else
        echo ""
        echo ""
        echo -e "${CGreen}Exiting Update Utility...${CClear}"
        sleep 1
        return
      fi
    else
      echo -e "${CCyan}Score! There is a new version out there! Would you like to update?${CClear}"
      if promptyn " (y/n): "; then
        echo ""
        echo -e "${CCyan}Downloading BACKUPMON ${CYellow}v$DLVersion${CClear}"
        curl --silent --retry 3 "https://raw.githubusercontent.com/ViktorJp/backupmon/master/backupmon-$DLVersion.sh" -o "/jffs/scripts/backupmon.sh" && chmod 755 "/jffs/scripts/wxmon.sh"
        echo ""
        echo -e "${CCyan}Download successful!${CClear}"
        logger "BACKUPMON - Successfully downloaded BACKUPMON v$DLVersion"
        echo ""
        echo -e "${CYellow}Please exit, restart and configure new options using: 'wxmon.sh -config'.${CClear}"
        echo -e "${CYellow}NOTE: New features may have been added that require your input to take${CClear}"
        echo -e "${CYellow}advantage of its full functionality.${CClear}"
        echo ""
        read -rsp $'Press any key to continue...\n' -n1 key
        return
      else
        echo ""
        echo ""
        echo -e "${CGreen}Exiting Update Utility...${CClear}"
        sleep 1
        return
      fi
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# vsetup is a function that sets up, confiures and allows you to launch wxmon on your router...
vsetup () {

  # Check for and add an alias for wxmon
  if ! grep -F "sh /jffs/scripts/backupmon.sh" /jffs/configs/profile.add >/dev/null 2>/dev/null; then
		echo "alias backupmon=\"sh /jffs/scripts/backupmon.sh\" # backupmon" >> /jffs/configs/profile.add
  fi

  while true; do
    clear
    logoNM
    echo ""
    echo -e "${CYellow}Setup Utility${CClear}" # Provide main setup menu
    echo ""
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${CGreen}Operations"
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${InvDkGray}${CWhite} sc ${CClear}${CCyan}: Setup and Configure BACKUPMON"
    echo -e "${InvDkGray}${CWhite} up ${CClear}${CCyan}: Check for latest updates"
    echo -e "${InvDkGray}${CWhite} un ${CClear}${CCyan}: Uninstall"
    echo -e "${InvDkGray}${CWhite}  e ${CClear}${CCyan}: Exit"
    echo -e "${CGreen}----------------------------------------------------------------"
    echo ""
    printf "Selection: "
    read -r InstallSelection

    # Execute chosen selections
        case "$InstallSelection" in

          sc) # run backupmon -config
            clear
            vconfig
          ;;

          up)
            echo ""
            vupdate
          ;;

          un)
            echo ""
            vuninstall
          ;;

          [Ee])
            echo -e "${CClear}"
            exit 0
          ;;

          *)
            echo ""
            echo -e "${CRed}Invalid choice - Please enter a valid option...${CClear}"
            echo ""
            sleep 2
          ;;

        esac
  done
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

      if [ $BUILD -eq 388 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi
      mount -t cifs $UNC $UNCDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"
      sleep 5
  fi

  if [ -n "`mount | grep $UNCDRIVE`" ]; then

      echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") mounted successfully under: $UNCDRIVE ${CClear}"; printf "%s\n"

      if ! [ -d "${UNCDRIVE}${BKDIR}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}"; echo -e "${CGreen}STATUS: Backup Directory successfully created."; fi
      if ! [ -d "${UNCDRIVE}${BKDIR}/${DAY}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}/${DAY}"; echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}";fi

      [ -f ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar*
      [ -f ${UNCDRIVE}${BKDIR}/${DAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${DAY}/${EXTLABEL}.tar*

      if ! [ -z $EXCLUSION ]; then
        tar -zcf ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
      else
        tar -zcf ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar.gz -C /jffs . >/dev/null
      fi
      logger "Backup Script: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar.gz"
      echo -e "${CGreen}STATUS: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${DAY}/jffs.tar.gz.${CClear}"
      sleep 1

      if ! [ -z $EXCLUSION ]; then
        tar -zcf ${UNCDRIVE}${BKDIR}/${DAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
      else
        tar -zcf ${UNCDRIVE}${BKDIR}/${DAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
      fi
      logger "Backup Script: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${DAY}/${EXTLABEL}.tar.gz"
      echo -e "${CGreen}STATUS: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${DAY}/${EXTLABEL}.tar.gz.${CClear}"
      sleep 1

      #added copies of the backup.sh, backup.cfg and exclusions list to backup location for easy copy/restore
      cp /jffs/scripts/backupmon.sh ${UNCDRIVE}${BKDIR}/backupmon.sh
      echo -e "${CGreen}STATUS: Finished copying backupmon.sh script to ${UNCDRIVE}${BKDIR}.${CClear}"
      cp $CFGPATH ${UNCDRIVE}${BKDIR}/backupmon.cfg
      echo -e "${CGreen}STATUS: Finished copying backupmon.cfg script to ${UNCDRIVE}${BKDIR}.${CClear}"

      if ! [ -z $EXCLUSION ]; then
        EXCLFILE=$(echo $EXCLUSION | sed 's:.*/::')
        cp $EXCLUSION ${UNCDRIVE}${BKDIR}/$EXCLFILE
        echo -e "${CGreen}STATUS: Finished copying $EXCLFILE script to ${UNCDRIVE}${BKDIR}.${CClear}"
      fi

      #include restore instructions in the backup location
      { echo 'RESTORE INSTRUCTIONS'
        echo ''
        echo 'IMPORTANT: Your original USB Drive name was:' ${EXTLABEL}
        echo ''
        echo 'Please ensure your have performed the following before restoring your backups:'
        echo '1.) Format a new USB drive on your router using AMTM, calling it the exact same name as before (see above)!'
        echo '2.) Enable JFFS scripting in the router OS, and perform a reboot.'
        echo '3.) Restore the backupmon.sh script (located under your backup folder) into your /jffs/scripts folder.'
        echo '4.) Restore the backupmon.cfg file (located under your backup folder) into the /jffs/addons/backupmon.d folder.'
        echo '5.) Run "backupmon.sh -setup" and ensure that all of the settings/variables are correct before running a restore!'
        echo '6.) After the restore finishes, perform another reboot.  Everything should be restored as normal!'
      } > ${UNCDRIVE}${BKDIR}/instructions.txt
      echo -e "${CGreen}STATUS: Finished copying restore instructions.txt to ${UNCDRIVE}${BKDIR}.${CClear}"

      sleep 10
      umount $UNCDRIVE
      echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") unmounted successfully.${CClear}"; printf "%s\n"

  else

      echo -e "${CRed}ERROR: Failed to run Backup Script -- Drive mount failed.  Please check your configuration!${CClear}"
      logger "Backup Script ERROR: Failed to run Backup Script -- Drive mount failed.  Please check your configuration!"
      sleep 3

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# restore routine
restore() {

  clear
  echo -e "${CGreen}BACKUPMON v$Version"
  echo ""
  echo -e "${CCyan}Normal Backup starting in 10 seconds. Press ${CGreen}[S]${CCyan}etup or ${CRed}[X]${CCyan} to override and enter ${CRed}RESTORE${CCyan} mode"
  echo ""
  echo -e "${CGreen}[Restore Backup Commencing]..."
  echo ""
  echo -e "${CGreen}Please ensure your have performed the following before restoring your backups:"
  echo -e "${CGreen}1.) Format a new USB drive on your router using AMTM, calling it the exact same name as before!"
  echo -e "${CGreen}    (please refer to your restore instruction.txt file to find your original USB drive label)"
  echo -e "${CGreen}2.) Enable JFFS scripting in the router OS, and perform a reboot."
  echo -e "${CGreen}3.) Restore the backupmon.sh script (located under your backup folder) into your /jffs/scripts folder."
  echo -e "${CGreen}4.) Restore the backupmon.cfg file (located under your backup folder) into the /jffs/addons/backupmon.d folder."
  echo -e "${CGreen}5.) Run 'backupmon.sh -setup' and ensure that all of the settings/variables are correct before running a restore!"
  echo -e "${CGreen}6.) After the restore finishes, perform another reboot.  Everything should be restored as normal!"
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
    echo -e "${CGreen}Would you like to continue to restore from backup?"
    if promptyn "(y/n): "; then

      echo ""
      echo -e "${CGreen}"
        ok=0
        while [ $ok = 0 ]
        do
          echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 02 or 27): "
          read BACKUPDATE1
          if [ ${#BACKUPDATE1} -gt 2 ] || [ ${#BACKUPDATE1} -lt 2 ]
          then
            echo -e "${CRed}ERROR: Invalid entry. Please use 2 characters for the day format"; echo ""
          else
            ok=1
          fi
        done
      #read -n 2 BACKUPDATE1
      if [ -z "$BACKUPDATE1" ]; then BACKUPDATE=0; else BACKUPDATE=$BACKUPDATE1; fi
      if [ $BACKUPDATE -eq 0 ]; then echo ""; echo -e "${CRed}ERROR: Invalid Backup set chosen. Exiting script...${CClear}"; echo ""; exit 0; fi

      echo ""
      echo -e "${CRed}WARNING: You will be restoring a backup of your JFFS and the entire contents of your External"
      echo -e "USB drive back to their original locations.  You will be restoring from this backup location:"
      echo -e "${CBlue}${UNCDRIVE}${BKDIR}/$BACKUPDATE/"
      echo ""
      echo -e "${CGreen}Are you absolutely sure you like to continue to restore from backup?"
      if promptyn "(y/n): "; then
        echo ""
        echo ""
        echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz to /jffs.${CClear}"
        echo "tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz -C /jffs"
        echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz to $EXTDRIVE.${CClear}"
        echo "tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz -C $EXTDRIVE"
        echo ""
        sleep 10
        umount $UNCDRIVE
        echo -e "${CGreen}STATUS: External Drive ($UNC) unmounted successfully.${CClear}"
        echo -e "${CGreen}STATUS: Backups were successfully restored to their original locations.  Please reboot now!${CClear}"
        read -rsp $'Press any key to continue...\n' -n1 key
        # Exit gracefully
        echo ""
        echo -e "${CClear}"
        exit 0
      else
        # Exit gracefully
        echo ""
        echo ""
        umount $UNCDRIVE
        echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") unmounted successfully.${CClear}"; printf "%s\n"
        echo -e "${CClear}"
        exit 0
      fi

    else
      # Exit gracefully
      echo ""
      echo ""
      umount $UNCDRIVE
      echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") unmounted successfully.${CClear}"; printf "%s\n"
      echo -e "${CClear}"
      exit 0
    fi

  fi

}

# -------------------------------------------------------------------------------------------------------------------------
# Begin Main Program
# -------------------------------------------------------------------------------------------------------------------------

#DEBUG=; set -x # uncomment/comment to enable/disable debug mode
#{              # uncomment/comment to enable/disable debug mode

# Create the necessary folder/file structure for BACKUPMON under /jffs/addons
if [ ! -d "/jffs/addons/backupmon.d" ]; then
  mkdir -p "/jffs/addons/backupmon.d"
fi

# Check and see if any commandline option is being used
if [ $# -eq 0 ]
  then
    clear
    sh /jffs/scripts/backupmon.sh -backup
    exit 0
fi

# Check and see if an invalid commandline option is being used
if [ "$1" == "-h" ] || [ "$1" == "-help" ] || [ "$1" == "-setup" ] || [ "$1" == "-backup" ] || [ "$1" == "-restore" ]
  then
    clear
  else
    clear
    echo ""
    echo " BACKUPMON v$Version"
    echo ""
    echo " Exiting due to invalid commandline options!"
    echo " (run 'backupmon -h' for help)"
    echo ""
    echo -e "${CClear}"
    exit 0
fi

# Check to see if the help option is being called
if [ "$1" == "-h" ] || [ "$1" == "-help" ]
  then
  clear
  echo ""
  echo " BACKUPMON v$Version Commandline Option Usage:"
  echo ""
  echo " backupmon -h | -help"
  echo " backupmon -setup"
  echo " backupmon -backup"
  echo " backupmon -restore"
  echo ""
  echo "  -h | -help (this output)"
  echo "  -setup (displays the setup menu)"
  echo "  -backup (starts the normal backup procedures)"
  echo "  -restore (initiates the restore procedures)"
  echo ""
  echo -e "${CClear}"
  exit 0
fi

# Check to see if the populate option is being called
if [ "$1" == "-restore" ]
  then

    # Grab the config and read it in
    if [ -f $CFGPATH ]; then
      source $CFGPATH
    else
      clear
      echo -e "${CRed} ERROR: BACKUPMON is not configured.  Please run 'backupmon.sh -setup' first."
      echo -e "${CClear}"
      exit 0
    fi

    restore
    echo -e "${CClear}"
    exit 0

fi

# Check to see if the setup option is being called
if [ "$1" == "-setup" ]
  then
    vsetup
fi

# Check to see if the monitor option is being called
if [ "$1" == "-backup" ]
  then
    # Check for and add an alias for RTRMON
    if ! grep -F "sh /jffs/scripts/backupmon.sh" /jffs/configs/profile.add >/dev/null 2>/dev/null; then
  		echo "alias backupmon=\"sh /jffs/scripts/backupmon.sh\" # backupmon" >> /jffs/configs/profile.add
    fi
fi

clear
echo -e "${CGreen}BACKUPMON v$Version"
echo ""
echo -e "${CCyan}Normal Backup starting in 10 seconds. Press ${CGreen}[S]${CCyan}etup or ${CRed}[X]${CCyan} to override and enter ${CRed}RESTORE${CCyan} mode"
echo ""

if [ -f $CFGPATH ]; then #Making sure file exists before proceeding
  source $CFGPATH
else
  clear
  echo -e "${CRed} ERROR: BACKUPMON is not configured.  Please run 'backupmon.sh -setup' first."
  echo -e "${CClear}"
  exit 0
fi

echo -en "${CCyan}Backing up to ${CGreen}"; printf "%s" "${UNC}"; echo -e "${CCyan} mounted to ${CGreen}${UNCDRIVE}"
echo -e "${CCyan}Backup directory location: ${CGreen}${BKDIR}"
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
