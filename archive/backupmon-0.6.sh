#!/bin/sh

# Original functional backup script by: @Jeffrey Young, August 9, 2023
# BACKUPMON v0.6 heavily modified and restore functionality added by @Viktor Jaep, 2023
#
# BACKUPMON is a shell script that provides backup and restore capabilities for your Asus-Merlin firmware router's JFFS and
# external USB drive environments. By creating a network share off a NAS, server, or other device, BACKUPMON can point to
# this location, and perform a daily backup to this mounted drive. To perform daily, unattended backups, simply add a
# statement to your cron schedule, and launch backupmon.sh at any time you wish. During a situation of need to restore a
# backup after a catastrophic event with either your router or attached USB storage, simply copy the backupmon.sh & .cfg
# files over to a newly formatted /jffs/scripts folder, ensuring that your external USB storage was formatted with the same
# exact name (which is retrievable from the instructions.txt in your backup folder), and perform the restore by running the
# "backupmon.sh -restore" command, selecting the backup you want to use, and going through the prompts to complete the
# restoration of both your /jffs and external USB drive environments.
#
# Please use the 'backupmon.sh -setup' command to configure the necessary parameters that match your environment the best!

# Variable list -- please do not change any of these
Version=0.6                                                     # Current version
Beta=0                                                          # Beta release Y/N
CFGPATH="/jffs/addons/backupmon.d/backupmon.cfg"                # Path to the backupmon config file
DLVERPATH="/jffs/addons/backupmon.d/version.txt"                # Path to the backupmon version file
WDAY="$(date +%a)"                                              # Current day # of the week
MDAY="$(date +%d)"                                              # Current day # of the month
YDAY="$(date +%j)"                                              # Current day # of the year
EXTDRIVE="/tmp/mnt/$(nvram get usb_path_sda1_label)"            # Grabbing the External USB Drive path
EXTLABEL="$(nvram get usb_path_sda1_label)"                     # Grabbing the External USB Label name
UNCUPDATED="False"                                              # Tracking if the UNC was updated or not
UpdateNotify=0                                                  # Tracking whether a new update is available
SCHEDULE=0                                                      # Tracking whether automatic backups are scheduled
SCHEDULEHRS=2                                                   # Automatic backup hours (in 24hr format)
SCHEDULEMIN=30                                                  # Automatic backup minutes
FREQUENCY="M"                                                   # Frequency of backups -- weekly, monthly or yearly

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

# Promptyn is a simple function that accepts y/n input
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

# Preparebar and Progressbaroverride is a script that provides a nice progressbar to show script activity
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

