#!/bin/sh

# Original functional backup script by: @Jeffrey Young, August 9, 2023
# BACKUPMON v1.22b1 heavily modified and restore functionality added by @Viktor Jaep, 2023
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
Version=1.22b1                                                  # Current version
Beta=1                                                          # Beta release Y/N
CFGPATH="/jffs/addons/backupmon.d/backupmon.cfg"                # Path to the backupmon config file
DLVERPATH="/jffs/addons/backupmon.d/version.txt"                # Path to the backupmon version file
WDAY="$(date +%a)"                                              # Current day # of the week
MDAY="$(date +%d)"                                              # Current day # of the month
YDAY="$(date +%j)"                                              # Current day # of the year
EXTDRIVE="/tmp/mnt/$(nvram get usb_path_sda1_label)"            # Grabbing the External USB Drive path
EXTLABEL="$(nvram get usb_path_sda1_label)"                     # Grabbing the External USB Label name
UNCUPDATED="False"                                              # Tracking if the UNC was updated or not
SECONDARYUNCUPDATED="False"                                     # Tracking if the Secondary UNC was updated or not
UpdateNotify=0                                                  # Tracking whether a new update is available
BSWITCH="False"                                                 # Tracking -backup switch to eliminate timer

# Config variables
USERNAME="admin"
PASSWORD="admin"
UNC="\\\\192.168.50.25\\Backups"
UNCDRIVE="/tmp/mnt/backups"
BKDIR="/router/GT-AX6000-Backup"
EXCLUSION=""
SCHEDULE=0
SCHEDULEHRS=2
SCHEDULEMIN=30
FREQUENCY="M"
MODE="Basic"
PURGE=0
PURGELIMIT=0
SECONDARYSTATUS=0
SECONDARYUSER="admin"
SECONDARYPWD="admin"
SECONDARYUNC="\\\\192.168.50.25\\SecondaryBackups"
SECONDARYUNCDRIVE="/tmp/mnt/secondarybackups"
SECONDARYBKDIR="/router/GT-AX6000-2ndBackup"
SECONDARYEXCLUSION=""
SECONDARYFREQUENCY="M"
SECONDARYMODE="Basic"
SECONDARYPURGE=0
SECONDARYPURGELIMIT=0

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
  echo -e " /_____/_/  |_\____/_/ |_\____/_/   /_/  /_/\____/_/ |_/ ${CGreen}v$Version${CYellow}${CClear}"
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
        logger "BACKUPMON INFO: A new update (v$DLVersion) is available to download"
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

    if [ -z $SECONDARYPURGE ]; then SECONDARYPURGE=0; fi

    # Determine router model
    if [ -z "$ROUTERMODEL" ]; then
      [ -z "$(nvram get odmpid)" ] && ROUTERMODEL="$(nvram get productid)" || ROUTERMODEL="$(nvram get odmpid)" # Thanks @thelonelycoder for this logic
    fi

    CHANGES=0 #track notification to save your changes

    while true; do
      clear
      logoNM
      echo ""
      echo -e "${CGreen}----------------------------------------------------------------"
      echo -e "${CGreen}Primary Backup Configuration Options"
      echo -e "${CGreen}----------------------------------------------------------------"
      echo -e "${InvDkGray}${CWhite}    ${CClear}${CCyan}: Source Router Model             :"${CGreen}$ROUTERMODEL
      echo -e "${InvDkGray}${CWhite} 1  ${CClear}${CCyan}: Backup Target Username          :"${CGreen}$USERNAME
      echo -e "${InvDkGray}${CWhite} 2  ${CClear}${CCyan}: Backup Target Password          :"${CGreen}$PASSWORD
      if [ "$UNCUPDATED" == "True" ]; then
        echo -en "${InvDkGray}${CWhite} 3  ${CClear}${CCyan}: Backup Target UNC Path          :"${CGreen};printf '%s' $UNC; printf "%s\n"
      else
        echo -en "${InvDkGray}${CWhite} 3  ${CClear}${CCyan}: Backup Target UNC Path          :"${CGreen}; echo $UNC | sed -e 's,\\,\\\\,g'
      fi
      echo -e "${InvDkGray}${CWhite} 4  ${CClear}${CCyan}: Local Drive Mount Path          :"${CGreen}$UNCDRIVE
      echo -e "${InvDkGray}${CWhite} 5  ${CClear}${CCyan}: Backup Target Directory Path    :"${CGreen}$BKDIR
      echo -e "${InvDkGray}${CWhite} 6  ${CClear}${CCyan}: Backup Exclusion File Name      :"${CGreen}$EXCLUSION
      echo -en "${InvDkGray}${CWhite} 7  ${CClear}${CCyan}: Schedule Backups?               :"${CGreen}
      if [ "$SCHEDULE" == "0" ]; then
        printf "No"; printf "%s\n";
      else printf "Yes"; printf "%s\n"; fi
      if [ "$SCHEDULE" == "1" ]; then
        echo -e "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Time:                          :${CGreen}$SCHEDULEHRS:$SCHEDULEMIN"
      else
        echo -e "${InvDkGray}${CWhite} |  ${CClear}${CDkGray}-  Time:                          :${CDkGray}$SCHEDULEHRS:$SCHEDULEMIN"
      fi
      echo -en "${InvDkGray}${CWhite} 8  ${CClear}${CCyan}: Backup Frequency?               :"${CGreen}
      if [ "$FREQUENCY" == "W" ]; then
        printf "Weekly"; printf "%s\n";
      elif [ "$FREQUENCY" == "M" ]; then
        printf "Monthly"; printf "%s\n";
      elif [ "$FREQUENCY" == "Y" ]; then
        printf "Yearly"; printf "%s\n";
      elif [ "$FREQUENCY" == "P" ]; then
        printf "Perpetual"; printf "%s\n"; fi
      if [ "$FREQUENCY" == "P" ]; then
        echo -en "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Purge Backups?                 :${CGreen}"
        if [ "$PURGE" == "0" ]; then
          printf "No"; printf "%s\n";
        elif [ "$PURGE" == "1" ]; then
          printf "Yes"; printf "%s\n";fi
        echo -en "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Purge older than (days):       :${CGreen}"
        if [ "$PURGELIMIT" == "0" ]; then
          printf "N/A"; printf "%s\n";
        else
          printf $PURGELIMIT; printf "%s\n";
        fi
      else
        echo -e "${InvDkGray}${CWhite} |--${CClear}${CDkGray}-  Purge Backups?                 :${CDkGray}No"
        echo -e "${InvDkGray}${CWhite} |  ${CClear}${CDkGray}-  Purge older than (days):       :${CDkGray}N/A"
      fi
      echo -e "${InvDkGray}${CWhite} 9  ${CClear}${CCyan}: Backup/Restore Mode             :"${CGreen}$MODE
      echo -en "${InvDkGray}${CWhite} 10 ${CClear}${CCyan}: Secondary Backup Config Options :"${CGreen}$SECONDARY
      if [ "$SECONDARYSTATUS" != "0" ] && [ "$SECONDARYSTATUS" != "1" ]; then SECONDARYSTATUS=0; fi
      if [ "$SECONDARYSTATUS" == "0" ]; then
        printf "Disabled"; printf "%s\n";
      else printf "Enabled"; printf "%s\n"; fi
      echo -e "${InvDkGray}${CWhite} |  ${CClear}"
      if [ $CHANGES -eq 0 ]; then
        echo -e "${InvDkGray}${CWhite} s  ${CClear}${CCyan}: Save Config & Exit"
      else
        echo -e "${InvDkGray}${CWhite} s  ${CClear}${CCyan}: Save Config & Exit               ${CWhite}${InvRed}<-- Save your changes! ${CClear}"
      fi
      echo -e "${InvDkGray}${CWhite} e  ${CClear}${CCyan}: Exit & Discard Changes"
      echo -e "${CGreen}----------------------------------------------------------------"
      echo ""
      CHANGES=1
      printf "Selection: "
      read -r ConfigSelection

      # Execute chosen selections
          case "$ConfigSelection" in

            1) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}1. What is the Primary Backup Target Username?"
              echo -e "${CYellow}(Default = Admin)${CClear}"
              read -p 'Username: ' USERNAME1
              if [ "$USERNAME1" == "" ] || [ -z "$USERNAME1" ]; then USERNAME="Admin"; else USERNAME="$USERNAME1"; fi # Using default value on enter keypress
            ;;

            2) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}2. What is the Primary Backup Target Password?"
              echo -e "${CYellow}(Default = Admin)${CClear}"
              read -p 'Password: ' PASSWORD1
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
              echo -e "${CYellow}(Default = /jffs/addons/backupmon.d/exclusions.txt)${CClear}"
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
                  else
                    #delete and re-add if it already exists in case there's a time change
                    sed -i -e '/backupmon.sh/d' /jffs/scripts/services-start
                    cru d RunBackupMon
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
              echo -e "${CCyan}8. What backup frequency would you like BACKUPMON to run daily backup jobs each"
              echo -e "${CCyan}day? There are 4 different choices -- Weekly, Monthly, Yearly and Perpetual."
              echo -e "${CCyan}Backup folders based on the week, month, year, or perpetual are created under"
              echo -e "${CCyan}your network share. Explained below:"
              echo ""
              echo -e "${CYellow}WEEKLY:"
              echo -e "${CGreen}7 different folders for each day of the week are created (ex: Mon, Tue... Sun)."
              echo ""
              echo -e "${CYellow}MONTHLY:"
              echo -e "${CGreen}31 different folders for each day are created (ex: 01, 02, 03... 30, 31)."
              echo ""
              echo -e "${CYellow}YEARLY:"
              echo -e "${CGreen}365 different folders are created for each day (ex: 001, 002, 003... 364, 365)."
              echo ""
              echo -e "${CYellow}PERPETUAL:"
              echo -e "${CGreen}A unique backup folder is created each time it runs based on the date-time"
              echo -e "${CGreen}(ex: 20230909-084322). NOTE: When using the Perpetual backup frequency option,"
              echo -e "${CGreen}you may only use BASIC mode."
              echo ""
              echo -e "${CYellow}(Weekly=W, Monthly=M, Yearly=Y, Perpetual=P) (Default = M)${CClear}"
              while true; do
                read -p 'Frequency (W/M/Y/P)?: ' FREQUENCY
                  case $FREQUENCY in
                    [Ww] ) FREQUENCY="W"; PURGE=0; PURGELIMIT=0; break ;;
                    [Mm] ) FREQUENCY="M"; PURGE=0; PURGELIMIT=0; break ;;
                    [Yy] ) FREQUENCY="Y"; PURGE=0; PURGELIMIT=0; break ;;
                    [Pp] ) FREQUENCY="P"; MODE="Basic" break ;;
                    "" ) echo -e "\n Error: Please use either M, W, Y or P\n";;
                    * ) echo -e "\n Error: Please use either M, W, Y or P\n";;
                  esac
              done

              if [ $FREQUENCY == "P" ]; then
                echo ""
                echo -e "${CCyan}8a. Would you like to purge perpetual backups after a certain age? This can help"
                echo -e "${CCyan}trim your backups and reclaim disk space, but also gives you more flexibility on"
                echo -e "${CCyan}the length of time you can keep your backups. Purging backups can be run manually"
                echo -e "${CCyan}from the setup menu, and gives you the ability to see which backups will be purged"
                echo -e "${CCyan}before they are deleted permanently. It will also run automatically when calling"
                echo -e "${CCyan}BACKUPMON with the -backup switch. If you run 'sh backupmon.sh -backup', it will"
                echo -e "${CCyan}complete a backup, and then run an auto purge based on your criteria. Running"
                echo -e "${CCyan}'sh backupmon.sh' without the -backup switch will run a normal backup without an"
                echo -e "${CCyan}auto purge, even if purge is enabled below."
                echo ""
                echo -e "${CCyan}PLEASE NOTE: If there are any backups you wish to save permanently, please move"
                echo -e "${CCyan}these to a SAFE, separate folder that BACKUPMON does not interact with."
                echo ""
                echo -e "${CYellow}(No=0, Yes=1) (Default = 0)${CClear}"
                read -p 'Purge Backups? (0/1): ' PURGE1
                if [ "$PURGE1" == "" ] || [ -z "$PURGE1" ]; then PURGE=0; else PURGE="$PURGE1"; fi # Using default value on enter keypress

                if [ "$PURGE" == "0" ]; then

                  PURGELIMIT=0

                elif [ "$PURGE" == "1" ]; then

                  echo ""
                  echo -e "${CCyan}8b. How many days would you like to keep your perpetual backups? Example: 90"
                  echo -e "${CCyan}Note that all perpetual backups older than 90 days would be permanently deleted."
                  echo ""
                  echo -e "${CCyan}PLEASE NOTE: If there are any backups you wish to save permanently, please move"
                  echo -e "${CCyan}these to a SAFE, separate folder that BACKUPMON does not interact with."
                  echo ""
                  echo -e "${CYellow}(Default = 90)${CClear}"
                  read -p 'Backup Age? (in days): ' PURGELIMIT1
                  if [ "$PURGELIMIT1" == "" ] || [ -z "$PURGELIMIT1" ]; then PURGELIMIT=0; else PURGELIMIT="$PURGELIMIT1"; fi # Using default value on enter keypress

                else
                  PURGE=0
                  PURGELIMIT=0
                fi
              fi

            ;;

            9) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}9. What mode of operation would you like BACKUPMON to run in? You have 2 different"
              echo -e "${CCyan}choices -- Basic or Advanced. Choose wisely! These are the differences:"
              echo ""
              echo -e "${CYellow}BASIC:"
              echo -e "${CGreen}- Only backs up one backup set per daily folder"
              echo -e "${CGreen}- Backup file names have standard names based on jffs and USB drive label names"
              echo -e "${CGreen}- Self-prunes the daily backup folders by deleting contents before backing up new set"
              echo -e "${CGreen}- Will overwrite daily backups, even if multiple are made on the same day"
              echo -e "${CGreen}- Restore more automated, and only required to pick which day to restore from"
              echo ""
              echo -e "${CYellow}ADVANCED:"
              echo -e "${CGreen}- Backs up multiple daily backup sets per daily folder"
              echo -e "${CGreen}- Backup file names contain extra unique date and time identifiers"
              echo -e "${CGreen}- Keeps all daily backups forever, and no longer self-prunes"
              echo -e "${CGreen}- Will not overwrite daily backups, even if multiple are made on the same day"
              echo -e "${CGreen}- Restore more tedious, and required to type exact backup file names before restore"
              echo ""
              echo -e "${CYellow}NOTE: When choosing BASIC mode while using 'Perpetual Frequency', your daily backup"
              echo -e "${CYellow}folders will not self-prune or overwrite, even if multiple backups are made on the"
              echo -e "${CYellow}same day."
              echo ""
              echo -e "${CYellow}(0=Basic, 1=Advanced) (Default = 0)${CClear}"
              while true; do
                read -p 'Mode (0/1)?: ' MODE1
                  case $MODE1 in
                    [0] ) MODE="Basic"; break ;;
                    [1] ) if [ $FREQUENCY == "P" ]; then MODE="Basic"; else MODE="Advanced"; fi; break ;;
                    "" ) echo -e "\n Error: Please use either 0 or 1\n";;
                    * ) echo -e "\n Error: Please use either 0 or 1\n";;
                  esac
              done
            ;;

            10) # -----------------------------------------------------------------------------------------
            while true; do
              clear
              echo ""
              echo -e "${CCyan}10. Would you like to utilize a secondary/redundant backup configuration?"
              echo -e "${CCyan}A secondary/redundant backup would allow you to backup your data to a"
              echo -e "${CCyan}second backup target location, for optimum safety and redundancy. Please"
              echo -e "${CCyan}use the prompts below to configure the necessary information to initiate"
              echo -e "${CCyan}and schedule secondary backups. Ensure that the format of the prompts"
              echo -e "${CCyan}are followed exactly based on their example default values:"
              echo ""
              echo -e "${CGreen}----------------------------------------------------------------"
              echo -e "${CGreen}Secondary Backup Configuration Options"
              echo -e "${CGreen}----------------------------------------------------------------"
              echo -en "${InvDkGray}${CWhite} 1  ${CClear}${CCyan}: Enabled/Disabled           : ${CGreen}"
              if [ "$SECONDARYSTATUS" != "0" ] && [ "$SECONDARYSTATUS" != "1" ]; then SECONDARYSTATUS=0; fi
              if [ "$SECONDARYSTATUS" == "0" ]; then
                printf "Disabled"; printf "%s\n";
              else printf "Enabled"; printf "%s\n"; fi
              if [ -z "$SECONDARYUSER" ]; then SECONDARYUSER="admin"; fi
              echo -e "${InvDkGray}${CWhite} 2  ${CClear}${CCyan}: Secondary Target Username  : ${CGreen}$SECONDARYUSER"
              if [ -z "$SECONDARYPWD" ]; then SECONDARYPWD="admin"; fi
              echo -e "${InvDkGray}${CWhite} 3  ${CClear}${CCyan}: Secondary Target Password  : ${CGreen}$SECONDARYPWD"
              if [ -z "$SECONDARYUNC" ]; then SECONDARYUNC="\\\\192.168.50.25\\Backups"; fi
              if [ "$SECONDARYUNCUPDATED" == "True" ]; then
                echo -en "${InvDkGray}${CWhite} 4  ${CClear}${CCyan}: Secondary Target UNC Path  : ${CGreen}"; printf '%s' $SECONDARYUNC; printf "%s\n"
              else
                echo -en "${InvDkGray}${CWhite} 4  ${CClear}${CCyan}: Secondary Target UNC Path  : ${CGreen}"; echo $SECONDARYUNC | sed -e 's,\\,\\\\,g'
              fi
              if [ -z "$SECONDARYUNCDRIVE" ]; then SECONDARYUNCDRIVE="/tmp/mnt/backups"; fi
              echo -e "${InvDkGray}${CWhite} 5  ${CClear}${CCyan}: Local Drive Mount Path     : ${CGreen}$SECONDARYUNCDRIVE"
              if [ -z "$SECONDARYBKDIR" ]; then SECONDARYBKDIR="/router/GT-AX6000-Backup"; fi
              echo -e "${InvDkGray}${CWhite} 6  ${CClear}${CCyan}: Secondary Target Dir Path  : ${CGreen}$SECONDARYBKDIR"
              echo -e "${InvDkGray}${CWhite} 7  ${CClear}${CCyan}: Exclusion File Name        : ${CGreen}$SECONDARYEXCLUSION"
              echo -en "${InvDkGray}${CWhite} 8  ${CClear}${CCyan}: Backup Frequency?          : ${CGreen}"
              if [ "$SECONDARYFREQUENCY" == "W" ]; then
                printf "Weekly"; printf "%s\n";
              elif [ "$SECONDARYFREQUENCY" == "M" ]; then
                printf "Monthly"; printf "%s\n";
              elif [ "$SECONDARYFREQUENCY" == "Y" ]; then
                printf "Yearly"; printf "%s\n";
              elif [ "$SECONDARYFREQUENCY" == "P" ]; then
                printf "Perpetual"; printf "%s\n";
              else SECONDARYFREQUENCY="M";
                printf "Monthly"; printf "%s\n"; fi
              if [ "$SECONDARYFREQUENCY" == "P" ]; then
                echo -en "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Purge Secondary Backups?  : ${CGreen}"
                if [ "$SECONDARYPURGE" == "0" ]; then
                  printf "No"; printf "%s\n";
                else printf "Yes"; printf "%s\n"; fi
              else
                echo -en "${InvDkGray}${CWhite} |--${CClear}${CDkGray}-  Purge Secondary Backups?  : ${CDkGray}"
                if [ "$SECONDARYPURGE" == "0" ]; then
                  printf "No"; printf "%s\n";
                else printf "Yes"; printf "%s\n"; fi
              fi
              if [ -z $SECONDARYPURGELIMIT ]; then SECONDARYPURGELIMIT=0; fi
              if [ "$SECONDARYFREQUENCY" == "P" ] && [ "$SECONDARYPURGE" == "1" ]; then
                echo -e "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Purge Older Than (days)   : ${CGreen}$SECONDARYPURGELIMIT"
              else
                echo -e "${InvDkGray}${CWhite} |--${CClear}${CDkGray}-  Purge Older Than (days)   : ${CDkGray}$SECONDARYPURGELIMIT"
              fi
              if [ -z "$SECONDARYMODE" ]; then SECONDARYMODE="Basic"; fi
              echo -e "${InvDkGray}${CWhite} 9  ${CClear}${CCyan}: Backup/Restore Mode        : ${CGreen}$SECONDARYMODE"
              echo -e "${InvDkGray}${CWhite} |  ${CClear}"
              echo -e "${InvDkGray}${CWhite} e  ${CClear}${CCyan}: Exit Back to Primary Backup Config"
              echo -e "${CGreen}----------------------------------------------------------------"
              echo ""
              printf "Selection: ${CClear}"
              read -r SECONDARYINPUT
                  case $SECONDARYINPUT in
                    1 ) echo ""; read -p 'Secondary Backup Enabled=1, Disabled=0 (0/1?): ' SECONDARYSTATUS;;
                    2 ) echo ""; read -p 'Secondary Username: ' SECONDARYUSER;;
                    3 ) echo ""; read -p 'Secondary Password: ' SECONDARYPWD;;
                    4 ) echo ""; read -rp 'Secondary Target UNC (ex: \\\\192.168.50.25\\Backups ): ' SECONDARYUNC1; SECONDARYUNC="$SECONDARYUNC1"; SECONDARYUNCUPDATED="True";;
                    5 ) echo ""; read -p 'Secondary Local Drv Mount Path (ex: /tmp/mnt/backups ): ' SECONDARYUNCDRIVE;;
                    6 ) echo ""; read -p 'Secondary Target Dir Path (ex: /router/GT-AX6000-Backup ): ' SECONDARYBKDIR;;
                    7 ) echo ""; read -p 'Secondary Exclusion File Name (ex: /jffs/addons/backupmon.d/exclusions.txt ): ' SECONDARYEXCLUSION;;
                    8 ) echo ""; read -p 'Secondary Backup Frequency (Weekly=W, Monthly=M, Yearly=Y, Perpetual=P) (W/M/Y/P?): ' SECONDARYFREQUENCY; SECONDARYFREQUENCY=$(echo "$SECONDARYFREQUENCY" | awk '{print toupper($0)}'); SECONDARYPURGE=0; if [ "$SECONDARYFREQUENCY" == "P" ]; then SECONDARYMODE="Basic"; read -p 'Purge Secondary Backups? (Yes=1/No=0) ' SECONDARYPURGE; read -p 'Secondary Backup Purge Age? (Days/Disabled=0) ' SECONDARYPURGELIMIT; else SECONDARYPURGELIMIT=0; fi;;
                    9 ) echo ""; read -p 'Secondary Backup Mode (Basic=0, Advanced=1) (0/1?): ' SECONDARYMODE; if [ "$SECONDARYMODE" == "0" ]; then SECONDARYMODE="Basic"; elif [ "$SECONDARYMODE" == "1" ]; then SECONDARYMODE="Advanced"; else SECONDARYMODE="Basic"; fi; if [ "$SECONDARYFREQUENCY" == "P" ]; then SECONDARYMODE="Basic"; fi;;
                    [Ee] ) break ;;
                    "" ) echo -e "\n Error: Please use 1 - 9 or Exit = e\n";;
                    * ) echo -e "\n Error: Please use 1 - 9 or Exit = e\n";;
                  esac
              done
            ;;

            [Ss]) # -----------------------------------------------------------------------------------------
              echo ""
              if [ "$UNCUPDATED" == "False" ]; then
                UNC=$(echo $UNC | sed -e 's,\\,\\\\,g')
              fi

              if [ "$SECONDARYUNCUPDATED" == "False" ]; then
                SECONDARYUNC=$(echo $SECONDARYUNC | sed -e 's,\\,\\\\,g')
              fi

                { echo 'ROUTERMODEL="'"$ROUTERMODEL"'"'
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
                  echo 'MODE="'"$MODE"'"'
                  echo 'PURGE='$PURGE
                  echo 'PURGELIMIT='$PURGELIMIT
                  echo 'SECONDARYSTATUS='$SECONDARYSTATUS
                  echo 'SECONDARYUSER="'"$SECONDARYUSER"'"'
                  echo 'SECONDARYPWD="'"$SECONDARYPWD"'"'
                  echo 'SECONDARYUNC="'"$SECONDARYUNC"'"'
                  echo 'SECONDARYUNCDRIVE="'"$SECONDARYUNCDRIVE"'"'
                  echo 'SECONDARYBKDIR="'"$SECONDARYBKDIR"'"'
                  echo 'SECONDARYEXCLUSION="'"$SECONDARYEXCLUSION"'"'
                  echo 'SECONDARYFREQUENCY="'"$SECONDARYFREQUENCY"'"'
                  echo 'SECONDARYMODE="'"$SECONDARYMODE"'"'
                  echo 'SECONDARYPURGE='$SECONDARYPURGE
                  echo 'SECONDARYPURGELIMIT='$SECONDARYPURGELIMIT
                } > $CFGPATH
              echo -e "${CGreen}Applying config changes to BACKUPMON..."
              logger "BACKUPMON INFO: Successfully wrote a new config file"
              sleep 3
              UNCUPDATED="False"
              SECONDARYUNCUPDATED="False"
              UNC=$(echo -e "$UNC")
              SECONDARYUNC=$(echo -e "$SECONDARYUNC")
              return
            ;;

            [Ee]) # -----------------------------------------------------------------------------------------
              UNCUPDATED="False"
              SECONDARYUNCUPDATED="False"
              return
            ;;

          esac
    done

  else

      # Determine router model
      [ -z "$(nvram get odmpid)" ] && ROUTERMODEL="$(nvram get productid)" || ROUTERMODEL="$(nvram get odmpid)" # Thanks @thelonelycoder for this logic

      #Create a new config file with default values to get it to a basic running state
      { echo 'ROUTERMODEL="'"$ROUTERMODEL"'"'
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
        echo 'MODE="Basic"'
        echo 'PURGE=0'
        echo 'PURGELIMIT=0'
        echo 'SECONDARYSTATUS=0'
        echo 'SECONDARYUSER="admin"'
        echo 'SECONDARYPWD="admin"'
        echo 'SECONDARYUNC="\\\\192.168.50.25\\SecondaryBackups"'
        echo 'SECONDARYUNCDRIVE="/tmp/mnt/secondarybackups"'
        echo 'SECONDARYBKDIR="/router/GT-AX6000-2ndBackup"'
        echo 'SECONDARYEXCLUSION=""'
        echo 'SECONDARYFREQUENCY="M"'
        echo 'SECONDARYMODE="Basic"'
        echo 'SECONDARYPURGE=0'
        echo 'SECONDARYPURGELIMIT=0'
      } > $CFGPATH

      #Re-run backupmon -config to restart setup process
      vconfig

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

testtarget() {

TESTUSER="admin"
TESTPWD="admin"
TESTUNC="\\\\192.168.50.25\\Backups"
TESTUNCDRIVE="/tmp/mnt/testbackups"
TESTBKDIR="/router/test-backup"
TESTUNCUPDATED="False"

while true; do
  clear
  logoNM
  echo ""
  echo -e "${CCyan}The Backup Target Network Connection Tester allows you to play with"
  echo -e "your connection variables, such as your username/password, network UNC"
  echo -e "path, target directories and local drive mount paths. If your network"
  echo -e "target is configured correctly, this utility will write a test folder"
  echo -e "out there, and copy a test file into the test folder in order to"
  echo -e "validate that read/write permissions are correct."
  echo ""
  echo -e "${CGreen}----------------------------------------------------------------"
  echo -e "${CGreen}Backup Target Network Connection Tester"
  echo -e "${CGreen}----------------------------------------------------------------"
  echo -e "${InvDkGray}${CWhite} 1  ${CClear}${CCyan}: Test Target Username         : ${CGreen}$TESTUSER"
  echo -e "${InvDkGray}${CWhite} 2  ${CClear}${CCyan}: Test Target Password         : ${CGreen}$TESTPWD"
  if [ "$TESTUNCUPDATED" == "True" ]; then
    echo -en "${InvDkGray}${CWhite} 3  ${CClear}${CCyan}: Test Target UNC Path         : ${CGreen}"; printf '%s' $TESTUNC; printf "%s\n"
  else
    echo -en "${InvDkGray}${CWhite} 3  ${CClear}${CCyan}: Test Target UNC Path         : ${CGreen}"; echo $TESTUNC | sed -e 's,\\,\\\\,g'
  fi
  echo -e "${InvDkGray}${CWhite} 4  ${CClear}${CCyan}: Test Local Drive Mount Path  : ${CGreen}$TESTUNCDRIVE"
  echo -e "${InvDkGray}${CWhite} 5  ${CClear}${CCyan}: Test Target Dir Path         : ${CGreen}$TESTBKDIR"
  echo -e "${InvDkGray}${CWhite} |  ${CClear}"
  echo -e "${InvDkGray}${CWhite} t  ${CClear}${CCyan}: Test your Network Backup Connection"
  echo -e "${InvDkGray}${CWhite} e  ${CClear}${CCyan}: Exit Back to Setup + Operations Menu"
  echo -e "${CGreen}----------------------------------------------------------------"
  echo ""
  printf "Selection: ${CClear}"
  read -r TESTINPUT
      case $TESTINPUT in
        1 ) echo ""; read -p 'Test Username: ' TESTUSER;;
        2 ) echo ""; read -p 'Test Password: ' TESTPWD;;
        3 ) echo ""; read -rp 'Test Target UNC (ex: \\\\192.168.50.25\\Backups ): ' TESTUNC1; TESTUNC="$TESTUNC1"; TESTUNCUPDATED="True";;
        4 ) echo ""; read -p 'Test Local Drv Mount Path (ex: /tmp/mnt/testbackups ): ' TESTUNCDRIVE;;
        5 ) echo ""; read -p 'Test Target Dir Path (ex: /router/test-backup ): ' TESTBKDIR;;
        [Ee] ) break ;;
        [Tt] )  # Connection test script
                if [ "$TESTUNCUPDATED" == "True" ]; then TESTUNC=$(echo -e "$TESTUNC"); fi
                echo ""
                echo -e "${CCyan}Messages:"
                # Check to see if a local drive mount is available, if not, create one.
                if ! [ -d $TESTUNCDRIVE ]; then
                    mkdir -p $TESTUNCDRIVE
                    chmod 777 $TESTUNCDRIVE
                    echo -e "${CYellow}ALERT: External Drive directory not set. Created test directory under: $TESTUNCDRIVE ${CClear}"
                    sleep 3
                else
                  echo -e "${CGreen}INFO: External Drive directory exists. Test directory found under: ${CYellow}$TESTUNCDRIVE ${CClear}"
                fi

                # If everything successfully was created, proceed
                if ! mount | grep $TESTUNCDRIVE > /dev/null 2>&1; then

                    # Check the build to see if modprobe needs to be called
                    if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
                      modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
                    fi

                    CNT=0
                    TRIES=2
                      while [ $CNT -lt $TRIES ]; do # Loop through number of tries
                        mount -t cifs $TESTUNC $TESTUNCDRIVE -o "vers=2.1,username=${TESTUSER},password=${TESTPWD}"  # Connect the UNC to the local drive mount
                        MRC=$?
                        if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
                          break
                        else
                          echo -e "${CYellow}WARNING: Unable to mount to external drive. Retrying...${CClear}"
                          sleep 5
                          CNT=$((CNT+1))
                          if [ $CNT -eq $TRIES ];then
                            echo -e "${CRed}ERROR: Unable to mount to external drive ($TESTUNCDRIVE). Please check your configuration. Exiting.${CClear}"
                            break
                          fi
                        fi
                      done
                fi

                # If the local mount is connected to the UNC, proceed
                if [ -n "`mount | grep $TESTUNCDRIVE`" ]; then

                    echo -en "${CGreen}STATUS: External Test Drive ("; printf "%s" "${TESTUNC}"; echo -en ") mounted successfully under: ${CYellow}$TESTUNCDRIVE ${CClear}"; printf "%s\n"

                    # Create the backup directories and daily directories if they do not exist yet
                    if ! [ -d "${TESTUNCDRIVE}${TESTBKDIR}" ]; then mkdir -p "${TESTUNCDRIVE}${TESTBKDIR}"; echo -e "${CGreen}STATUS: Test Backup Directory successfully created under: ${CYellow}$TESTBKDIR${CClear}"; fi
                    if ! [ -d "${TESTUNCDRIVE}${TESTBKDIR}/test" ]; then mkdir -p "${TESTUNCDRIVE}${TESTBKDIR}/test"; echo -e "${CGreen}STATUS: Daily Test Backup Subdirectory successfully created under: ${CYellow}$TESTBKDIR/test${CClear}";fi

                    #include restore instructions in the backup location
                    { echo 'TEST FILE'
                      echo ''
                      echo 'This is a test file created to ensure you have proper read/write access to your backup directory.'
                      echo ''
                      echo 'Please delete this file and associated test directories at your convenience'
                    } > ${TESTUNCDRIVE}${TESTBKDIR}/Test/testfile.txt
                    echo -e "${CGreen}STATUS: Finished copying ${CYellow}testfile.txt${CGreen} to ${CYellow}${TESTUNCDRIVE}${TESTBKDIR}/test${CClear}"
                    echo -e "${CGreen}STATUS: Settling for 10 seconds..."
                    sleep 10

                    # Unmount the locally connected mounted drive
                    unmounttestdrv
                    read -rsp $'Press any key to acknowledge...\n' -n1 key

                else

                    # There's problems with mounting the drive - check paths and permissions!
                    echo -e "${CRed}ERROR: Failed to run Network Connect Test Script -- Drive mount failed. Please check your configuration!${CClear}"
                    read -rsp $'Press any key to acknowledge...\n' -n1 key

                fi
                TESTUNCUPDATED="False"

        ;;
        "" ) echo -e "\n Error: Please use 1 - 9 or Exit = e\n";;
        * ) echo -e "\n Error: Please use 1 - 9 or Exit = e\n";;

      esac
  done
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
        sed -i -e '/backupmon.sh/d' /jffs/scripts/services-start
        cru d RunBackupMon
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
        echo -e "\n${CCyan}Downloading BACKUPMON ${CYellow}v$DLVersion${CClear}"
        curl --silent --retry 3 "https://raw.githubusercontent.com/ViktorJp/backupmon/master/backupmon-$DLVersion.sh" -o "/jffs/scripts/backupmon.sh" && chmod 755 "/jffs/scripts/backupmon.sh"
        echo ""
        echo -e "${CCyan}Download successful!${CClear}"
        logger "BACKUPMON INFO: Successfully downloaded BACKUPMON v$DLVersion"
        echo ""
        echo -e "${CYellow}Please exit, restart and configure new options using: 'backupmon.sh -setup'.${CClear}"
        echo -e "${CYellow}NOTE: New features may have been added that require your input to take${CClear}"
        echo -e "${CYellow}advantage of its full functionality. Please save your configuration!${CClear}"
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
        echo -e "\n${CCyan}Downloading BACKUPMON ${CYellow}v$DLVersion${CClear}"
        curl --silent --retry 3 "https://raw.githubusercontent.com/ViktorJp/backupmon/master/backupmon-$DLVersion.sh" -o "/jffs/scripts/backupmon.sh" && chmod 755 "/jffs/scripts/backupmon.sh"
        echo ""
        echo -e "${CCyan}Download successful!${CClear}"
        logger "BACKUPMON INFO: Successfully downloaded BACKUPMON v$DLVersion"
        echo ""
        echo -e "${CYellow}Please exit, restart and configure new options using: 'backupmon.sh -setup'.${CClear}"
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
# This amazing function was borrowed from none other than @Martinski... a genius approach to filtering and deleting files/folders
# $1 = path, $2 = age, $3 = show/delete
_DeleteFileDirAfterNumberOfDays_ ()
{
   local retCode=1  minNumOfDays=1
   if [ $# -eq 0 ] || [ -z "$1" ] || [ -z "$2" ] || \
      { [ ! -f "$1" ] && [ ! -d "$1" ] ; }
   then
      printf "\nFile or Directory [$1] is *NOT* FOUND.\n"
      return 1
   fi
   if ! echo "$2" | grep -qE "^[1-9][0-9]*$" || [ "$2" -lt "$minNumOfDays" ]
   then
      printf "\nNumber of days [$2] is *NOT* VALID.\n"
      return 1
   fi
   if [ "$(($(date +%s) - $(date +%s -r "$1")))" -gt "$(($2 * 86400))" ]
   then
       count=$((count+1))
       if [ "$3" == "show" ]; then
         printf "$1\n"
       elif [ "$3" == "delete" ]; then
         if [ -f "$1" ]
         then rmOpts="-f"
         else rmOpts="-fr"
         fi
         printf "${CRed}Deleting $1..."
         rm $rmOpts "$1" ; retCode="$?"
         printf "${CGreen}OK\n"
       fi
   fi
   return "$retCode"
}

# -------------------------------------------------------------------------------------------------------------------------

# purgebackups is a function that allows you to see which backups will be purged before deleting them...
purgebackups () {

  if [ "$PURGE" -eq 0 ]; then
    return
  fi

  clear
  logoNM
  echo ""
  echo -e "${CYellow}Purge Perpetual Backups Utility${CClear}"
  echo ""
  echo -e "${CCyan}You are about to purge backups! FUN! This action is irreversible and permanent."
  echo -e "${CCyan}But no worries! BACKUPMON will first show you which backups are affected by the"
  echo -e "${CYellow}$PURGELIMIT days${CCyan} limit you have configured."
  echo ""
  echo -e "${CCyan}Do you wish to proceed?${CClear}"
  if promptyn "(y/n): "; then

    echo ""
    echo -e "\n${CCyan}Messages:"

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
      CNT=0
      TRIES=12
        while [ $CNT -lt $TRIES ]; do # Loop through number of tries
          mount -t cifs $UNC $UNCDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"  # Connect the UNC to the local drive mount
          MRC=$?
          if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
            echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") mounted successfully under: $UNCDRIVE ${CClear}"; printf "%s\n"
            break
          else
            echo -e "${CYellow}WARNING: Unable to mount to external drive. Trying every 10 seconds for 2 minutes."
            sleep 10
            CNT=$((CNT+1))
            if [ $CNT -eq $TRIES ];then
              echo -e "${CRed}ERROR: Unable to mount to external drive. Please check your configuration. Exiting."
              logger "BACKUPMON ERROR: Unable to mount to external drive. Please check your configuration!"
              exit 0
            fi
          fi
        done
      sleep 2
    fi

    # If the UNC is successfully mounted, proceed
    if [ -n "`mount | grep $UNCDRIVE`" ]; then

      # Show a list of valid backups on screen
      count=0
      echo -e "${CGreen}STATUS: Perpetual backup folders identified below are older than $PURGELIMIT days:${CRed}"
      for FOLDER in $(ls ${UNCDRIVE}${BKDIR} -1)
      do
        _DeleteFileDirAfterNumberOfDays_ "${UNCDRIVE}${BKDIR}/$FOLDER" $PURGELIMIT show
      done

      # If there are no valid backups within range, display a message and exit
      if [ $count -eq 0 ]; then
        echo -e "${CYellow}INFO: No perpetual backup folders were identified older than $PURGELIMIT days.${CClear}"
        logger "BACKUPMON INFO: No perpetual backup folders identified older than $PURGELIMIT days were found. Nothing to delete."
        read -rsp $'Press any key to acknowledge...\n' -n1 key
        echo ""
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountdrv

        echo -e "\n${CGreen}Exiting Purge Perpetual Backups Utility...${CClear}"
        sleep 2
        return
      fi

      # Continue with deleting backups permanently
      echo ""
      echo -e "${CGreen}Would you like to permanently purge these backups?${CClear}"

      if promptyn "(y/n): "; then
        echo -e "\n${CRed}"
        for FOLDER in $(ls ${UNCDRIVE}${BKDIR} -1)
        do
          _DeleteFileDirAfterNumberOfDays_ "${UNCDRIVE}${BKDIR}/$FOLDER" $PURGELIMIT delete
        done

        echo ""
        echo -e "${CGreen}STATUS: Perpetual backup folders older than $PURGELIMIT days deleted.${CClear}"
        logger "BACKUPMON INFO: Perpetual backup folders older than $PURGELIMIT days were deleted."
        read -rsp $'Press any key to acknowledge...\n' -n1 key
        echo ""
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountdrv

        echo -e "\n${CGreen}Exiting Purge Perpetual Backups Utility...${CClear}\n"
        sleep 2
        return

      else

        echo ""
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountdrv

        echo -e "\n${CGreen}Exiting Purge Perpetual Backups Utility...${CClear}\n"
        sleep 2
        return
      fi
    fi

  else
    echo ""
    echo -e "\n${CGreen}Exiting Purge Perpetual Backups Utility...${CClear}"
    sleep 2
    return
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# autopurge is a function that allows you to purge backups throught a commandline switch... if you're daring!
autopurge () {
  clear

  if [ "$FREQUENCY" != "P" ]; then
    echo -e "${CRed}ERROR: Perpetual backups are not configured. Please check your configuration. Exiting.${CClear}\n"
    logger "BACKUPMON ERROR: Perpetual backups are not configured. Please check your configuration."
    exit 0
  fi

  if [ "$PURGE" -eq 0 ]; then
    return
  fi

  logoNM
  echo ""
  echo -e "${CYellow}Auto Purge Perpetual Backups Utility${CClear}"
  echo ""
  echo -e "${CCyan}You are about to purge backups! FUN! This action is irreversible, permanent and"
  echo -e "${CCyan}fully automatic, so you have zero control! AWESOMESAUCE! BACKUPMON will by"
  echo -e "${CCyan}default show you which backups older than ${CYellow}$PURGELIMIT days${CCyan} are being deleted, as you"
  echo -e "${CCyan}rejoice in seeing disk space being freed up."
  echo -e "\n${CCyan}Messages:"

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
    CNT=0
    TRIES=12
      while [ $CNT -lt $TRIES ]; do # Loop through number of tries
        mount -t cifs $UNC $UNCDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"  # Connect the UNC to the local drive mount
        MRC=$?
        if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
          echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") mounted successfully under: $UNCDRIVE ${CClear}"; printf "%s\n"
          break
        else
          echo -e "${CYellow}WARNING: Unable to mount to external drive. Trying every 10 seconds for 2 minutes."
          sleep 10
          CNT=$((CNT+1))
          if [ $CNT -eq $TRIES ];then
            echo -e "${CRed}ERROR: Unable to mount to external drive. Please check your configuration. Exiting.${CClear}\n"
            logger "BACKUPMON ERROR: Unable to mount to external drive. Please check your configuration!"
            exit 0
          fi
        fi
      done
    sleep 2
  fi

  # If the UNC is successfully mounted, proceed
  if [ -n "`mount | grep $UNCDRIVE`" ]; then

      # Continue with deleting backups permanently
      count=0
      for FOLDER in $(ls ${UNCDRIVE}${BKDIR} -1)
      do
        _DeleteFileDirAfterNumberOfDays_ "${UNCDRIVE}${BKDIR}/$FOLDER" $PURGELIMIT delete
      done

      # If there are no valid backups within range, display a message and exit
      if [ $count -eq 0 ]; then
        echo -e "${CYellow}INFO: No perpetual backup folders were identified older than $PURGELIMIT days.${CClear}"
        logger "BACKUPMON INFO: No perpetual backup folders were identified older than $PURGELIMIT days. Nothing to delete."
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountdrv

        echo -e "\n${CGreen}Exiting Auto Purge Perpetual Backups Utility...${CClear}\n"
        sleep 2
        return

      else

        echo -e "${CGreen}STATUS: Perpetual backup folders older than $PURGELIMIT days deleted.${CClear}"
        logger "BACKUPMON INFO: Perpetual backup folders older than $PURGELIMIT days were deleted."
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountdrv

        echo -e "\n${CGreen}Exiting Auto Purge Perpetual Backups Utility...${CClear}\n"
        sleep 2
        return
      fi

  else

    echo -e "${CGreen}STATUS: Settling for 10 seconds..."
    sleep 10

    unmountdrv

    echo -e "\n${CGreen}Exiting Auto Purge Perpetual Backups Utility...${CClear}"
    sleep 2
    return
  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# purgebackups is a function that allows you to see which backups will be purged before deleting them...
purgesecondaries() {

  if [ $SECONDARYPURGE -eq 0 ]; then
    return
  fi

  if [ $SECONDARYSTATUS -eq 0 ]; then
    return
  fi

  clear
  logoNM
  echo ""
  echo -e "${CYellow}Purge Perpetual Secondary Backups Utility${CClear}"
  echo ""
  echo -e "${CCyan}You are about to purge secondary backups! FUN! This action is irreversible and"
  echo -e "${CCyan}permanent. But no worries! BACKUPMON will first show you which backups are affected"
  echo -e "${CCyan}by the ${CYellow}$SECONDARYPURGELIMIT days${CCyan} limit you have configured."
  echo ""
  echo -e "${CCyan}Do you wish to proceed?${CClear}"
  if promptyn "(y/n): "; then

    echo ""
    echo -e "\n${CCyan}Messages:"

    # Create the local drive mount directory
    if ! [ -d $SECONDARYUNCDRIVE ]; then
        mkdir -p $SECONDARYUNCDRIVE
        chmod 777 $SECONDARYUNCDRIVE
        echo -e "${CYellow}ALERT: External Secondary Drive directory not set. Created under: $SECONDARYUNCDRIVE ${CClear}"
        sleep 3
    fi

    # If the mount does not exist yet, proceed
    if ! mount | grep $SECONDARYUNCDRIVE > /dev/null 2>&1; then

      # Check if the build supports modprobe
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      # Mount the local drive directory to the UNC
      CNT=0
      TRIES=12
        while [ $CNT -lt $TRIES ]; do # Loop through number of tries
          mount -t cifs $SECONDARYUNC $SECONDARYUNCDRIVE -o "vers=2.1,username=${SECONDARYUSER},password=${SECONDARYPWD}"  # Connect the UNC to the local drive mount
          MRC=$?
          if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
            echo -en "${CGreen}STATUS: Secondary External Drive ("; printf "%s" "${SECONDARYUNC}"; echo -en ") mounted successfully under: $SECONDARYUNCDRIVE ${CClear}"; printf "%s\n"
            break
          else
            echo -e "${CYellow}WARNING: Unable to mount to secondary external drive. Trying every 10 seconds for 2 minutes."
            sleep 10
            CNT=$((CNT+1))
            if [ $CNT -eq $TRIES ];then
              echo -e "${CRed}ERROR: Unable to mount to secondary external drive. Please check your configuration. Exiting."
              logger "BACKUPMON ERROR: Unable to mount to secondary external drive. Please check your configuration!"
              exit 0
            fi
          fi
        done
      sleep 2
    fi

    # If the UNC is successfully mounted, proceed
    if [ -n "`mount | grep $SECONDARYUNCDRIVE`" ]; then

      # Show a list of valid backups on screen
      count=0
      echo -e "${CGreen}STATUS: Perpetual secondary backup folders identified below are older than $SECONDARYPURGELIMIT days:${CRed}"
      for FOLDER in $(ls ${SECONDARYUNCDRIVE}${SECONDARYBKDIR} -1)
      do
        _DeleteFileDirAfterNumberOfDays_ "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/$FOLDER" $SECONDARYPURGELIMIT show
      done

      # If there are no valid backups within range, display a message and exit
      if [ $count -eq 0 ]; then
        echo -e "${CYellow}INFO: No perpetual secondary backup folders were identified older than $SECONDARYPURGELIMIT days.${CClear}"
        logger "BACKUPMON INFO: No perpetual secondary backup folders identified older than $SECONDARYPURGELIMIT days were found. Nothing to delete."
        read -rsp $'Press any key to acknowledge...\n' -n1 key
        echo ""
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountsecondarydrv

        echo -e "\n${CGreen}Exiting Purge Perpetual Secondary Backups Utility...${CClear}"
        sleep 2
        return
      fi

      # Continue with deleting backups permanently
      echo ""
      echo -e "${CGreen}Would you like to permanently purge these secondary backups?${CClear}"

      if promptyn "(y/n): "; then
        echo -e "\n${CRed}"
        for FOLDER in $(ls ${SECONDARYUNCDRIVE}${SECONDARYBKDIR} -1)
        do
          _DeleteFileDirAfterNumberOfDays_ "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/$FOLDER" $SECONDARYPURGELIMIT delete
        done

        echo ""
        echo -e "${CGreen}STATUS: Perpetual secondary backup folders older than $SECONDARYPURGELIMIT days deleted.${CClear}"
        logger "BACKUPMON INFO: Perpetual secondary backup folders older than $SECONDARYPURGELIMIT days were deleted."
        read -rsp $'Press any key to acknowledge...\n' -n1 key
        echo ""
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountsecondarydrv

        echo -e "\n${CGreen}Exiting Purge Perpetual Secondary Backups Utility...${CClear}\n"
        sleep 2
        return

      else

        echo ""
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountsecondarydrv

        echo -e "\n${CGreen}Exiting Purge Perpetual Secondary Backups Utility...${CClear}\n"
        sleep 2
        return
      fi
    fi

  else
    echo ""
    echo -e "\n${CGreen}Exiting Purge Perpetual Secondary Backups Utility...${CClear}"
    sleep 2
    return
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# autopurgesecondaries is a function that allows you to purge secondary backups throught a commandline switch... if you're daring!
autopurgesecondaries () {
  clear

  if [ "$SECONDARYFREQUENCY" != "P" ]; then
    echo -e "${CRed}ERROR: Perpetual secondary backups are not configured. Please check your configuration. Exiting.${CClear}\n"
    logger "BACKUPMON ERROR: Perpetual secondary backups are not configured. Please check your configuration."
    exit 0
  fi

  if [ $SECONDARYPURGE -eq 0 ]; then
    return
  fi

  if [ $SECONDARYSTATUS -eq 0 ]; then
    return
  fi

  logoNM
  echo ""
  echo -e "${CYellow}Auto Purge Perpetual Secondary Backups Utility${CClear}"
  echo ""
  echo -e "${CCyan}You are about to purge secondary backups! FUN! This action is irreversible, permanent"
  echo -e "${CCyan}and fully automatic, so you have zero control! AWESOMESAUCE! BACKUPMON will by"
  echo -e "${CCyan}default show you which backups older than ${CYellow}$SECONDARYPURGELIMIT days${CCyan} are being deleted, as you"
  echo -e "${CCyan}rejoice in seeing disk space being freed up."
  echo -e "\n${CCyan}Messages:"

  # Create the local drive mount directory
  if ! [ -d $SECONDARYUNCDRIVE ]; then
      mkdir -p $SECONDARYUNCDRIVE
      chmod 777 $SECONDARYUNCDRIVE
      echo -e "${CYellow}ALERT: External Secondary Drive directory not set. Created under: $SECONDARYUNCDRIVE ${CClear}"
      sleep 3
  fi

  # If the mount does not exist yet, proceed
  if ! mount | grep $SECONDARYUNCDRIVE > /dev/null 2>&1; then

    # Check if the build supports modprobe
    if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
      modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
    fi

    # Mount the local drive directory to the UNC
    CNT=0
    TRIES=12
      while [ $CNT -lt $TRIES ]; do # Loop through number of tries
        mount -t cifs $SECONDARYUNC $SECONDARYUNCDRIVE -o "vers=2.1,username=${SECONDARYUSER},password=${SECONDARYPWD}"  # Connect the UNC to the local drive mount
        MRC=$?
        if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
          echo -en "${CGreen}STATUS: Secondary External Drive ("; printf "%s" "${SECONDARYUNC}"; echo -en ") mounted successfully under: $SECONDARYUNCDRIVE ${CClear}"; printf "%s\n"
          break
        else
          echo -e "${CYellow}WARNING: Unable to mount to secondary external drive. Trying every 10 seconds for 2 minutes."
          sleep 10
          CNT=$((CNT+1))
          if [ $CNT -eq $TRIES ];then
            echo -e "${CRed}ERROR: Unable to mount to secondary external drive. Please check your configuration. Exiting.${CClear}\n"
            logger "BACKUPMON ERROR: Unable to mount to secondary external drive. Please check your configuration!"
            exit 0
          fi
        fi
      done
    sleep 2
  fi

  # If the UNC is successfully mounted, proceed
  if [ -n "`mount | grep $SECONDARYUNCDRIVE`" ]; then

      # Continue with deleting backups permanently
      count=0
      for FOLDER in $(ls ${SECONDARYUNCDRIVE}${SECONDARYBKDIR} -1)
      do
        _DeleteFileDirAfterNumberOfDays_ "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/$FOLDER" $SECONDARYPURGELIMIT delete
      done

      # If there are no valid backups within range, display a message and exit
      if [ $count -eq 0 ]; then
        echo -e "${CYellow}INFO: No perpetual secondary backup folders were identified older than $SECONDARYPURGELIMIT days.${CClear}"
        logger "BACKUPMON INFO: No perpetual secondary backup folders were identified older than $SECONDARYPURGELIMIT days. Nothing to delete."
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountsecondarydrv

        echo -e "\n${CGreen}Exiting Auto Purge Perpetual Secondary Backups Utility...${CClear}\n"
        sleep 2
        return

      else

        echo -e "${CGreen}STATUS: Perpetual secondary backup folders older than $SECONDARYPURGELIMIT days deleted.${CClear}"
        logger "BACKUPMON INFO: Perpetual secondary backup folders older than $SECONDARYPURGELIMIT days were deleted."
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountsecondarydrv

        echo -e "\n${CGreen}Exiting Auto Purge Perpetual Secondary Backups Utility...${CClear}\n"
        sleep 2
        return
      fi

  else

    echo -e "${CGreen}STATUS: Settling for 10 seconds..."
    sleep 10

    unmountsecondarydrv

    echo -e "\n${CGreen}Exiting Auto Purge Perpetual Secondary Backups Utility...${CClear}"
    sleep 2
    return
  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# vsetup is a function that sets up, confiures and allows you to launch backupmon on your router...
vsetup () {

  # Check for and add an alias for backupmon
  if ! grep -F "sh /jffs/scripts/backupmon.sh" /jffs/configs/profile.add >/dev/null 2>/dev/null; then
		echo "alias backupmon=\"sh /jffs/scripts/backupmon.sh\" # backupmon" >> /jffs/configs/profile.add
  fi

  # Determine if the config is local or under /jffs/addons/backupmon.d
  if [ -f $CFGPATH ]; then #Making sure file exists before proceeding
    source $CFGPATH
  elif [ -f /jffs/scripts/backupmon.cfg ]; then
    source /jffs/scripts/backupmon.cfg
    cp /jffs/scripts/backupmon.cfg /jffs/addons/backupmon.d/backupmon.cfg
  else
    clear
    echo -e "${CRed} WARNING: BACKUPMON is not configured. Going through 1st time setup!"
    sleep 3
    vconfig
  fi

  while true; do
    clear
    logoNM
    echo ""
    echo -e "${CYellow}Setup + Operations Menu${CClear}" # Provide main setup menu
    echo ""
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${CGreen}Operations"
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${InvDkGray}${CWhite} bk ${CClear}${CCyan}: Run a Manual Backup"
    echo -e "${InvDkGray}${CWhite} rs ${CClear}${CCyan}: Run a Manual Restore"
    if [ $PURGE == "1" ]; then
      echo -e "${InvDkGray}${CWhite} pg ${CClear}${CCyan}: Purge Perpetual Primary Backups"
    else
      echo -e "${InvDkGray}${CWhite} pg ${CClear}${CDkGray}: Purge Perpetual Primary Backups"
    fi
    if [ $SECONDARYPURGE == "1" ] && [ $SECONDARYSTATUS -eq 1 ]; then
      echo -e "${InvDkGray}${CWhite} ps ${CClear}${CCyan}: Purge Perpetual Secondary Backups"
    else
      echo -e "${InvDkGray}${CWhite} ps ${CClear}${CDkGray}: Purge Perpetual Secondary Backups"
    fi
    echo ""
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${CGreen}Setup + Configuration"
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${InvDkGray}${CWhite} sc ${CClear}${CCyan}: Setup and Configure BACKUPMON"
    echo -e "${InvDkGray}${CWhite} ts ${CClear}${CCyan}: Test your Network Backup Target"
    echo -e "${InvDkGray}${CWhite} up ${CClear}${CCyan}: Check for latest updates"
    echo -e "${InvDkGray}${CWhite} un ${CClear}${CCyan}: Uninstall"
    echo -e "${InvDkGray}${CWhite}  e ${CClear}${CCyan}: Exit"
    echo -e "${CGreen}----------------------------------------------------------------"
    echo ""
    printf "Selection: "
    read -r InstallSelection

    # Execute chosen selections
        case "$InstallSelection" in

          bk)
            clear
            sh /jffs/scripts/backupmon.sh -backup
          ;;

          rs)
            clear
            sh /jffs/scripts/backupmon.sh -restore
          ;;

          pg)
            clear
            if [ $FREQUENCY == "P" ]; then
              purgebackups
            fi
          ;;

          ps)
            clear
            if [ $SECONDARYFREQUENCY == "P" ]; then
              purgesecondaries
            fi
          ;;

          sc)
            clear
            vconfig
          ;;

          ts)
            clear
            testtarget
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

      CNT=0
      TRIES=12
        while [ $CNT -lt $TRIES ]; do # Loop through number of tries
          mount -t cifs $UNC $UNCDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"  # Connect the UNC to the local drive mount
          MRC=$?
          if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
            break
          else
            echo -e "${CYellow}WARNING: Unable to mount to external drive. Trying every 10 seconds for 2 minutes."
            sleep 10
            CNT=$((CNT+1))
            if [ $CNT -eq $TRIES ];then
              echo -e "${CRed}ERROR: Unable to mount to external drive. Please check your configuration. Exiting."
              logger "BACKUPMON ERROR: Unable to mount to external drive. Please check your configuration!"
              exit 0
            fi
          fi
        done
  fi

  # If the local mount is connected to the UNC, proceed
  if [ -n "`mount | grep $UNCDRIVE`" ]; then

      echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -en ") mounted successfully under: $UNCDRIVE ${CClear}"; printf "%s\n"

      # Create the backup directories and daily directories if they do not exist yet
      if ! [ -d "${UNCDRIVE}${BKDIR}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}"; echo -e "${CGreen}STATUS: Backup Directory successfully created."; fi

      # Create frequency folders by week, month, year or perpetual
      if [ $FREQUENCY == "W" ]; then
        if ! [ -d "${UNCDRIVE}${BKDIR}/${WDAY}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}/${WDAY}"; echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}";fi
      elif [ $FREQUENCY == "M" ]; then
        if ! [ -d "${UNCDRIVE}${BKDIR}/${MDAY}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}/${MDAY}"; echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}";fi
      elif [ $FREQUENCY == "Y" ]; then
        if ! [ -d "${UNCDRIVE}${BKDIR}/${YDAY}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}/${YDAY}"; echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}";fi
      elif [ $FREQUENCY == "P" ]; then
        PDAY=$(date +"%Y%m%d-%H%M%S")
        if ! [ -d "${UNCDRIVE}${BKDIR}/${PDAY}" ]; then mkdir -p "${UNCDRIVE}${BKDIR}/${PDAY}"; echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}";fi
      fi

      if [ $MODE == "Basic" ]; then
        # Remove old tar files if they exist in the daily folders
        if [ $FREQUENCY == "W" ]; then
          [ -f ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar*
          [ -f ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg* ] && rm ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg*
          [ -f ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar*
        elif [ $FREQUENCY == "M" ]; then
          [ -f ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar*
          [ -f ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg* ] && rm ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg*
          [ -f ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar*
        elif [ $FREQUENCY == "Y" ]; then
          [ -f ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar*
          [ -f ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg* ] && rm ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg*
          [ -f ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar*
        elif [ $FREQUENCY == "P" ]; then
          [ -f ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar*
          [ -f ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg* ] && rm ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg*
          [ -f ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar*
        fi
      fi

      if [ $MODE == "Basic" ]; then
        # If a TAR exclusion file exists, use it for the /jffs backup
        if [ $FREQUENCY == "W" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg.${CClear}"
          sleep 1

        elif [ $FREQUENCY == "M" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg.${CClear}"
          sleep 1

        elif [ $FREQUENCY == "Y" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg.${CClear}"
          sleep 1

        elif [ $FREQUENCY == "P" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg.${CClear}"
          sleep 1
        fi

        # If a TAR exclusion file exists, use it for the USB drive backup
        if [ "$EXTLABEL" != "NOTFOUND" ]; then
          if [ $FREQUENCY == "W" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz.${CClear}"
            sleep 1
          elif [ $FREQUENCY == "M" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz.${CClear}"
            sleep 1
          elif [ $FREQUENCY == "Y" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz.${CClear}"
            sleep 1
          elif [ $FREQUENCY == "P" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} to ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz.${CClear}"
            sleep 1
          fi
        else
          echo -e "${CYellow}WARNING: External USB drive not found. Skipping backup."
          logger "BACKUPMON WARNING: External USB drive not found. Skipping backup."
        fi

      elif [ $MODE == "Advanced" ]; then

        datelabel=$(date +"%Y%m%d-%H%M%S")
        # If a TAR exclusion file exists, use it for the /jffs backup
        if [ $FREQUENCY == "W" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${WDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram-${datelabel}.cfg.${CClear}"
          sleep 1

        elif [ $FREQUENCY == "M" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${MDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram-${datelabel}.cfg.${CClear}"
          sleep 1

        elif [ $FREQUENCY == "Y" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${YDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram-${datelabel}.cfg.${CClear}"
          sleep 1

        fi

        # If a TAR exclusion file exists, use it for the USB drive backup
        if [ "$EXTLABEL" != "NOTFOUND" ]; then
          if [ $FREQUENCY == "W" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            sleep 1
          elif [ $FREQUENCY == "M" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            sleep 1
          elif [ $FREQUENCY == "Y" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished backing up EXT Drive to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            sleep 1
          fi
        else
          echo -e "${CYellow}WARNING: External USB drive not found. Skipping backup."
          logger "BACKUPMON WARNING: External USB drive not found. Skipping backup."
        fi
      fi

      #added copies of the backupmon.sh, backupmon.cfg, exclusions list and NVRAM to backup location for easy copy/restore
      cp /jffs/scripts/backupmon.sh ${UNCDRIVE}${BKDIR}/backupmon.sh
      echo -e "${CGreen}STATUS: Finished copying ${CYellow}backupmon.sh${CGreen} script to ${UNCDRIVE}${BKDIR}.${CClear}"
      cp $CFGPATH ${UNCDRIVE}${BKDIR}/backupmon.cfg
      echo -e "${CGreen}STATUS: Finished copying ${CYellow}backupmon.cfg${CGreen} script to ${UNCDRIVE}${BKDIR}.${CClear}"

      if ! [ -z $EXCLUSION ]; then
        EXCLFILE=$(echo $EXCLUSION | sed 's:.*/::')
        cp $EXCLUSION ${UNCDRIVE}${BKDIR}/$EXCLFILE
        echo -e "${CGreen}STATUS: Finished copying ${CYellow}$EXCLFILE${CGreen} script to ${UNCDRIVE}${BKDIR}.${CClear}"
      fi

      #Please note: the nvram.txt export is for reference only. This file cannot be used to restore from, just to reference from.
      nvram show 2>/dev/null > ${UNCDRIVE}${BKDIR}/nvram.txt
      echo -e "${CGreen}STATUS: Finished copying reference ${CYellow}nvram.txt${CGreen} extract to ${UNCDRIVE}${BKDIR}.${CClear}"

      #include restore instructions in the backup location
      { echo 'RESTORE INSTRUCTIONS'
        echo ''
        echo 'IMPORTANT: Your original USB Drive name was:' ${EXTLABEL}
        echo ''
        echo 'Please ensure your have performed the following before restoring your backups:'
        echo '1.) Enable SSH in router UI, and connect via an SSH Terminal (like PuTTY).'
        echo '2.) Run "AMTM" and format a new USB drive on your router - call it exactly the same name as before (see above)! Reboot.'
        echo '3.) After reboot, SSH back in to AMTM, create your swap file (if required). This action should automatically enable JFFS.'
        echo '4.) From the UI, verify JFFS scripting enabled in the router OS, if not, enable and perform another reboot.'
        echo '5.) Restore the backupmon.sh & backupmon.cfg files (located under your backup folder) into your /jffs/scripts folder.'
        echo '6.) Run "sh backupmon.sh -setup" and ensure that all of the settings are correct before running a restore.'
        echo '7.) Run "sh backupmon.sh -restore", pick which backup you want to restore, and confirm before proceeding!'
        echo '8.) After the restore finishes, perform another reboot.  Everything should be restored as normal!'
      } > ${UNCDRIVE}${BKDIR}/instructions.txt
      echo -e "${CGreen}STATUS: Finished copying restoration ${CYellow}instructions.txt${CGreen} to ${UNCDRIVE}${BKDIR}.${CClear}"
      echo -e "${CGreen}STATUS: Settling for 10 seconds..."
      sleep 10

      # Unmount the locally connected mounted drive
      unmountdrv

  else

      # There's problems with mounting the drive - check paths and permissions!
      echo -e "${CRed}ERROR: Failed to run Backup Script -- Drive mount failed. Please check your configuration!${CClear}"
      logger "BACKUPMON ERROR: Failed to run Backup Script -- Drive mount failed. Please check your configuration!"
      sleep 3

  fi

}

# backup routine by @Jeffrey Young showing a great way to connect to an external network location to dump backups to
secondary() {

  if [ $SECONDARYSTATUS -eq 0 ]; then
    return
  fi

  # Run a secondary backup
  echo ""
  echo -e "${CGreen}[Secondary Backup Commencing]..."
  echo ""
  echo -e "${CCyan}Messages:"

  # Check to see if a local drive mount is available, if not, create one.
  if ! [ -d $SECONDARYUNCDRIVE ]; then
      mkdir -p $SECONDARYUNCDRIVE
      chmod 777 $SECONDARYUNCDRIVE
      echo -e "${CYellow}ALERT: Secondary External Drive directory not set. Newly created under: $SECONDARYUNCDRIVE ${CClear}"
      sleep 3
  fi

  # If everything successfully was created, proceed
  if ! mount | grep $SECONDARYUNCDRIVE > /dev/null 2>&1; then

      # Check the build to see if modprobe needs to be called
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      CNT=0
      TRIES=12
        while [ $CNT -lt $TRIES ]; do # Loop through number of tries
          mount -t cifs $SECONDARYUNC $SECONDARYUNCDRIVE -o "vers=2.1,username=${SECONDARYUSER},password=${SECONDARYPWD}"  # Connect the UNC to the local drive mount
          MRC=$?
          if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
            break
          else
            echo -e "${CYellow}WARNING: Unable to mount to secondary external drive. Trying every 10 seconds for 2 minutes."
            sleep 10
            CNT=$((CNT+1))
            if [ $CNT -eq $TRIES ];then
              echo -e "${CRed}ERROR: Unable to mount to secondary external drive. Please check your configuration. Exiting."
              logger "BACKUPMON ERROR: Unable to mount to secondary external drive. Please check your configuration!"
              exit 0
            fi
          fi
        done
  fi

  # If the local mount is connected to the UNC, proceed
  if [ -n "`mount | grep $SECONDARYUNCDRIVE`" ]; then

      echo -en "${CGreen}STATUS: Secondary External Drive ("; printf "%s" "${SECONDARYUNC}"; echo -en ") mounted successfully under: $SECONDARYUNCDRIVE ${CClear}"; printf "%s\n"

      # Create the secondary backup directories and daily directories if they do not exist yet
      if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}" ]; then mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}"; echo -e "${CGreen}STATUS: Secondary Backup Directory successfully created."; fi

      # Create frequency folders by week, month, year or perpetual
      if [ $SECONDARYFREQUENCY == "W" ]; then
        if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}" ]; then mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}"; echo -e "${CGreen}STATUS: Daily Secondary Backup Directory successfully created.${CClear}";fi
      elif [ $SECONDARYFREQUENCY == "M" ]; then
        if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}" ]; then mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}"; echo -e "${CGreen}STATUS: Daily Secondary Backup Directory successfully created.${CClear}";fi
      elif [ $SECONDARYFREQUENCY == "Y" ]; then
        if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}" ]; then mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}"; echo -e "${CGreen}STATUS: Daily Secondary Backup Directory successfully created.${CClear}";fi
      elif [ $SECONDARYFREQUENCY == "P" ]; then
        PDAY=$(date +"%Y%m%d-%H%M%S")
        if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}" ]; then mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}"; echo -e "${CGreen}STATUS: Daily Secondary Backup Directory successfully created.${CClear}";fi
      fi

      if [ $SECONDARYMODE == "Basic" ]; then
        # Remove old tar files if they exist in the daily folders
        if [ $SECONDARYFREQUENCY == "W" ]; then
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar*
        elif [ $SECONDARYFREQUENCY == "M" ]; then
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar*
        elif [ $SECONDARYFREQUENCY == "Y" ]; then
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar*
        elif [ $SECONDARYFREQUENCY == "P" ]; then
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar*
        fi
      fi

      if [ $SECONDARYMODE == "Basic" ]; then
        # If a TAR exclusion file exists, use it for the /jffs backup
        if [ $SECONDARYFREQUENCY == "W" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg.${CClear}"
          sleep 1

        elif [ $SECONDARYFREQUENCY == "M" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg.${CClear}"
          sleep 1

        elif [ $SECONDARYFREQUENCY == "Y" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg.${CClear}"
          sleep 1

        elif [ $SECONDARYFREQUENCY == "P" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg.${CClear}"
          sleep 1

        fi

        # If a TAR exclusion file exists, use it for the USB drive backup
        if [ "$EXTLABEL" != "NOTFOUND" ]; then
          if [ $SECONDARYFREQUENCY == "W" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive to ${SECONDARYUNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz.${CClear}"
            sleep 1
          elif [ $SECONDARYFREQUENCY == "M" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz.${CClear}"
            sleep 1
          elif [ $SECONDARYFREQUENCY == "Y" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz.${CClear}"
            sleep 1
          elif [ $SECONDARYFREQUENCY == "P" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz.${CClear}"
            sleep 1
          fi
        else
          echo -e "${CYellow}WARNING: External USB drive not found. Skipping backup."
          logger "BACKUPMON WARNING: External USB drive not found. Skipping backup."
        fi

      elif [ $SECONDARYMODE == "Advanced" ]; then

        datelabel=$(date +"%Y%m%d-%H%M%S")
        # If a TAR exclusion file exists, use it for the /jffs backup
        if [ $SECONDARYFREQUENCY == "W" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram-${datelabel}.cfg.${CClear}"
          sleep 1

        elif [ $SECONDARYFREQUENCY == "M" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram-${datelabel}.cfg.${CClear}"
          sleep 1

        elif [ $SECONDARYFREQUENCY == "Y" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          sleep 1

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram-${datelabel}.cfg.${CClear}"
          sleep 1
        fi

        # If a TAR exclusion file exists, use it for the USB drive backup
        if [ "$EXTLABEL" != "NOTFOUND" ]; then
          if [ $SECONDARYFREQUENCY == "W" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            sleep 1
          elif [ $SECONDARYFREQUENCY == "M" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            sleep 1
          elif [ $SECONDARYFREQUENCY == "Y" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            sleep 1
          fi
        else
          echo -e "${CYellow}WARNING: External USB drive not found. Skipping backup."
          logger "BACKUPMON WARNING: External USB drive not found. Skipping backup."
        fi
      fi

      #added copies of the backupmon.sh, backupmon.cfg, exclusions list and NVRAM to backup location for easy copy/restore
      cp /jffs/scripts/backupmon.sh ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/backupmon.sh
      echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}backupmon.sh${CGreen} script to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"
      cp $CFGPATH ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/backupmon.cfg
      echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}backupmon.cfg${CGreen} script to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"

      if ! [ -z $SECONDARYEXCLUSION ]; then
        EXCLFILE=$(echo $SECONDARYEXCLUSION | sed 's:.*/::')
        cp $SECONDARYEXCLUSION ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/$EXCLFILE
        echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}$EXCLFILE${CGreen} script to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"
      fi

      #Please note: the nvram.txt export is for reference only. This file cannot be used to restore from, just to reference from.
      nvram show 2>/dev/null > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/nvram.txt
      echo -e "${CGreen}STATUS: Finished secondary reference copy of ${CYellow}nvram.txt${CGreen} extract to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"

      #include restore instructions in the backup location
      { echo 'RESTORE INSTRUCTIONS'
        echo ''
        echo 'IMPORTANT: Your original USB Drive name was:' ${EXTLABEL}
        echo ''
        echo 'Please ensure your have performed the following before restoring your backups:'
        echo '1.) Enable SSH in router UI, and connect via an SSH Terminal (like PuTTY).'
        echo '2.) Run "AMTM" and format a new USB drive on your router - call it exactly the same name as before (see above)! Reboot.'
        echo '3.) After reboot, SSH back in to AMTM, create your swap file (if required). This action should automatically enable JFFS.'
        echo '4.) From the UI, verify JFFS scripting enabled in the router OS, if not, enable and perform another reboot.'
        echo '5.) Restore the backupmon.sh & backupmon.cfg files (located under your backup folder) into your /jffs/scripts folder.'
        echo '6.) Run "sh backupmon.sh -setup" and ensure that all of the settings are correct before running a restore.'
        echo '7.) Run "sh backupmon.sh -restore", pick which backup you want to restore, and confirm before proceeding!'
        echo '8.) After the restore finishes, perform another reboot.  Everything should be restored as normal!'
      } > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/instructions.txt
      echo -e "${CGreen}STATUS: Finished secondary copy of restoration ${CYellow}instructions.txt${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"
      echo -e "${CGreen}STATUS: Settling for 10 seconds..."
      sleep 10

      # Unmount the locally connected mounted drive
      unmountsecondarydrv

  else

      # There's problems with mounting the drive - check paths and permissions!
      echo -e "${CRed}ERROR: Failed to run Secondary Backup Script -- Drive mount failed. Please check your configuration!${CClear}"
      logger "BACKUPMON ERROR: Failed to run Secondary Backup Script -- Drive mount failed. Please check your configuration!"
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
  echo -e "${CGreen}1.) Enable SSH in router UI, and connect via an SSH Terminal (like PuTTY)."
  echo -e "${CGreen}2.) Run 'AMTM' and format a new USB drive on your router - call it exactly the same name as before! Reboot."
  echo -e "${CYellow}    (please refer to your restore instruction.txt file to find your original USB drive label)"
  echo -e "${CGreen}3.) After reboot, SSH back in to AMTM, create your swap file (if required). This action should automatically enable JFFS."
  echo -e "${CGreen}4.) From the UI, verify JFFS scripting enabled in the router OS, if not, enable and perform another reboot."
  echo -e "${CGreen}5.) Restore the backupmon.sh & backupmon.cfg files (located under your backup folder) into your /jffs/scripts folder."
  echo -e "${CGreen}6.) Run 'sh backupmon.sh -setup' and ensure that all of the settings are correct before running a restore."
  echo -e "${CGreen}7.) Run 'sh backupmon.sh -restore', pick which backup you want to restore, and confirm before proceeding!"
  echo -e "${CGreen}8.) After the restore finishes, perform another reboot.  Everything should be restored as normal!"
  echo ""
  if [ $SECONDARYSTATUS -eq 1 ]; then
    echo -e "${CYellow}Please choose whether you would like to restore from primary or secondary backups? (Primary=P, Secondary=S)"
    while true; do
      read -p 'Restoration Source (P/S)?: ' RESTOREFROM
        case $RESTOREFROM in
          [Pp] ) SOURCE="Primary"; echo ""; echo -e "${CGreen}[Primary Backup Source Selected]"; echo ""; break ;;
          [Ss] ) SOURCE="Secondary"; echo ""; echo -e "${CGreen}[Secondary Backup Source Selected]"; echo ""; break ;;
          "" ) echo -e "\n Error: Please use either P or S.\n";;
          * ) echo -e "\n Error: Please use either P or S.\n";;
        esac
    done
  else
    SOURCE="Primary"
  fi

  echo -e "${CCyan}Messages:"

  # Determine router model
  [ -z "$(nvram get odmpid)" ] && RESTOREMODEL="$(nvram get productid)" || RESTOREMODEL="$(nvram get odmpid)" # Thanks @thelonelycoder for this logic

  if [ "$ROUTERMODEL" != "$RESTOREMODEL" ]; then
    echo -e "${CRed}ERROR: Original source router model is different from target router model."
    echo -e "${CRed}ERROR: Restorations can only be performed on the same source/target router model or you may brick your router!"
    echo -e "${CRed}ERROR: If you are certain source/target routers are the same, please check and re-save your configuration!${CClear}"
    logger "BACKUPMON ERROR: Original source router model is different from target router model. Please check your configuration!"
    echo ""
    exit 0
  fi

  if [ "$SOURCE" == "Primary" ]; then

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
      CNT=0
      TRIES=12
        while [ $CNT -lt $TRIES ]; do # Loop through number of tries
          mount -t cifs $UNC $UNCDRIVE -o "vers=2.1,username=${USERNAME},password=${PASSWORD}"  # Connect the UNC to the local drive mount
          MRC=$?
          if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
            echo -e "${CGreen}STATUS: External Drive ($UNC) mounted successfully under: $UNCDRIVE ${CClear}"
            break
          else
            echo -e "${CYellow}WARNING: Unable to mount to external drive. Trying every 10 seconds for 2 minutes."
            sleep 10
            CNT=$((CNT+1))
            if [ $CNT -eq $TRIES ];then
              echo -e "${CRed}ERROR: Unable to mount to external drive. Please check your configuration. Exiting."
              logger "BACKUPMON ERROR: Unable to mount to external drive. Please check your configuration!"
              exit 0
            fi
          fi
        done
      sleep 2
    fi

    # If the UNC is successfully mounted, proceed
    if [ -n "`mount | grep $UNCDRIVE`" ]; then

      # Show a list of valid backups on screen
      echo -e "${CGreen}Available Backup Selections:${CClear}"
      ls -ld ${UNCDRIVE}${BKDIR}/*/
      echo ""
      echo -e "${CGreen}Would you like to continue to restore from backup?"

      if promptyn "(y/n): "; then

        while true; do
          echo ""
          echo -e "${CGreen}"
            ok=0
            while [ $ok = 0 ]
            do
              if [ $FREQUENCY == "W" ]; then
                echo -e "${CGreen}Enter the Day of the backup you wish to restore? (ex: Mon or Fri) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountdrv; echo -e "${CClear}"; exit 0; fi
                if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "M" ]; then
                echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 02 or 27) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountdrv; echo -e "${CClear}"; exit 0; fi
                if [ ${#BACKUPDATE1} -gt 2 ] || [ ${#BACKUPDATE1} -lt 2 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 2 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "Y" ]; then
                echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 002 or 270) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountdrv; echo -e "${CClear}"; exit 0; fi
                if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "P" ]; then
                echo -e "${CGreen}Enter the exact folder name of the backup you wish to restore? (ex: 20230909-083422) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountdrv; echo -e "${CClear}"; exit 0; fi
                if [ ${#BACKUPDATE1} -gt 15 ] || [ ${#BACKUPDATE1} -lt 15 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 15 characters for the folder name format"; echo ""
                else
                  ok=1
                fi
              fi
            done

            if [ -z "$BACKUPDATE1" ]; then echo ""; echo -e "${CRed}ERROR: Invalid backup set chosen. Exiting script...${CClear}"; echo ""; exit 0; else BACKUPDATE=$BACKUPDATE1; fi

            if [ $MODE == "Basic" ]; then
              break
            elif [ $MODE == "Advanced" ]; then
              echo ""
              echo -e "${CGreen}Available Backup Files under:${CClear}"

              ls -lR /${UNCDRIVE}${BKDIR}/$BACKUPDATE

              echo ""
              echo -e "${CGreen}Would you like to continue using this backup set?"
              if promptyn "(y/n): "; then
                echo ""
                echo ""
                echo -e "${CGreen}Enter the EXACT file name (including extensions) of the JFFS backup you wish to restore?${CClear}"
                read ADVJFFS
                echo ""
                if [ "$EXTLABEL" != "NOTFOUND" ]; then
                  echo -e "${CGreen}Enter the EXACT file name (including extensions) of the EXT USB backup you wish to restore?${CClear}"
                  read ADVUSB
                  echo ""
                fi
                echo -e "${CGreen}Enter the EXACT file name (including extensions) of the NVRAM backup you wish to restore?${CClear}"
                read ADVNVRAM
                break
              fi
            fi
        done

          if [ $MODE == "Basic" ]; then
            echo ""
            echo -e "${CRed}WARNING: You will be restoring a backup of your JFFS, the entire contents of your External"
            echo -e "USB drive and NVRAM back to their original locations.  You will be restoring from this backup location:"
            echo -e "${CBlue}${UNCDRIVE}${BKDIR}/$BACKUPDATE/"
            echo ""
            echo -e "${CGreen}LAST CHANCE: Are you absolutely sure you like to continue to restore from backup?"
            if promptyn "(y/n): "; then
              echo ""
              echo ""
              # Run the TAR commands to restore backups to their original locations
              echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz to /jffs${CClear}"
              tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz -C /jffs >/dev/null
              if [ "$EXTLABEL" != "NOTFOUND" ]; then
                echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz to $EXTDRIVE${CClear}"
                tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz -C $EXTDRIVE >/dev/null
              else
                echo -e "${CYellow}WARNING: External USB drive not found. Skipping restore."
                logger "BACKUPMON WARNING: External USB drive not found. Skipping restore."
              fi
              echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/nvram.cfg to NVRAM${CClear}"
              nvram restore ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/nvram.cfg >/dev/null 2>&1
              echo ""
              echo -e "${CGreen}STATUS: Backups were successfully restored to their original locations.  Forcing reboot now!${CClear}"
              echo ""
              /sbin/service 'reboot'
            fi

          elif [ $MODE == "Advanced" ]; then
            echo ""
            echo -e "${CRed}WARNING: You will be restoring a backup of your JFFS, the entire contents of your External"
            echo -e "USB drive and NVRAM back to their original locations.  You will be restoring from this backup location:"
            echo -e "${CBlue}${UNCDRIVE}${BKDIR}/$BACKUPDATE/"
            echo -e "JFFS filename: $ADVJFFS"
            if [ "$EXTLABEL" != "NOTFOUND" ]; then
              echo -e "EXT USB filename: $ADVUSB"
            fi
            echo -e "NVRAM filename: $ADVNVRAM"
            echo ""
            echo -e "${CGreen}LAST CHANCE: Are you absolutely sure you like to continue to restore from backup?"
            if promptyn "(y/n): "; then
              echo ""
              echo ""
              # Run the TAR commands to restore backups to their original locations
              echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVJFFS} to /jffs${CClear}"
              tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVJFFS} -C /jffs >/dev/null
              if [ "$EXTLABEL" != "NOTFOUND" ]; then
                echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVUSB} to $EXTDRIVE${CClear}"
                tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVUSB} -C $EXTDRIVE >/dev/null
              else
                echo -e "${CYellow}WARNING: External USB drive not found. Skipping restore."
                logger "BACKUPMON WARNING: External USB drive not found. Skipping restore."
              fi
              echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVNVRAM} to NVRAM${CClear}"
              nvram restore ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVNVRAM} >/dev/null 2>&1
              echo ""
              echo -e "${CGreen}STATUS: Backups were successfully restored to their original locations.  Forcing reboot now!${CClear}"
              echo ""
              /sbin/service 'reboot'
            fi
          fi

          # Unmount the backup drive
          echo ""
          echo ""
          echo -e "${CGreen}STATUS: Settling for 10 seconds..."
          sleep 10

          unmountdrv

          echo ""
          echo -e "${CClear}"
          exit 0

      else

          # Exit gracefully
          echo ""
          echo ""
          echo -e "${CGreen}STATUS: Settling for 10 seconds..."
          sleep 10

          unmountdrv

          echo -e "${CClear}"
          exit 0

        fi

    else

      # Exit gracefully
      echo ""
      echo ""
      echo -e "${CGreen}STATUS: Settling for 10 seconds..."
      sleep 10

      unmountdrv

      echo -e "${CClear}"
      exit 0

    fi

  elif [ "$SOURCE" == "Secondary" ]; then

    # Create the local drive mount directory
    if ! [ -d $SECONDARYUNCDRIVE ]; then
        mkdir -p $SECONDARYUNCDRIVE
        chmod 777 $SECONDARYUNCDRIVE
        echo -e "${CYellow}ALERT: Secondary External Drive directory not set. Created under: $SECONDARYUNCDRIVE ${CClear}"
        sleep 3
    fi

    # If the mount does not exist yet, proceed
    if ! mount | grep $SECONDARYUNCDRIVE > /dev/null 2>&1; then

      # Check if the build supports modprobe
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      # Mount the local drive directory to the Secondary UNC
      CNT=0
      TRIES=12
        while [ $CNT -lt $TRIES ]; do # Loop through number of tries
          mount -t cifs $SECONDARYUNC $SECONDARYUNCDRIVE -o "vers=2.1,username=${SECONDARYUSER},password=${SECONDARYPWD}"  # Connect the UNC to the local drive mount
          MRC=$?
          if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
            echo -e "${CGreen}STATUS: Secondary External Drive ($SECONDARYUNC) mounted successfully under: $SECONDARYUNCDRIVE ${CClear}"
            break
          else
            echo -e "${CYellow}WARNING: Unable to mount to secondary external drive. Trying every 10 seconds for 2 minutes."
            sleep 10
            CNT=$((CNT+1))
            if [ $CNT -eq $TRIES ];then
              echo -e "${CRed}ERROR: Unable to mount to secondary external drive. Please check your configuration. Exiting."
              logger "BACKUPMON ERROR: Unable to mount to secondary external drive. Please check your configuration!"
              exit 0
            fi
          fi
        done
      sleep 2
    fi

    # If the UNC is successfully mounted, proceed
    if [ -n "`mount | grep $SECONDARYUNCDRIVE`" ]; then

      # Show a list of valid backups on screen
      echo -e "${CGreen}Available Backup Selections:${CClear}"
      ls -ld ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/*/
      echo ""
      echo -e "${CGreen}Would you like to continue to restore from backup?"

      if promptyn "(y/n): "; then

        while true; do
          echo ""
          echo -e "${CGreen}"
            ok=0
            while [ $ok = 0 ]
            do
              if [ $SECONDARYFREQUENCY == "W" ]; then
                echo -e "${CGreen}Enter the Day of the backup you wish to restore? (ex: Mon or Fri) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountsecondarydrv; echo -e "${CClear}"; exit 0; fi
                if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "M" ]; then
                echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 02 or 27) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountsecondarydrv; echo -e "${CClear}"; exit 0; fi
                if [ ${#BACKUPDATE1} -gt 2 ] || [ ${#BACKUPDATE1} -lt 2 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 2 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "Y" ]; then
                echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 002 or 270) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountsecondarydrv; echo -e "${CClear}"; exit 0; fi
                if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "P" ]; then
                echo -e "${CGreen}Enter the exact folder name of the backup you wish to restore? (ex: 20230909-083422) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountsecondarydrv; echo -e "${CClear}"; exit 0; fi
                if [ ${#BACKUPDATE1} -gt 15 ] || [ ${#BACKUPDATE1} -lt 15 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 15 characters for the folder name format"; echo ""
                else
                  ok=1
                fi
              fi
            done

            if [ -z "$BACKUPDATE1" ]; then echo ""; echo -e "${CRed}ERROR: Invalid backup set chosen. Exiting script...${CClear}"; echo ""; exit 0; else BACKUPDATE=$BACKUPDATE1; fi

            if [ $SECONDARYMODE == "Basic" ]; then
              break
            elif [ $SECONDARYMODE == "Advanced" ]; then
              echo ""
              echo -e "${CGreen}Available Secondary Backup Files under:${CClear}"

              ls -lR /${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/$BACKUPDATE

              echo ""
              echo -e "${CGreen}Would you like to continue using this secondary backup set?"
              if promptyn "(y/n): "; then
                echo ""
                echo ""
                echo -e "${CGreen}Enter the EXACT file name (including extensions) of the JFFS backup you wish to restore?${CClear}"
                read ADVJFFS
                echo ""
                if [ "$EXTLABEL" != "NOTFOUND" ]; then
                  echo -e "${CGreen}Enter the EXACT file name (including extensions) of the EXT USB backup you wish to restore?${CClear}"
                  read ADVUSB
                  echo ""
                fi
                echo -e "${CGreen}Enter the EXACT file name (including extensions) of the NVRAM backup you wish to restore?${CClear}"
                read ADVNVRAM
                break
              fi
            fi
        done

          if [ $SECONDARYMODE == "Basic" ]; then
            echo ""
            echo -e "${CRed}WARNING: You will be restoring a secondary backup of your JFFS, the entire contents of your External"
            echo -e "USB drive and NVRAM back to their original locations.  You will be restoring from this secondary backup location:"
            echo -e "${CBlue}${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/$BACKUPDATE/"
            echo ""
            echo -e "${CGreen}LAST CHANCE: Are you absolutely sure you like to continue to restore from backup?"
            if promptyn "(y/n): "; then
              echo ""
              echo ""
              # Run the TAR commands to restore backups to their original locations
              echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/jffs.tar.gz to /jffs${CClear}"
              tar -xzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/jffs.tar.gz -C /jffs >/dev/null
              if [ "$EXTLABEL" != "NOTFOUND" ]; then
                echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz to $EXTDRIVE${CClear}"
                tar -xzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz -C $EXTDRIVE >/dev/null
              else
                echo -e "${CYellow}WARNING: External USB drive not found. Skipping restore."
                logger "BACKUPMON WARNING: External USB drive not found. Skipping restore."
              fi
              echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/nvram.cfg to NVRAM${CClear}"
              nvram restore ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/nvram.cfg >/dev/null 2>&1
              echo ""
              echo -e "${CGreen}STATUS: Secondary backups were successfully restored to their original locations.  Forcing reboot now!${CClear}"
              echo ""
              /sbin/service 'reboot'
            fi

          elif [ $SECONDARYMODE == "Advanced" ]; then
            echo ""
            echo -e "${CRed}WARNING: You will be restoring a secondary backup of your JFFS, the entire contents of your External"
            echo -e "USB drive and NVRAM back to their original locations.  You will be restoring from this secondary backup location:"
            echo -e "${CBlue}${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/$BACKUPDATE/"
            echo -e "JFFS filename: $ADVJFFS"
            if [ "$EXTLABEL" != "NOTFOUND" ]; then
              echo -e "EXT USB filename: $ADVUSB"
            fi
            echo -e "NVRAM filename: $ADVNVRAM"
            echo ""
            echo -e "${CGreen}LAST CHANCE: Are you absolutely sure you like to continue to restore from backup?"
            if promptyn "(y/n): "; then
              echo ""
              echo ""
              # Run the TAR commands to restore backups to their original locations
              echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVJFFS} to /jffs${CClear}"
              tar -xzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVJFFS} -C /jffs >/dev/null
              if [ "$EXTLABEL" != "NOTFOUND" ]; then
                echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVUSB} to $EXTDRIVE${CClear}"
                tar -xzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVUSB} -C $EXTDRIVE >/dev/null
              else
                echo -e "${CYellow}WARNING: External USB drive not found. Skipping restore."
                logger "BACKUPMON WARNING: External USB drive not found. Skipping restore."
              fi
              echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVNVRAM} to NVRAM${CClear}"
              nvram restore ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVNVRAM} >/dev/null 2>&1
              echo ""
              echo -e "${CGreen}STATUS: Secondary backups were successfully restored to their original locations.  Forcing reboot now!${CClear}"
              echo ""
              /sbin/service 'reboot'
            fi
          fi

          # Unmount the backup drive
          echo ""
          echo ""
          echo -e "${CGreen}STATUS: Settling for 10 seconds..."
          sleep 10

          unmountsecondarydrv

          echo ""
          echo -e "${CClear}"
          exit 0

      else

          # Exit gracefully
          echo ""
          echo ""
          echo -e "${CGreen}STATUS: Settling for 10 seconds..."
          sleep 10

          unmountsecondarydrv

          echo -e "${CClear}"
          exit 0

        fi

    else

      # Exit gracefully
      echo ""
      echo ""
      echo -e "${CGreen}STATUS: Settling for 10 seconds..."
      sleep 10

      unmountsecondarydrv

      echo -e "${CClear}"
      exit 0

    fi

  fi

}

# -------------------------------------------------------------------------------------------------------------------------
# unmountdrv is a function to gracefully unmount the drive, and retry for up to 2 minutes
unmountdrv () {

  CNT=0
  TRIES=12
    while [ $CNT -lt $TRIES ]; do # Loop through number of tries
      umount -l $UNCDRIVE  # unmount the local drive from the UNC
      URC=$?
      if [ $URC -eq 0 ]; then  # If umount come back successful, then proceed
        echo -en "${CGreen}STATUS: External Drive ("; printf "%s" "${UNC}"; echo -e ") unmounted successfully.${CClear}"
        break
      else
        echo -e "${CYellow}WARNING: Unable to unmount from external drive. Trying every 10 seconds for 2 minutes."
        sleep 10
        CNT=$((CNT+1))
        if [ $CNT -eq $TRIES ];then
          echo -e "${CRed}ERROR: Unable to unmount from external drive. Please check your configuration. Exiting."
          logger "BACKUPMON ERROR: Unable to unmount from external drive. Please check your configuration!"
          exit 0
        fi
      fi
    done

}

# -------------------------------------------------------------------------------------------------------------------------
# unmountsecondarydrv is a function to gracefully unmount the secondary drive, and retry for up to 2 minutes
unmountsecondarydrv () {

  CNT=0
  TRIES=12
    while [ $CNT -lt $TRIES ]; do # Loop through number of tries
      umount -l $SECONDARYUNCDRIVE  # unmount the local drive from the Secondary UNC
      URC=$?
      if [ $URC -eq 0 ]; then  # If umount come back successful, then proceed
        echo -en "${CGreen}STATUS: Secondary External Drive ("; printf "%s" "${SECONDARYUNC}"; echo -e ") unmounted successfully.${CClear}"
        break
      else
        echo -e "${CYellow}WARNING: Unable to unmount from secondary external drive. Trying every 10 seconds for 2 minutes."
        sleep 10
        CNT=$((CNT+1))
        if [ $CNT -eq $TRIES ];then
          echo -e "${CRed}ERROR: Unable to unmount from secondary external drive. Please check your configuration. Exiting."
          logger "BACKUPMON ERROR: Unable to unmount from secondary external drive. Please check your configuration!"
          exit 0
        fi
      fi
    done

}

# -------------------------------------------------------------------------------------------------------------------------
# unmountdrv is a function to gracefully unmount the drive, and retry for up to 2 minutes
unmounttestdrv () {

  CNT=0
  TRIES=3
    while [ $CNT -lt $TRIES ]; do # Loop through number of tries
      umount -l $TESTUNCDRIVE  # unmount the local drive from the UNC
      URC=$?
      if [ $URC -eq 0 ]; then  # If umount come back successful, then proceed
        echo -en "${CGreen}STATUS: External Test Drive ("; printf "%s" "${TESTUNC}"; echo -e ") unmounted successfully.${CClear}"
        break
      else
        echo -e "${CYellow}WARNING: Unable to unmount from external test drive. Retrying...${CClear}"
        sleep 5
        CNT=$((CNT+1))
        if [ $CNT -eq $TRIES ];then
          echo -e "${CRed}ERROR: Unable to unmount from external drive. Please check your configuration. Exiting.${CClear}"
          read -rsp $'Press any key to acknowledge...\n' -n1 key
          break
        fi
      fi
    done
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

# Check for and add an alias for BACKUPMON
if ! grep -F "sh /jffs/scripts/backupmon.sh" /jffs/configs/profile.add >/dev/null 2>/dev/null; then
  echo "alias backupmon=\"sh /jffs/scripts/backupmon.sh\" # backupmon" >> /jffs/configs/profile.add
fi

# Check to see if EXT drive exists
if [ -z "$EXTLABEL" ]; then EXTLABEL="NOTFOUND"; fi

updatecheck

# Check and see if any commandline option is being used
if [ $# -eq 0 ]
  then
    clear
    sh /jffs/scripts/backupmon.sh -noswitch
    exit 0
fi

# Check and see if an invalid commandline option is being used
if [ "$1" == "-h" ] || [ "$1" == "-help" ] || [ "$1" == "-setup" ] || [ "$1" == "-backup" ] || [ "$1" == "-restore" ] || [ "$1" == "-noswitch" ] || [ "$1" == "-purge" ]
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
  echo " backupmon -purge"
  echo ""
  echo "  -h | -help (this output)"
  echo "  -setup (displays the setup menu)"
  echo "  -backup (runs the normal backup procedures)"
  echo "  -restore (initiates the restore procedures)"
  echo "  -purge (auto purges perpetual backup folders)"
  echo ""
  echo -e "${CClear}"
  exit 0
fi

# Check to see if the restore option is being called
if [ "$1" == "-restore" ]
  then

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

    restore
    echo -e "${CClear}"
    exit 0
fi

# Check to see if the setup option is being called
if [ "$1" == "-setup" ]
  then
    vsetup
fi

# Check to see if the purge option is being called
if [ "$1" == "-purge" ]
  then

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

    autopurge
    autopurgesecondaries
fi

# Check to see if the backup option is being called
if [ "$1" == "-backup" ]
  then

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

    BSWITCH="True"
fi

# Check to see if the backup option is being called
if [ "$1" == "-noswitch" ]
  then

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

    BSWITCH="False"
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

if [ $FREQUENCY == "W" ]; then FREQEXPANDED="Weekly"; fi
if [ $FREQUENCY == "M" ]; then FREQEXPANDED="Monthly"; fi
if [ $FREQUENCY == "Y" ]; then FREQEXPANDED="Yearly"; fi
if [ $FREQUENCY == "P" ]; then FREQEXPANDED="Perpetual"; fi
echo -en "${CCyan}Backing up to ${CGreen}"; printf "%s" "${UNC}"; echo -e "${CCyan} mounted to ${CGreen}${UNCDRIVE}"
echo -e "${CCyan}Backup directory location: ${CGreen}${BKDIR}"
echo -e "${CCyan}Frequency: ${CGreen}$FREQEXPANDED"
echo -e "${CCyan}Mode: ${CGreen}$MODE"
echo ""

# If the -backup switch is used then bypass the counter for immediate backup
if [ "$BSWITCH" == "False" ]; then
  # Run a 10sec timer
  i=0
  while [ $i -ne 10 ]
  do
      preparebar 51 "|"
      progressbaroverride $i 10 "" "s" "Standard"
      i=$(($i+1))
  done
fi

# Run a normal backup
echo -e "${CGreen}[Primary Backup Commencing]..."
echo ""
echo -e "${CCyan}Messages:"

backup
secondary

if [ $PURGE -eq 1 ] && [ "$BSWITCH" == "True" ]; then
  autopurge
fi

if [ $SECONDARYPURGE -eq 1 ] && [ "$BSWITCH" == "True" ]; then
  autopurgesecondaries
fi

BSWITCH="False"
echo -e "${CClear}"
exit 0

#} #2>&1 | tee $LOG | logger -t $(basename $0)[$$]  # uncomment/comment to enable/disable debug mode