# vconfig is a function that guides you through the various configuration options for backupmon
vconfig () {

  if [ -f /jffs/scripts/backupmon.cfg ]; then
    source /jffs/scripts/backupmon.cfg
    cp /jffs/scripts/backupmon.cfg /jffs/addons/backupmon.d/backupmon.cfg
  fi

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
      echo -en "${InvDkGray}${CWhite} 7 ${CClear}${CCyan}: Schedule Backups?           :"${CGreen}
      if [ "$SCHEDULE" == "0" ]; then
        printf "No"; printf "%s\n";
      else printf "Yes"; printf "%s\n"; fi
      if [ "$SCHEDULE" == "1" ]; then
        echo -e "${InvDkGray}${CWhite} |-${CClear}${CCyan}-  Time:                      :${CGreen}$SCHEDULEHRS:$SCHEDULEMIN"
      else
        echo -e "${InvDkGray}${CWhite} | ${CClear}${CDkGray}-  Time:                      :${CDkGray}$SCHEDULEHRS:$SCHEDULEMIN"
      fi
      echo -en "${InvDkGray}${CWhite} 8 ${CClear}${CCyan}: Backup Frequency?           :"${CGreen}
      if [ "$FREQUENCY" == "W" ]; then
        printf "Weekly"; printf "%s\n";
      elif [ "$FREQUENCY" == "M" ]; then
        printf "Monthly"; printf "%s\n";
      elif [ "$FREQUENCY" == "Y" ]; then
        printf "Yearly"; printf "%s\n"; fi
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
              if [ "$USERNAME1" == "" ] || [ -z "$USERNAME1" ]; then USERNAME="Admin"; else USERNAME="$USERNAME1"; fi # Using default value on enter keypress
            ;;

            2) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}2. What is the Backup Target Password?"
              echo -e "${CYellow}(Default = Admin)${CClear}"
              read -p 'Username: ' PASSWORD1
              if [ "$PASSWORD1" == "" ] || [ -z "$PASSWORD1" ]; then PASSWORD="Admin"; else PASSWORD="$PASSWORD1"; fi # Using default value on enter keypress
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
              if [ "$UNC1" == "" ] || [ -z "$UNC1" ]; then UNC="\\\\\\\\192.168.50.25\\\\Backups"; else UNC="$UNC1"; fi # Using default value on enter keypress
              #UNC=$UNC1
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
              if [ "$UNCDRIVE1" == "" ] || [ -z "$UNCDRIVE1" ]; then UNCDRIVE="/tmp/mnt/backups"; else UNCDRIVE="$UNCDRIVE1"; fi # Using default value on enter keypress
            ;;

            5) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}5. What is the Backup Target Directory Path? This is the path that is created"
              echo -e "${CCyan}on your network backup location in order to store and order the backups by day."
              echo -e "${CCyan}Please note: Use proper notation for the path by using single forward slashes"
              echo -e "${CCyan}between directories. Example below:"
              echo -e "${CYellow}(Default = /router/GT-AX6000-Backup)${CClear}"
              read -p 'Local Drive Mount Path: ' BKDIR1
              if [ "$BKDIR1" == "" ] || [ -z "$BKDIR1" ]; then BKDIR="/router/GT-AX6000-Backup"; else BKDIR="$BKDIR1"; fi # Using default value on enter keypress
            ;;

            6) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}6. What is the Backup Exclusion File Name? This file contains a list of certain"
              echo -e "${CCyan}files that you want to exclude from the backup, such as your swap file.  Please"
              echo -e "${CCyan}note: Use proper notation for the path by using single forward slashes between"
              echo -e "${CCyan}directories. Example below:"
              echo -e "${CYellow}(Default = /jffs/addons/backupmon.d/backupmonexcl.txt)${CClear}"
              read -p 'Local Drive Mount Path: ' EXCLUSION1
              if [ "$EXCLUSION1" == "" ] || [ -z "$EXCLUSION1" ]; then EXCLUSION=""; else EXCLUSION="$EXCLUSION1"; fi # Using default value on enter keypress
            ;;

            7) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}7. Would you like BACKUPMON to automatically run at a scheduled time each day?"
              echo -e "${CCyan}Please note: This will place a cru command into your 'services-start' file that"
              echo -e "${CCyan}is located under your /jffs/scripts folder. Each time your router reboots, this"
              echo -e "${CCyan}command will automatically be added as a CRON job to run your backup."
              echo -e "${CYellow}(No=0, Yes=1) (Default = 0)${CClear}"
              read -p 'Schedule BACKUPMON?: ' SCHEDULE1
              if [ "$SCHEDULE1" == "" ] || [ -z "$SCHEDULE1" ]; then SCHEDULE=0; else SCHEDULE="$SCHEDULE1"; fi # Using default value on enter keypress

              if [ "$SCHEDULE" == "0" ]; then

                if [ -f /jffs/scripts/services-start ]; then
                  sed -i -e '/backupmon.sh/d' /jffs/scripts/services-start
                  cru d RunBackupMon
                fi

              elif [ "$SCHEDULE" == "1" ]; then

                echo ""
                echo -e "${CCyan}7a. What time would you like BACKUPMON to automatically run each day? Please"
                echo -e "${CCyan}note: You will be asked for the hours and minutes in separate prompts. Use 24hr"
                echo -e "${CCyan}format for the hours. (Ex: 17 hrs / 15 min = 17:15 or 5:15pm)"
                echo -e "${CYellow}(Default = 2 hrs / 30 min = 02:30 or 2:30am)${CClear}"
                read -p 'Schedule HOURS?: ' SCHEDULEHRS1
                if [ "$SCHEDULEHRS1" == "" ] || [ -z "$SCHEDULEHRS1" ]; then SCHEDULEHRS=2; else SCHEDULEHRS="$SCHEDULEHRS1"; fi # Using default value on enter keypress
                read -p 'Schedule MINUTES?: ' SCHEDULEMIN1
                if [ "$SCHEDULEMIN1" == "" ] || [ -z "$SCHEDULEMIN1" ]; then SCHEDULEMIN=30; else SCHEDULEMIN="$SCHEDULEMIN1"; fi # Using default value on enter keypress

                if [ -f /jffs/scripts/services-start ]; then

                  if ! grep -q -F "sh /jffs/scripts/backupmon.sh" /jffs/scripts/services-start; then
                    echo 'cru a RunBackupMon "'"$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh"'"' >> /jffs/scripts/services-start
                    cru a RunBackupMon "$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh"
                  fi

                else
                  echo 'cru a RunBackupMon "'"$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh"'"' >> /jffs/scripts/services-start
                  chmod 755 /jffs/scripts/services-start
                  cru a RunBackupMon "$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh"
                fi

              else
                SCHEDULE=0
                SCHEDULEHRS=2
                SCHEDULEMIN=30
              fi
            ;;

            8) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}8. What frequency would you like BACKUPMON to run backup jobs each day? You have"
              echo -e "${CCyan}3 different choices -- Weekly, Monthly and Yearly. For Weekly backups, 7 different"
              echo -e "${CCyan}folders for each day of the week are created. Monthly, 31 different folders, and"
              echo -e "${CCyan}yearly, 365 different folders are created. As each week/month/year rolls over,"
              echo -e "${CCyan}those backups will be overwritten."
              echo -e "${CYellow}(Weekly=W, Monthly=M, Yearly=Y) (Default = M)${CClear}"
              while true; do
                read -p 'Frequency (W/M/Y)?: ' FREQUENCY
                  case $FREQUENCY in
                    [Ww] ) FREQUENCY="W"; break ;;
                    [Mm] ) FREQUENCY="M"; break ;;
                    [Yy] ) FREQUENCY="Y"; break ;;
                    "" ) echo -e "\n Error: Please use either M, W, or Y\n";;
                    * ) echo -e "\n Error: Please use either M, W, or Y\n";;
                  esac
              done
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
                  echo 'SCHEDULE='$SCHEDULE
                  echo 'SCHEDULEHRS='$SCHEDULEHRS
                  echo 'SCHEDULEMIN='$SCHEDULEMIN
                  echo 'FREQUENCY="'"$FREQUENCY"'"'
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
        echo 'SCHEDULE=0'
        echo 'SCHEDULEHRS=2'
        echo 'SCHEDULEMIN=30'
        echo 'FREQUENCY="M"'
      } > $CFGPATH

      #Re-run backupmon -config to restart setup process
      vconfig

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# vuninstall is a function that uninstalls and removes all traces of backupmon from your router...
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
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# vsetup is a function that sets up, confiures and allows you to launch backupmon on your router...
vsetup () {

  # Check for and add an alias for backupmon
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

  # Check to see if a local drive mount is available, if not, create one.
  if ! [ -d $UNCDRIVE ]; then
      mkdir -p $UNCDRIVE
      chmod 777 $UNCDRIVE
      echo -e "${CYellow}ALERT: External Drive directory not set. Newly created under: $UNCDRIVE ${CClear}"
      sleep 3
  fi

  # If everything successfully was created, proceed
  if ! mount | grep $UNCDRIVE > /dev/null 2>&1; then

      # Check the build to see if modprobe needs to be called
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      # Connect the UNC to the local drive mount
      mount -t cifs $UNC $UNCDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"
      sleep 5
  fi

  # If the local mount is connected to the UNC, proceed
  if [ -n "`mount | grep $UNCDRIVE`" ]; then

      echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") mounted successfully under: $UNCDRIVE ${CClear}"; printf "%s\n"

      # Create the backup directories and daily directories if they do not exist yet
      if ! [ -d "${UNCDRIVE}${BKDIR}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}"; echo -e "${CGreen}STATUS: Backup Directory successfully created."; fi

      # Create frequency folders by week, month or year
      if [ $FREQUENCY == "W" ]; then
        if ! [ -d "${UNCDRIVE}${BKDIR}/${WDAY}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}/${WDAY}"; echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}";fi
      elif [ $FREQUENCY == "M" ]; then
        if ! [ -d "${UNCDRIVE}${BKDIR}/${MDAY}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}/${MDAY}"; echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}";fi
      elif [ $FREQUENCY == "Y" ]; then
        if ! [ -d "${UNCDRIVE}${BKDIR}/${YDAY}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}/${YDAY}"; echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}";fi
      fi

      # Remove old tar files if they exist in the daily folders
      if [ $FREQUENCY == "W" ]; then
        [ -f ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar*
        [ -f ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar*
      elif [ $FREQUENCY == "M" ]; then
        [ -f ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar*
        [ -f ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar*
      elif [ $FREQUENCY == "Y" ]; then
        [ -f ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar*
        [ -f ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar*
      fi

      # If a TAR exclusion file exists, use it for the /jffs backup
      if [ $FREQUENCY == "W" ]; then
        if ! [ -z $EXCLUSION ]; then
          tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
        else
          tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz -C /jffs . >/dev/null
        fi
        logger "Backup Script: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz"
        echo -e "${CGreen}STATUS: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz.${CClear}"
        sleep 1
      elif [ $FREQUENCY == "M" ]; then
        if ! [ -z $EXCLUSION ]; then
          tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
        else
          tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz -C /jffs . >/dev/null
        fi
        logger "Backup Script: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz"
        echo -e "${CGreen}STATUS: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz.${CClear}"
        sleep 1
      elif [ $FREQUENCY == "Y" ]; then
        if ! [ -z $EXCLUSION ]; then
          tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
        else
          tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz -C /jffs . >/dev/null
        fi
        logger "Backup Script: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz"
        echo -e "${CGreen}STATUS: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz.${CClear}"
        sleep 1
      fi

      # If a TAR exclusion file exists, use it for the USB drive backup
      if [ $FREQUENCY == "W" ]; then
        if ! [ -z $EXCLUSION ]; then
          tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
        else
          tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
        fi
        logger "Backup Script: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz"
        echo -e "${CGreen}STATUS: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz.${CClear}"
        sleep 1
      elif [ $FREQUENCY == "M" ]; then
        if ! [ -z $EXCLUSION ]; then
          tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
        else
          tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
        fi
        logger "Backup Script: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz"
        echo -e "${CGreen}STATUS: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz.${CClear}"
        sleep 1
      elif [ $FREQUENCY == "Y" ]; then
        if ! [ -z $EXCLUSION ]; then
          tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
        else
          tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
        fi
        logger "Backup Script: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz"
        echo -e "${CGreen}STATUS: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz.${CClear}"
        sleep 1
      fi

      #added copies of the backupmon.sh, backupmon.cfg and exclusions list to backup location for easy copy/restore
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
        echo '3.) Restore the backupmon.sh & .cfg files (located under your backup folder) into your /jffs/scripts folder.'
        echo '4.) Run "backupmon.sh -setup" and ensure that all of the settings are correct before running a restore.'
        echo '5.) Run "backupmon.sh -restore", pick which backup you want to restore, and confirm before proceeding!'
        echo '6.) After the restore finishes, perform another reboot.  Everything should be restored as normal!'
      } > ${UNCDRIVE}${BKDIR}/instructions.txt
      echo -e "${CGreen}STATUS: Finished copying restore instructions.txt to ${UNCDRIVE}${BKDIR}.${CClear}"

      sleep 10
      # Unmount the locally connected mounted drive
      umount -l $UNCDRIVE
      echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") unmounted successfully.${CClear}"; printf "%s\n"

  else

      # There's problems with mounting the drive - check paths and permissions!
      echo -e "${CRed}ERROR: Failed to run Backup Script -- Drive mount failed.  Please check your configuration!${CClear}"
      logger "Backup Script ERROR: Failed to run Backup Script -- Drive mount failed.  Please check your configuration!"
      sleep 3

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# restore function is a routine that allows you to pick a backup to be restored
restore() {

  clear
  # Notify if a new version awaits
  if [ "$UpdateNotify" == "0" ]; then
    echo -e "${CGreen}BACKUPMON v$Version"
  else
    echo -e "${CGreen}BACKUPMON v$Version ${CRed}-- $UpdateNotify"
  fi

  # Display instructions
  echo ""
  echo -e "${CCyan}Normal Backup starting in 10 seconds. Press ${CGreen}[S]${CCyan}etup or ${CRed}[X]${CCyan} to override and enter ${CRed}RESTORE${CCyan} mode"
  echo ""
  echo -e "${CGreen}[Restore Backup Commencing]..."
  echo ""
  echo -e "${CGreen}Please ensure your have performed the following before restoring your backups:"
  echo -e "${CGreen}1.) Format a new USB drive on your router using AMTM, calling it the exact same name as before!"
  echo -e "${CGreen}    (please refer to your restore instruction.txt file to find your original USB drive label)"
  echo -e "${CGreen}2.) Enable JFFS scripting in the router OS, and perform a reboot."
  echo -e "${CGreen}3.) Restore the backupmon.sh & .cfg files (located under your backup folder) into your /jffs/scripts folder."
  echo -e "${CGreen}4.) Run 'backupmon.sh -setup' and ensure that all of the settings are correct before running a restore!"
  echo -e "${CGreen}5.) Run 'backupmon.sh -restore', pick which backup you want to restore, and confirm before proceeding!"
  echo -e "${CGreen}6.) After the restore finishes, perform another reboot.  Everything should be restored as normal!"
  echo ""
  echo -e "${CCyan}Messages:"

  # Create the local drive mount directory
  if ! [ -d $UNCDRIVE ]; then
      mkdir -p $UNCDRIVE
      chmod 777 $UNCDRIVE
      echo -e "${CYellow}ALERT: External Drive directory not set. Created under: $UNCDRIVE ${CClear}"
      sleep 3
  fi

  # If the mount does not exist yet, proceed
  if ! mount | grep $UNCDRIVE > /dev/null 2>&1; then

    # Check if the build supports modprobe
    if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
      modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
    fi

    # Mount the local drive directory to the UNC
    mount -t cifs $UNC $UNCDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"
    echo -e "${CGreen}STATUS: External Drive ($UNC) mounted successfully under: $UNCDRIVE ${CClear}"
    sleep 5

  fi

  # If the UNC is successfully mounted, proceed
  if [ -n "`mount | grep $UNCDRIVE`" ]; then

    # Show a list of valid backups on screen
    echo -e "${CGreen}Available Backup Selections:${CClear}"
    ls -ld ${UNCDRIVE}${BKDIR}/*/
    echo
    ls -ld ${UNCDRIVE}${BKDIR}/*/*/

    echo ""
    echo -e "${CGreen}Would you like to continue to restore from backup?"
    if promptyn "(y/n): "; then

      echo ""
      echo -e "${CGreen}"
        ok=0
        while [ $ok = 0 ]
        do
          if [ $FREQUENCY == "W" ]; then
            echo -e "${CGreen}Enter the Day of the backup you wish to restore? (ex: Mon or Fri): "
            read BACKUPDATE1
            if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
            then
              echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
            else
              ok=1
            fi
          elif [ $FREQUENCY == "M" ]; then
            echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 02 or 27): "
            read BACKUPDATE1
            if [ ${#BACKUPDATE1} -gt 2 ] || [ ${#BACKUPDATE1} -lt 2 ]
            then
              echo -e "${CRed}ERROR: Invalid entry. Please use 2 characters for the day format"; echo ""
            else
              ok=1
            fi
          elif [ $FREQUENCY == "Y" ]; then
            echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 002 or 270): "
            read BACKUPDATE1
            if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
            then
              echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
            else
              ok=1
            fi
          fi
        done

      if [ -z "$BACKUPDATE1" ]; then echo ""; echo -e "${CRed}ERROR: Invalid Backup set chosen. Exiting script...${CClear}"; echo ""; exit 0; else BACKUPDATE=$BACKUPDATE1; fi

      echo ""
      echo -e "${CRed}WARNING: You will be restoring a backup of your JFFS and the entire contents of your External"
      echo -e "USB drive back to their original locations.  You will be restoring from this backup location:"
      echo -e "${CBlue}${UNCDRIVE}${BKDIR}/$BACKUPDATE/"
      echo ""
      echo -e "${CGreen}Are you absolutely sure you like to continue to restore from backup?"
      if promptyn "(y/n): "; then
        echo ""
        echo ""
        # Run the TAR commands to restore backups to their original locations
        echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz to /jffs.${CClear}"
        tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz -C /jffs >/dev/null
        echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz to $EXTDRIVE.${CClear}"
        tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz -C $EXTDRIVE >/dev/null
        echo ""
        sleep 10
        # Unmount the backup drive
        umount -l $UNCDRIVE
        echo -e "${CGreen}STATUS: External Drive ($UNC) unmounted successfully.${CClear}"
        echo -e "${CGreen}STATUS: Backups were successfully restored to their original locations.  Please reboot now!${CClear}"
        # read -rsp $'Press any key to continue...\n' -n1 key
        # Exit gracefully
        echo ""
        echo -e "${CClear}"
        exit 0
      else
        # Exit gracefully
        echo ""
        echo ""
        sleep 10
        umount -l $UNCDRIVE
        echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") unmounted successfully.${CClear}"; printf "%s\n"
        echo -e "${CClear}"
        exit 0
      fi

    else
      # Exit gracefully
      echo ""
      echo ""
      sleep 10
      umount -l $UNCDRIVE
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

updatecheck

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
  echo "  -backup (runs the normal backup procedures)"
  echo "  -restore (initiates the restore procedures)"
  echo ""
  echo -e "${CClear}"
  exit 0
fi

# Check to see if the restore option is being called
if [ "$1" == "-restore" ]
  then

    # Grab the config and read it in
    if [ -f $CFGPATH ]; then
      source $CFGPATH
    elif [ -f /jffs/scripts/backupmon.cfg ]; then
      source /jffs/scripts/backupmon.cfg
      cp /jffs/scripts/backupmon.cfg /jffs/addons/backupmon.d/backupmon.cfg
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

# Check to see if the backup option is being called
if [ "$1" == "-backup" ]
  then
    # Check for and add an alias for BACKUPMON
    if ! grep -F "sh /jffs/scripts/backupmon.sh" /jffs/configs/profile.add >/dev/null 2>/dev/null; then
  		echo "alias backupmon=\"sh /jffs/scripts/backupmon.sh\" # backupmon" >> /jffs/configs/profile.add
    fi
fi

clear
# Check for updates
if [ "$UpdateNotify" == "0" ]; then
  echo -e "${CGreen}BACKUPMON v$Version"
else
  echo -e "${CGreen}BACKUPMON v$Version ${CRed}-- $UpdateNotify"
fi

echo ""
echo -e "${CCyan}Normal Backup starting in 10 seconds. Press ${CGreen}[S]${CCyan}etup or ${CRed}[X]${CCyan} to override and enter ${CRed}RESTORE${CCyan} mode"
echo ""

# Determine if the config is local or under /jffs/addons/backupmon.d
if [ -f $CFGPATH ]; then #Making sure file exists before proceeding
  source $CFGPATH
elif [ -f /jffs/scripts/backupmon.cfg ]; then
  source /jffs/scripts/backupmon.cfg
  cp /jffs/scripts/backupmon.cfg /jffs/addons/backupmon.d/backupmon.cfg
else
  clear
  echo -e "${CRed} ERROR: BACKUPMON is not configured.  Please run 'backupmon.sh -setup' first."
  echo -e "${CClear}"
  exit 0
fi

if [ $FREQUENCY == "W" ]; then FREQEXPANDED="Weekly"; fi
if [ $FREQUENCY == "M" ]; then FREQEXPANDED="Monthly"; fi
if [ $FREQUENCY == "Y" ]; then FREQEXPANDED="Yearly"; fi
echo -en "${CCyan}Backing up to ${CGreen}"; printf "%s" "${UNC}"; echo -e "${CCyan} mounted to ${CGreen}${UNCDRIVE}"
echo -e "${CCyan}Backup directory location: ${CGreen}${BKDIR} ${CCyan}-- Frequency: ${CGreen}$FREQEXPANDED"
echo ""

# Run a 10sec timer
i=0
while [ $i -ne 10 ]
do
    preparebar 51 "|"
    progressbaroverride $i 10 "" "s" "Standard"
    i=$(($i+1))
done

# Run a normal backup
echo -e "${CGreen}[Normal Backup Commencing]..."
echo ""
echo -e "${CCyan}Messages:"

backup

echo -e "${CClear}"
exit 0

#} #2>&1 | tee $LOG | logger -t $(basename $0)[$$]  # uncomment/comment to enable/disable debug mode
