#!/bin/sh

# Original functional backup script by: @Jeffrey Young, August 9, 2023
# BACKUPMON v1.5.10 heavily modified and restore functionality added by @Viktor Jaep, 2023
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
Version="1.5.10"                                                # Current version
Beta=0                                                          # Beta release Y/N
CFGPATH="/jffs/addons/backupmon.d/backupmon.cfg"                # Path to the backupmon config file
DLVERPATH="/jffs/addons/backupmon.d/version.txt"                # Path to the backupmon version file
LOGFILE="/jffs/addons/backupmon.d/backupmon.log"                # Path to the local logfile
PFEXCLUSION="/jffs/addons/backupmon.d/pfexclusion.txt"          # Path to pagefile exclusion file
WDAY="$(date +%a)"                                              # Current day # of the week
MDAY="$(date +%d)"                                              # Current day # of the month
YDAY="$(date +%j)"                                              # Current day # of the year
EXTDRIVE="/tmp/mnt/$(nvram get usb_path_sda1_label)"            # Grabbing the default External USB Drive path
EXTLABEL="$(nvram get usb_path_sda1_label)"                     # Grabbing the default External USB Label name
UNCUPDATED="False"                                              # Tracking if the UNC was updated or not
SECONDARYUNCUPDATED="False"                                     # Tracking if the Secondary UNC was updated or not
UpdateNotify=0                                                  # Tracking whether a new update is available
BSWITCH="False"                                                 # Tracking -backup switch to eliminate timer
USBSOURCE="FALSE"                                               # Tracking switch
USBTARGET="FALSE"                                               # Tracking switch
SECONDARYUSBTARGET="FALSE"                                      # Tracking switch
TESTUSBTARGET="FALSE"                                           # Tracking switch

# Default Config variables
BTUSERNAME="admin"
BTPASSWORD="YWRtaW4K"
UNC="\\\\192.168.50.25\\Backups"
UNCDRIVE="/tmp/mnt/backups"
BKDIR="/router/GT-AX6000-Backup"
BACKUPMEDIA="Network"
EXCLUSION=""
BACKUPSWAP=0
SMBVER="2.1"
SCHEDULE=0
SCHEDULEHRS=2
SCHEDULEMIN=30
SCHEDULEMODE="BackupOnly"
FREQUENCY="M"
MODE="Basic"
PURGE=0
PURGELIMIT=0
AMTMEMAIL=0
AMTMEMAILSUCCESS=0
AMTMEMAILFAILURE=0
SECONDARYSTATUS=0
SECONDARYUSER="admin"
SECONDARYPWD="YWRtaW4K"
SECONDARYUNC="\\\\192.168.50.25\\SecondaryBackups"
SECONDARYUNCDRIVE="/tmp/mnt/secondarybackups"
SECONDARYBKDIR="/router/GT-AX6000-2ndBackup"
SECONDARYBACKUPMEDIA="Network"
SECONDARYEXCLUSION=""
SECONDARYFREQUENCY="M"
SECONDARYMODE="Basic"
SECONDARYPURGE=0
SECONDARYPURGELIMIT=0

#AMTM Email Notification Variables
readonly scriptFileName="${0##*/}"
readonly scriptFileNTag="${scriptFileName%.*}"
readonly CEM_LIB_TAG="master"
readonly CEM_LIB_URL="https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/${CEM_LIB_TAG}/EMail"
readonly CUSTOM_EMAIL_LIBDir="/jffs/addons/shared-libs"
readonly CUSTOM_EMAIL_LIBName="CustomEMailFunctions.lib.sh"
readonly CUSTOM_EMAIL_LIBFile="${CUSTOM_EMAIL_LIBDir}/$CUSTOM_EMAIL_LIBName"

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

#Preferred standard router binaries path
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:$PATH"

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
        * ) echo -e "\nPlease answer y or n.";;
      esac
  done
}

# -------------------------------------------------------------------------------------------------------------------------

# blackwhite is a simple function that removes all color attributes
blackwhite () {
# Color variables
CBlack=""
InvBlack=""
CRed=""
InvRed=""
CGreen=""
InvGreen=""
CDkGray=""
InvDkGray=""
InvLtGray=""
CYellow=""
InvYellow=""
CBlue=""
InvBlue=""
CMagenta=""
CCyan=""
InvCyan=""
CWhite=""
InvWhite=""
CClear=""

}

# -------------------------------------------------------------------------------------------------------------------------

# Preparebar and Progressbaroverride is a script that provides a nice progressbar to show script activity
preparebar () {
  # $1 - bar length
  # $2 - bar char
  barlen=$1
  barspaces=$(printf "%*s" "$1")
  barchars=$(printf "%*s" "$1" | tr ' ' "$2")
}

progressbaroverride () {

  insertspc=" "

  if [ $1 -eq -1 ]; then
    printf "\r  $barspaces\r"
  else
      barch=$(($1*barlen/$2))
      barsp=$((barlen-barch))
      progr=$((100*$1/$2))
  fi

    if [ ! -z $6 ]; then AltNum=$6; else AltNum=$1; fi

      printf "  ${CWhite}${InvDkGray}$AltNum${4} / ${progr}%%${CClear} ${CGreen}[ e=Exit / Selection? ${InvGreen} ${CClear}${CGreen}]\r${CClear}" "$barchars" "$barspaces"

    # Borrowed this wonderful keypress capturing mechanism from @Eibgrad... thank you! :)
    key_press=''; read -rsn1 -t 1 key_press < "$(tty 0>&2)"

    if [ $key_press ]; then
        case $key_press in
            [Xx]) echo ""; echo ""; sleep 1; restore;;
            [Ss]) (vsetup); source $CFGPATH; echo ""; sleep 1; exit 0;;
            [Ee])  # Exit gracefully
                  echo ""
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
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: A new update (v$DLVersion) is available to download" >> $LOGFILE
      else
        UpdateNotify=0
      fi
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# vlogs is a function that calls the nano text editor to view the BACKUPMON log file
vlogs () {

export TERM=linux
nano +999999 --linenumbers $LOGFILE

}

# -------------------------------------------------------------------------------------------------------------------------

# Trimlogs is a function that forces the logs down to a certain number of rows to give you some history
trimlogs () {

      CURRLOGSIZE=$(wc -l $LOGFILE | awk '{ print $1 }' ) # Determine the number of rows in the log

      if [ $CURRLOGSIZE -gt 5000 ] # If it's bigger than the max allowed, tail/trim it!
        then
          echo "$(tail -5000 $LOGFILE)" > $LOGFILE
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
  
    # Check for the Swap File Exclusion
    if [ "$BACKUPSWAP" == "0" ]; then
      excludeswap
    fi

    CHANGES=0 #track notification to save your changes

    while true; do
      clear
      logoNM     
      echo ""
      echo -e "${CGreen}----------------------------------------------------------------"
      echo -e "${CGreen}Primary Backup Configuration Options"
      echo -e "${CGreen}----------------------------------------------------------------"
      echo -e "${InvDkGray}${CWhite}    ${CClear}${CCyan}: Source Router Model                : "${CGreen}$ROUTERMODEL
      echo -e "${InvDkGray}${CWhite}    ${CClear}${CCyan}: Source Router Firmware/Build       : "${CGreen}$FWBUILD
      echo -e "${InvDkGray}${CWhite} 1  ${CClear}${CCyan}: Source EXT USB Drive Mount Point   : "${CGreen}$EXTDRIVE

      echo -e "${InvDkGray}${CWhite} 2  ${CClear}${CCyan}: Backup Target Media Type           : "${CGreen}$BACKUPMEDIA
      if [ "$BACKUPMEDIA" == "USB" ]; then
        echo -e "${InvDkGray}${CWhite} 3  ${CClear}${CDkGray}: Backup Target Username             : "${CDkGray}$BTUSERNAME
        echo -e "${InvDkGray}${CWhite} 4  ${CClear}${CDkGray}: Backup Target Password (ENC)       : "${CDkGray}$BTPASSWORD
        if [ "$UNCUPDATED" == "True" ]; then
          echo -en "${InvDkGray}${CWhite} 5  ${CClear}${CDkGray}: Backup Target UNC Path             : "${CDkGray};printf '%s' $UNC; printf "%s\n"
        else
          echo -en "${InvDkGray}${CWhite} 5  ${CClear}${CDkGray}: Backup Target UNC Path             : "${CDkGray}; echo $UNC | sed -e 's,\\,\\\\,g'
        fi
      else  
        echo -e "${InvDkGray}${CWhite} 3  ${CClear}${CCyan}: Backup Target Username             : "${CGreen}$BTUSERNAME
        echo -e "${InvDkGray}${CWhite} 4  ${CClear}${CCyan}: Backup Target Password (ENC)       : "${CGreen}$BTPASSWORD
        if [ "$UNCUPDATED" == "True" ]; then
          echo -en "${InvDkGray}${CWhite} 5  ${CClear}${CCyan}: Backup Target UNC Path             : "${CGreen};printf '%s' $UNC; printf "%s\n"
        else
          echo -en "${InvDkGray}${CWhite} 5  ${CClear}${CCyan}: Backup Target UNC Path             : "${CGreen}; echo $UNC | sed -e 's,\\,\\\\,g'
        fi
      fi
      
      if [ "$UNCDRIVE" == "" ] || [ -z "$UNCDRIVE" ]; then
        echo -e "${InvDkGray}${CWhite} 6  ${CClear}${CCyan}: Backup Target Mount Point          : ${CWhite}${InvRed}<-- Action Needed! ${CClear}"
      else
        echo -e "${InvDkGray}${CWhite} 6  ${CClear}${CCyan}: Backup Target Mount Point          : "${CGreen}$UNCDRIVE
      fi

      echo -e "${InvDkGray}${CWhite} 7  ${CClear}${CCyan}: Backup Target Directory Path       : "${CGreen}$BKDIR
      
      echo -e "${InvDkGray}${CWhite} 8  ${CClear}${CCyan}: Backup Exclusion File Name         : "${CGreen}$EXCLUSION

      echo -en "${InvDkGray}${CWhite} 9  ${CClear}${CCyan}: Backup Swap File                   : ${CGreen}"
        if [ "$BACKUPSWAP" == "0" ]; then
          printf "No"; printf "%s\n";
        elif [ "$BACKUPSWAP" == "1" ]; then
          printf "Yes"; printf "%s\n";fi

      echo -e "${InvDkGray}${CWhite} 10 ${CClear}${CCyan}: Backup CIFS/SMB Version            : "${CGreen}$SMBVER

      echo -en "${InvDkGray}${CWhite} 11 ${CClear}${CCyan}: Backup Frequency?                  : ${CGreen}"
      if [ "$FREQUENCY" == "W" ]; then
        printf "Weekly"; printf "%s\n";
      elif [ "$FREQUENCY" == "M" ]; then
        printf "Monthly"; printf "%s\n";
      elif [ "$FREQUENCY" == "Y" ]; then
        printf "Yearly"; printf "%s\n";
      elif [ "$FREQUENCY" == "P" ]; then
        printf "Perpetual"; printf "%s\n"; fi
      if [ "$FREQUENCY" == "P" ]; then
        echo -en "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Purge Backups?                    : ${CGreen}"
        if [ "$PURGE" == "0" ]; then
          printf "No"; printf "%s\n";
        elif [ "$PURGE" == "1" ]; then
          printf "Yes"; printf "%s\n";fi
        echo -en "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Purge older than (days):          : ${CGreen}"
        if [ "$PURGELIMIT" == "0" ]; then
          printf "N/A"; printf "%s\n";
        else
          printf $PURGELIMIT; printf "%s\n";
        fi
      else
        echo -e "${InvDkGray}${CWhite} |--${CClear}${CDkGray}-  Purge Backups?                    : ${CDkGray}No"
        echo -e "${InvDkGray}${CWhite} |  ${CClear}${CDkGray}-  Purge older than (days):          : ${CDkGray}N/A"
      fi

      echo -e "${InvDkGray}${CWhite} 12 ${CClear}${CCyan}: Backup/Restore Mode                : "${CGreen}$MODE

      echo -en "${InvDkGray}${CWhite} 13 ${CClear}${CCyan}: Schedule Backups?                  : ${CGreen}"
      if [ "$SCHEDULE" == "0" ]; then
        printf "No"; printf "%s\n";
      else printf "Yes"; printf "%s\n"; fi
      if [ "$SCHEDULE" == "1" ]; then
        echo -e "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Time:                             : ${CGreen}$SCHEDULEHRS:$SCHEDULEMIN"
        echo -en "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Scheduled Backup Mode             : ${CGreen}"
        if [ "$SCHEDULEMODE" == "BackupOnly" ]; then
          printf "Backup Only"; printf "%s\n";
        elif [ "$SCHEDULEMODE" == "BackupAutoPurge" ]; then
          printf "Backup + Autopurge"; printf "%s\n"; fi
      else
        echo -e "${InvDkGray}${CWhite} |  ${CClear}${CDkGray}-  Time:                             : ${CDkGray}$SCHEDULEHRS:$SCHEDULEMIN"
        echo -en "${InvDkGray}${CWhite} |--${CClear}${CDkGray}-  Scheduled Backup Mode             : ${CDkGray}"
        if [ "$SCHEDULEMODE" == "BackupOnly" ]; then
          printf "Backup Only"; printf "%s\n";
        elif [ "$SCHEDULEMODE" == "BackupAutoPurge" ]; then
          printf "Backup + Autopurge"; printf "%s\n"; fi
      fi

      echo -en "${InvDkGray}${CWhite} 14 ${CClear}${CCyan}: AMTM Email Notifications?          : ${CGreen}"
      if [ "$AMTMEMAIL" == "0" ]; then
        printf "No"; printf "%s\n";
      else printf "Yes"; printf "%s\n"; fi
      if [ "$AMTMEMAILSUCCESS" == "1" ]; then
        echo -e "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  On Success?                       : ${CGreen}Yes"
      else
        echo -e "${InvDkGray}${CWhite} |  ${CClear}${CDkGray}-  On Success?                       : ${CDkGray}No"
      fi
      if [ "$AMTMEMAILFAILURE" == "1" ]; then
        echo -e "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  On Failure?                       : ${CGreen}Yes"
      else
        echo -e "${InvDkGray}${CWhite} |  ${CClear}${CDkGray}-  On Failure?                       : ${CDkGray}No"
      fi

      echo -en "${InvDkGray}${CWhite} 15 ${CClear}${CCyan}: Secondary Backup Config Options    : "${CGreen}$SECONDARY
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
              echo -e "${CCyan}1. Please choose the SOURCE Mount Point of your attached external USB Drive that"
              echo -e "${CCyan}contains data that you want to have backed up. In most cases, whatever is"
              echo -e "${CCyan}attached to your sda1 partition should be selected. Should there be only one"
              echo -e "${CCyan}mount point available, it will be automatically selected."
              printf "${CYellow}Recommended Mount Point = ${CClear}"
              _GetDefaultUSBMountPoint_
              USBSOURCE="TRUE"
              _GetMountPoint_ "Select an EXT USB Drive Mount Point: "
              read -rsp $'Press any key to acknowledge...\n' -n1 key
              checkusbexclusion
            ;;

            2) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}2. What is the TARGET Backup Media Type? This is the type of device that you"
              echo -e "${CCyan}want your backups copied to. Please indicate whether the media is a network"
              echo -e "${CCyan}device (accessible via UNC path), or a local USB device (connected to router)."
              echo -e "${CCyan}PLEASE NOTE: If the USB option is chosen, there will be no need to complete"
              echo -e "${CCyan}further information for the Target UNC, username or password, and will be"
              echo -e "${CCyan}grayed out." 
              echo -e "${CYellow}(Network=1, USB=2) (Default = 1)"
              echo -e "${CClear}"
              while true; do
                read -p 'Media Type (1/2)?: ' BACKUPMEDIA
                  case $BACKUPMEDIA in
                    [1] ) BACKUPMEDIA="Network"; break ;;
                    [2] ) BACKUPMEDIA="USB"; break ;;
                    "" ) echo -e "\nError: Please use either 1 or 2\n";;
                    * ) echo -e "\nError: Please use either 1 or 2\n";;
                  esac                  
              done
              
              if [ "$BACKUPMEDIA" == "Network" ] && [ "$EXTDRIVE" == "$UNCDRIVE" ]; then
                UNCDRIVE=""
              fi
              
              if [ "$BACKUPMEDIA" == "USB" ] && [ "$EXTDRIVE" != "$UNCDRIVE" ]; then
                UNCDRIVE=""
              fi
              
            ;;      

            3) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}3. What is the TARGET Network Backup Username?"
              echo -e "${CYellow}(Default = admin)"
              echo -e "${CClear}"
              read -p 'Username: ' BTUSERNAME1
              if [ "$BTUSERNAME1" == "" ] || [ -z "$BTUSERNAME1" ]; then BTUSERNAME="admin"; else BTUSERNAME="$BTUSERNAME1"; fi # Using default value on enter keypress
            ;;

            4) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}4. What is the TARGET Network Backup Password?"
              echo -e "${CYellow}(Default = admin)"
              echo -e "${CClear}"
              if [ $BTPASSWORD == "admin" ]; then
                echo -e "${CGreen}Old Password (Unencoded): admin"
              else
                echo -en "${CGreen}Old Password (Unencoded): "; echo "$BTPASSWORD" | openssl enc -d -base64 -A
              fi
              echo ""
              read -rp 'New Password: ' BTPASSWORD1
              if [ "$BTPASSWORD1" == "" ] || [ -z "$BTPASSWORD1" ]; then BTPASSWORD=`echo "admin" | openssl enc -base64 -A`; else BTPASSWORD=`echo $BTPASSWORD1 | openssl enc -base64 -A`; fi # Using default value on enter keypress
            ;;

            5) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}5. What is the TARGET Backup UNC Path? This is the path of a local network"
              echo -e "${CCyan}backup device that has a share made available for backups to be pushed to."
              echo -e "${CCyan}Please note: Use proper notation for the network path by starting with"
              echo -en "${CCyan}4 backslashes "; printf "%s" "(\\\\\\\\)"; echo -en " and using 2 backslashes "; printf "%s" "(\\\\)"; echo -e " between any additional"
              echo -e "${CCyan}folders. Example below:"
              echo -en "${CYellow}"; printf "%s" "(Default = \\\\\\\\192.168.50.25\\\\Backups)"
              echo -e "${CClear}"
              read -rp 'Target Backup UNC Path: ' UNC1
              if [ "$UNC1" == "" ] || [ -z "$UNC1" ]; then UNC="\\\\\\\\192.168.50.25\\\\Backups"; else UNC="$UNC1"; fi # Using default value on enter keypress
              UNCUPDATED="True"
            ;;

            6) # -----------------------------------------------------------------------------------------
              
              if [ "$BACKUPMEDIA" == "Network" ]; then
                echo ""
                echo -e "${CCyan}6. What would you like to name the TARGET Network Backup Drive Mount Point? This"
                echo -e "${CCyan}mount path will be created for you, and is the local path on your router"
                echo -e "${CCyan}typically located under /tmp/mnt which provides a physical directory that is"
                echo -e "${CCyan}mounted to the network backup location. Please note: Use proper notation for the"
                echo -e "${CCyan}path by using single forward slashes between directories. Example below:"
                echo -e "${CYellow}(Default = /tmp/mnt/backups)"
                echo -e "${CClear}"
                read -p 'Target Network Backup Drive Mount Point: ' UNCDRIVE1
                if [ "$UNCDRIVE1" == "" ] || [ -z "$UNCDRIVE1" ]; then UNCDRIVE="/tmp/mnt/backups"; else UNCDRIVE="$UNCDRIVE1"; fi # Using default value on enter keypress
                if [ "$EXTDRIVE" == "$UNCDRIVE" ]; then
                  UNCDRIVE=""
                  echo ""
                  echo -e "${CYellow} WARNING: Your TARGET Network Backup Drive Mount Point cannot be named the"
                  echo -e "${CYellow} same as your SOURCE External USB Drive Mount. Please choose a mount point"
                  echo -e "${CYellow} name that is unique for this network target.${CClear}\n"
                  read -rsp $'Press any key to acknowledge...\n' -n1 key
                fi
                
              elif [ "$BACKUPMEDIA" == "USB" ]; then
                echo ""
                echo -e "${CCyan}6. Please choose the TARGET USB Backup Drive Mount Point assigned to your external"
                echo -e "${CCyan}USB Drive where you want backups to be stored. Should there be only one drive"
                echo -e "${CCyan}available, it will be automatically selected. PLEASE NOTE: It is highly recommended"
                echo -e "${CCyan}not to use the same USB drive to both be a SOURCE and TARGET for backups.${CClear}"
                USBTARGET="TRUE"
                _GetMountPoint_ "Select a Target USB Backup Drive Mount Point: "
                read -rsp $'Press any key to acknowledge...\n' -n1 key
                checkusbexclusion
              fi
            ;;

            7) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}7. What is the TARGET Backup Directory Path? This is the path that is created"
              echo -e "${CCyan}on your network backup location in order to store and order the backups by day."
              echo -e "${CCyan}Please note: Use proper notation for the path by using single forward slashes"
              echo -e "${CCyan}between directories. Example below:"
              echo -e "${CYellow}(Default = /router/GT-AX6000-Backup)"
              echo -e "${CClear}"
              read -p 'Target Backup Directory Path: ' BKDIR1
              if [ "$BKDIR1" == "" ] || [ -z "$BKDIR1" ]; then BKDIR="/router/GT-AX6000-Backup"; else BKDIR="$BKDIR1"; fi # Using default value on enter keypress
              checkusbexclusion
            ;;

            8) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}8. Would you like to use a Backup Exclusion File Name? This file contains a"
              echo -e "${CCyan}list of certain files that you want to exclude from the backup, such as your"
              echo -e "${CCyan}swap file."
              echo ""
              echo -e "${CYellow}WARNING: If you do not use an Exclusion file with the necessary entries to"
              echo -e "${CYellow}exlude your swap file (or others), your backup size and time it takes to"
              echo -e "${CYellow}complete the backup will increase greatly. Examples of what to include in"
              echo -e "${CYellow}the exlusions.txt file below entered in a simple list format:"
              echo ""
              echo -e "${CYellow}myswap.swp"
              echo -e "${CYellow}entware/var/log/*"
              echo -e "${CYellow}skynet/skynet.log"
              echo ""
              echo -e "${CCyan}Please note: Use proper notation for the path to this file by using single"
              echo -e "${CCyan}forward slashes between directories. Example below:"
              echo -e "${CYellow}(Example = /jffs/addons/backupmon.d/exclusions.txt) (Default = Leave Blank)"
              echo -e "${CClear}"
              read -p 'Backup Exclusion Path + File Name: ' EXCLUSION1
              if [ "$EXCLUSION1" == "" ] || [ -z "$EXCLUSION1" ]; then EXCLUSION=""; else EXCLUSION="$EXCLUSION1"; fi # Using default value on enter keypress
              if [ "$BACKUPSWAP" == "0" ] && [ "$EXCLUSION" == "" ]; then EXCLUSION="$PFEXCLUSION"; fi
            ;;

            9) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}9. Would you like to back up your Swap File? This file usually ranges in the"
              echo -e "${CCyan}1GB, 2GB or 4GB range. It is not a file that is required to be backed up, and"
              echo -e "${CCyan}may cause issues when restoring backups. Due to the size, it will also"
              echo -e "${CCyan}substantially increase backup target size and time it takes to run backups."
              echo -e "${CYellow}NOTE: It is highly recommended to leave this disabled."
              echo ""
              echo -e "${CYellow}(No=0, Yes=1) (Default = 0)"
              echo -e "${CClear}"
              read -p 'Backup Swap? (0/1): ' SWAP1
              if [ "$SWAP1" == "" ] || [ -z "$SWAP1" ]; then BACKUPSWAP=0; else BACKUPSWAP="$SWAP1"; fi # Using default value on enter keypress
              
              if [ "$BACKUPSWAP" == "1" ]; then
                swapname=$(cat /proc/swaps | awk 'NR==2 {print $1}' | sed 's|.*/||') >/dev/null 2>&1 
                sed -i -e '/'$swapname'/d' $EXCLUSION >/dev/null 2>&1
                sed -i -e '/'$swapname'/d' $SECONDARYEXCLUSION >/dev/null 2>&1
              fi
            ;;

            10) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}10. What version of the CIFS/SMB protocol would you like to use? This protocol"
              echo -e "${CCyan}is used by BACKUPMON to connect to other network devices in order to transfer"
              echo -e "${CCyan}files and backups from source to target. While BACKUPMON supports the latest"
              echo -e "${CCyan}SMB protocol available (v3.02), you can choose older versions for backwards"
              echo -e "${CCyan}compatibility purposes, for example, if the target hardware is not able to"
              echo -e "${CCyan}support a more recent version."
               echo -e "${CYellow}(v2.1=1, v2.0=2, v1.0=3, v3.0=4, v3.02=5) (Default = 1)"
              echo -e "${CClear}"
              while true; do
                read -p 'CIFS/SMB Version (1/2/3/4/5)?: ' SMBVER
                  case $SMBVER in
                    [1] ) SMBVER="2.1"; break ;;
                    [2] ) SMBVER="2.0"; break ;;
                    [3] ) SMBVER="1.0"; break ;;
                    [4] ) SMBVER="3.0"; break ;;
                    [5] ) SMBVER="3.02"; break ;;
                    "" ) echo -e "\nError: Please use either 1, 2, 3, 4 or 5\n";;
                    * ) echo -e "\nError: Please use either 1, 2, 3, 4 or 5\n";;
                  esac
              done
            ;;      


            11) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}11. What backup frequency would you like BACKUPMON to run daily backup jobs each"
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
              echo -e "${CYellow}(Weekly=W, Monthly=M, Yearly=Y, Perpetual=P) (Default = M)"
              echo -e "${CClear}"
              while true; do
                read -p 'Frequency (W/M/Y/P)?: ' FREQUENCY
                  case $FREQUENCY in
                    [Ww] ) FREQUENCY="W"; PURGE=0; PURGELIMIT=0; break ;;
                    [Mm] ) FREQUENCY="M"; PURGE=0; PURGELIMIT=0; break ;;
                    [Yy] ) FREQUENCY="Y"; PURGE=0; PURGELIMIT=0; break ;;
                    [Pp] ) FREQUENCY="P"; MODE="Basic" break ;;
                    "" ) echo -e "\nError: Please use either M, W, Y or P\n";;
                    * ) echo -e "\nError: Please use either M, W, Y or P\n";;
                  esac
              done

              if [ $FREQUENCY == "P" ]; then
                echo ""
                echo -e "${CCyan}11a. Would you like to purge perpetual backups after a certain age? This can help"
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
                echo -e "${CYellow}(No=0, Yes=1) (Default = 0)"
                echo -e "${CClear}"
                read -p 'Purge Backups? (0/1): ' PURGE1
                if [ "$PURGE1" == "" ] || [ -z "$PURGE1" ]; then PURGE=0; else PURGE="$PURGE1"; fi # Using default value on enter keypress
                
                if [ "$PURGE" == "0" ]; then
                  PURGELIMIT=0
                elif [ "$PURGE" == "1" ]; then

                  echo ""
                  echo -e "${CCyan}11b. How many days would you like to keep your perpetual backups? Example: 90"
                  echo -e "${CCyan}Note that all perpetual backups older than 90 days would be permanently deleted."
                  echo ""
                  echo -e "${CCyan}PLEASE NOTE: If there are any backups you wish to save permanently, please move"
                  echo -e "${CCyan}these to a SAFE, separate folder that BACKUPMON does not interact with."
                  echo ""
                  echo -e "${CYellow}(Default = 90)"
                  echo -e "${CClear}"
                  read -p 'Backup Age? (in days): ' PURGELIMIT1
                  if [ "$PURGELIMIT1" == "" ] || [ -z "$PURGELIMIT1" ]; then PURGELIMIT=0; else PURGELIMIT="$PURGELIMIT1"; fi # Using default value on enter keypress

                else
                  PURGE=0
                  PURGELIMIT=0
                fi
              fi

            ;;

            12) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}12. What mode of operation would you like BACKUPMON to run in? You have 2 different"
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
              echo -e "${CYellow}(Basic-0, Advanced=1) (Default = 0)"
              echo -e "${CClear}"
              while true; do
                read -p 'Mode (0/1)?: ' MODE1
                  case $MODE1 in
                    [0] ) MODE="Basic"; break ;;
                    [1] ) if [ $FREQUENCY == "P" ]; then MODE="Basic"; else MODE="Advanced"; fi; break ;;
                    "" ) echo -e "\nError: Please use either 0 or 1\n";;
                    * ) echo -e "\nError: Please use either 0 or 1\n";;
                  esac
              done
            ;;

            13) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}13. Would you like BACKUPMON to automatically run at a scheduled time each day?"
              echo -e "${CCyan}Please note: This will place a cru command into your 'services-start' file that"
              echo -e "${CCyan}is located under your /jffs/scripts folder. Each time your router reboots, this"
              echo -e "${CCyan}command will automatically be added as a CRON job to run your backup."
              echo -e "${CYellow}(No=0, Yes=1) (Default = 0)"
              echo -e "${CClear}"
              read -p 'Schedule BACKUPMON?: ' SCHEDULE1
              if [ "$SCHEDULE1" == "" ] || [ -z "$SCHEDULE1" ]; then SCHEDULE=0; else SCHEDULE="$SCHEDULE1"; fi # Using default value on enter keypress

              if [ "$SCHEDULE" == "0" ]; then

                if [ -f /jffs/scripts/services-start ]; then
                  sed -i -e '/backupmon.sh/d' /jffs/scripts/services-start
                  cru d RunBackupMon
                fi

              elif [ "$SCHEDULE" == "1" ]; then

                echo ""
                echo -e "${CCyan}12a. What time would you like BACKUPMON to automatically run each day? Please"
                echo -e "${CCyan}note: You will be asked for the hours and minutes in separate prompts. Use 24hr"
                echo -e "${CCyan}format for the hours. (Ex: 17 hrs / 15 min = 17:15 or 5:15pm)"
                echo -e "${CYellow}(Default = 2 hrs / 30 min = 02:30 or 2:30am)"
                echo -e "${CClear}"
                read -p 'Schedule HOURS?: ' SCHEDULEHRS1
                if [ "$SCHEDULEHRS1" == "" ] || [ -z "$SCHEDULEHRS1" ]; then SCHEDULEHRS=2; else SCHEDULEHRS="$SCHEDULEHRS1"; fi # Using default value on enter keypress
                read -p 'Schedule MINUTES?: ' SCHEDULEMIN1
                if [ "$SCHEDULEMIN1" == "" ] || [ -z "$SCHEDULEMIN1" ]; then SCHEDULEMIN=30; else SCHEDULEMIN="$SCHEDULEMIN1"; fi # Using default value on enter keypress
                
                if [ "$FREQUENCY" == "P" ]; then
                  echo ""
                  echo -e "${CCyan}12b. When running a scheduled job each day, would you like BACKUPMON to only run"
                  echo -e "${CCyan}backups, or would you like it to run backups and have it automatically purge"
                  echo -e "${CCyan}old backups outside your specified age range immediately following? If you don't"
                  echo -e "${CCyan}want to run backups with autopurge, you will be responsible for manually running"
                  echo -e "${CCyan}backup purges using the config menu, or manually from the file system itself."
                  echo -e "${CCyan}Please note: This option is only available when having the Perpetual Backup"
                  echo -e "${CCyan}Frequency selected."
                  echo -e "${CYellow}(Backups Only=1, Backups+Autopurge=2) (Default = 1)"
                  echo -e "${CClear}"
                  while true; do
                    read -p 'Backup/Purge Functionality (1/2)?: ' SCHEDULEMODE
                      case $SCHEDULEMODE in
                        [1] ) SCHEDULEMODE="BackupOnly"; break ;;
                        [2] ) SCHEDULEMODE="BackupAutoPurge"; break ;;
                        "" ) echo -e "\nError: Please use either 1 or 2\n";;
                        * ) echo -e "\nError: Please use either 1 or 2\n";;
                      esac
                  done
                fi

                if [ "$SCHEDULEMODE" == "BackupOnly" ]; then
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
                  
                echo ""
                echo -e "${CGreen}[Modifiying SERVICES-START file]..."
                sleep 2
                echo -e "[Modifying CRON jobs]..."
                sleep 2
                
                elif [ "$SCHEDULEMODE" == "BackupAutoPurge" ]; then
                  if [ -f /jffs/scripts/services-start ]; then

                    if ! grep -q -F "sh /jffs/scripts/backupmon.sh" /jffs/scripts/services-start; then
                      echo 'cru a RunBackupMon "'"$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh -backup"'"' >> /jffs/scripts/services-start
                      cru a RunBackupMon "$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh -backup"
                    else
                      #delete and re-add if it already exists in case there's a time change
                      sed -i -e '/backupmon.sh/d' /jffs/scripts/services-start
                      cru d RunBackupMon
                      echo 'cru a RunBackupMon "'"$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh -backup"'"' >> /jffs/scripts/services-start
                      cru a RunBackupMon "$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh -backup"
                    fi

                  else
                    echo 'cru a RunBackupMon "'"$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh -backup"'"' >> /jffs/scripts/services-start
                    chmod 755 /jffs/scripts/services-start
                    cru a RunBackupMon "$SCHEDULEMIN $SCHEDULEHRS * * * sh /jffs/scripts/backupmon.sh -backup"
                  fi
                
                echo ""
                echo -e "${CGreen}[Modifiying SERVICES-START file]..."
                sleep 2
                echo -e "[Modifying CRON jobs]..."
                sleep 2
                
                fi  

              else
                SCHEDULE=0
                SCHEDULEHRS=2
                SCHEDULEMIN=30
              fi
            ;;
            
            14) # -----------------------------------------------------------------------------------------
              echo ""
              echo -e "${CCyan}14. Would you like BACKUPMON to send you email notifications on backup success"
              echo -e "${CCyan}or failure, or both? Please note: This does require that AMTM email has been"
              echo -e "${CCyan}set up successfully under AMTM -> em (email settings). Once you are able to"
              echo -e "${CCyan}send and receive test emails, you may utilize this functionality in BACKUPMON."
              echo -e "${CCyan}Additionally, this functionality will download an AMTM email interface library"
              echo -e "${CCyan}courtesy of @Martinski, and will be located under a new common library folder"
              echo -e "${CCyan}called: /jffs/addons/shared-libs."
              echo -e "${CYellow}(No=0, Yes=1) (Default = 0)"
              echo -e "${CClear}"
              read -p 'Enable BACKUPMON Email Notifications? (0/1): ' AMTMEMAIL1
              if [ "$AMTMEMAIL1" == "" ] || [ -z "$AMTMEMAIL1" ]; then AMTMEMAIL=0; else AMTMEMAIL="$AMTMEMAIL1"; fi # Using default value on enter keypress

              if [ "$AMTMEMAIL" == "1" ]; then
                
                if [ -f "$CUSTOM_EMAIL_LIBFile" ]
                then
                  . "$CUSTOM_EMAIL_LIBFile"

                  if [ -z "${CEM_LIB_VERSION:+xSETx}" ] || \
                    _CheckLibraryUpdates_CEM_ "$CUSTOM_EMAIL_LIBDir" quiet
                  then
                    _DownloadCEMLibraryFile_ "update"
                  fi
                else
                    _DownloadCEMLibraryFile_ "install"
                fi
                
                echo ""
                read -p 'Email on Successful Backups? (No=0, Yes=1): ' AMTMEMAILSUCCESS1
                if [ "$AMTMEMAILSUCCESS1" == "" ] || [ -z "$AMTMEMAILSUCCESS1" ]; then AMTMEMAILSUCCESS=0; else AMTMEMAILSUCCESS="$AMTMEMAILSUCCESS1"; fi # Using default value on enter keypress
                echo ""
                read -p 'Email on Backup Failures? (No=0, Yes=1): ' AMTMEMAILFAILURE1
                if [ "$AMTMEMAILFAILURE1" == "" ] || [ -z "$AMTMEMAILFAILURE1" ]; then AMTMEMAILFAILURE=0; else AMTMEMAILFAILURE="$AMTMEMAILFAILURE1"; fi # Using default value on enter keypress
                echo ""
                echo -e "Would you like to send a TEST email from BACKUPMON?"
                if promptyn "(y/n): "; then

                  echo ""
                  cemIsFormatHTML=true
                  cemIsVerboseMode=true  ## true OR false ##
                  emailBodyTitle="Testing Email Notification"
                  emailSubject="TEST: BACKUPMON Email Notification"
                  tmpEMailBodyFile="/tmp/var/tmp/tmpEMailBody_${scriptFileNTag}.$$.TXT"

                  {
                  printf "This is a <b>TEST</b> to check & verify if sending email notifications is working well from <b>BACKUPMON</b>.\n"
                  } > "$tmpEMailBodyFile"

                  _SendEMailNotification_ "BACKUPMON v$Version" "$emailSubject" "$tmpEMailBodyFile" "$emailBodyTitle"
                  
                  echo ""
                  read -rsp $'Press any key to acknowledge...\n' -n1 key
                
                fi
                
                #If notifications are off, turn off AMTM Email functionality
                if [ "$AMTMEMAILSUCCESS" == "0" ] && [ "$AMTMEMAILFAILURE" == "0" ]; then
                  AMTMEMAIL=0
                fi
                
               else
                AMTMEMAIL=0
                AMTMEMAILSUCCESS=0
                AMTMEMAILFAILURE=0
              fi
              
            ;;
            
            15) # -----------------------------------------------------------------------------------------
            while true; do
              clear
              logoNM     
              echo ""
              echo -e "${CGreen}----------------------------------------------------------------"
              echo -e "${CGreen}Secondary Backup Configuration Options"
              echo -e "${CGreen}----------------------------------------------------------------"
              echo -en "${InvDkGray}${CWhite} 1  ${CClear}${CCyan}: Enabled/Disabled                   : ${CGreen}"
              if [ "$SECONDARYSTATUS" != "0" ] && [ "$SECONDARYSTATUS" != "1" ]; then SECONDARYSTATUS=0; fi
              if [ "$SECONDARYSTATUS" == "0" ]; then
                printf "Disabled"; printf "%s\n";
              else printf "Enabled"; printf "%s\n"; fi
              echo -e "${InvDkGray}${CWhite} 2  ${CClear}${CCyan}: Secondary Target Media Type        : ${CGreen}$SECONDARYBACKUPMEDIA"             
              if [ "$SECONDARYBACKUPMEDIA" == "USB" ]; then
                if [ -z "$SECONDARYUSER" ]; then SECONDARYUSER="admin"; fi
                echo -e "${InvDkGray}${CWhite} 3  ${CClear}${CDkGray}: Secondary Target Username          : ${CDkGray}$SECONDARYUSER"
                if [ -z "$SECONDARYPWD" ]; then SECONDARYPWD="YWRtaW4K"; fi
                echo -e "${InvDkGray}${CWhite} 4  ${CClear}${CDkGray}: Secondary Target Password (ENC)    : ${CDkGray}$SECONDARYPWD"
                if [ -z "$SECONDARYUNC" ]; then SECONDARYUNC="\\\\192.168.50.25\\Backups"; fi
                if [ "$SECONDARYUNCUPDATED" == "True" ]; then
                  echo -en "${InvDkGray}${CWhite} 5  ${CClear}${CDkGray}: Secondary Target UNC Path          : ${CDkGray}"; printf '%s' $SECONDARYUNC; printf "%s\n"
                else
                  echo -en "${InvDkGray}${CWhite} 5  ${CClear}${CDkGray}: Secondary Target UNC Path          : ${CDkGray}"; echo $SECONDARYUNC | sed -e 's,\\,\\\\,g'
                fi
              else
                if [ -z "$SECONDARYUSER" ]; then SECONDARYUSER="admin"; fi
                echo -e "${InvDkGray}${CWhite} 3  ${CClear}${CCyan}: Secondary Target Username          : ${CGreen}$SECONDARYUSER"
                if [ -z "$SECONDARYPWD" ]; then SECONDARYPWD="YWRtaW4K"; fi
                echo -e "${InvDkGray}${CWhite} 4  ${CClear}${CCyan}: Secondary Target Password (ENC)    : ${CGreen}$SECONDARYPWD"
                if [ -z "$SECONDARYUNC" ]; then SECONDARYUNC="\\\\192.168.50.25\\Backups"; fi
                if [ "$SECONDARYUNCUPDATED" == "True" ]; then
                  echo -en "${InvDkGray}${CWhite} 5  ${CClear}${CCyan}: Secondary Target UNC Path          : ${CGreen}"; printf '%s' $SECONDARYUNC; printf "%s\n"
                else
                  echo -en "${InvDkGray}${CWhite} 5  ${CClear}${CCyan}: Secondary Target UNC Path          : ${CGreen}"; echo $SECONDARYUNC | sed -e 's,\\,\\\\,g'
                fi
              fi
              if [ "$SECONDARYUNCDRIVE" == "" ] || [ -z "$SECONDARYUNCDRIVE" ]; then
                echo -e "${InvDkGray}${CWhite} 6  ${CClear}${CCyan}: Secondary Target Drive Mount Point : ${CWhite}${InvRed}<-- Action Needed! ${CClear}"
              else
                echo -e "${InvDkGray}${CWhite} 6  ${CClear}${CCyan}: Secondary Target Drive Mount Point : ${CGreen}$SECONDARYUNCDRIVE"
              fi
              if [ -z "$SECONDARYBKDIR" ]; then SECONDARYBKDIR="/router/GT-AX6000-Backup"; fi
              echo -e "${InvDkGray}${CWhite} 7  ${CClear}${CCyan}: Secondary Target Directory Path    : ${CGreen}$SECONDARYBKDIR"
              echo -e "${InvDkGray}${CWhite} 8  ${CClear}${CCyan}: Exclusion File Name                : ${CGreen}$SECONDARYEXCLUSION"
              echo -en "${InvDkGray}${CWhite} 9  ${CClear}${CCyan}: Backup Frequency?                  : ${CGreen}"
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
                echo -en "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Purge Secondary Backups?          : ${CGreen}"
                if [ "$SECONDARYPURGE" == "0" ]; then
                  printf "No"; printf "%s\n";
                else printf "Yes"; printf "%s\n"; fi
              else
                echo -en "${InvDkGray}${CWhite} |--${CClear}${CDkGray}-  Purge Secondary Backups?          : ${CDkGray}"
                if [ "$SECONDARYPURGE" == "0" ]; then
                  printf "No"; printf "%s\n";
                else printf "Yes"; printf "%s\n"; fi
              fi
              if [ -z $SECONDARYPURGELIMIT ]; then SECONDARYPURGELIMIT=0; fi
              if [ "$SECONDARYFREQUENCY" == "P" ] && [ "$SECONDARYPURGE" == "1" ]; then
                echo -e "${InvDkGray}${CWhite} |--${CClear}${CCyan}-  Purge Older Than (days)           : ${CGreen}$SECONDARYPURGELIMIT"
              else
                echo -e "${InvDkGray}${CWhite} |--${CClear}${CDkGray}-  Purge Older Than (days)           : ${CDkGray}$SECONDARYPURGELIMIT"
              fi
              if [ -z "$SECONDARYMODE" ]; then SECONDARYMODE="Basic"; fi
              echo -e "${InvDkGray}${CWhite} 10 ${CClear}${CCyan}: Backup/Restore Mode                : ${CGreen}$SECONDARYMODE"
              echo -e "${InvDkGray}${CWhite} |  ${CClear}"
              echo -e "${InvDkGray}${CWhite} e  ${CClear}${CCyan}: Exit Back to Primary Backup Config"
              echo -e "${CGreen}----------------------------------------------------------------"
              echo ""
              printf "Selection: ${CClear}"
              read -r SECONDARYINPUT
                  case $SECONDARYINPUT in
                    1 ) echo ""; read -p 'Secondary Backup Enabled=1, Disabled=0 (0/1?): ' SECONDARYSTATUS;;
                    2 ) echo ""; read -p 'Secondary Target Backup Media (Network=1, USB=2): ' SECONDARYBACKUPMEDIA; if [ "$SECONDARYBACKUPMEDIA" == "1" ]; then SECONDARYBACKUPMEDIA="Network"; SECONDARYUNCDRIVE=""; elif [ "$SECONDARYBACKUPMEDIA" == "2" ]; then SECONDARYBACKUPMEDIA="USB"; SECONDARYUNCDRIVE=""; else SECONDARYBACKUPMEDIA="Network"; fi;;
                    3 ) echo ""; read -p 'Secondary Username: ' SECONDARYUSER;;
                    4 ) echo ""; if [ "$SECONDARYPWD" == "admin" ]; then echo -e "Old Secondary Password (Unencoded): admin"; else echo -en "Old Secondary Password (Unencoded): "; echo $SECONDARYPWD | openssl enc -d -base64 -A; fi; echo ""; read -rp 'New Secondary Password: ' SECONDARYPWD1; if [ "$SECONDARYPWD1" == "" ] || [ -z "$SECONDARYPWD1" ]; then SECONDARYPWD=`echo "admin" | openssl enc -base64 -A`; else SECONDARYPWD=`echo $SECONDARYPWD1 | openssl enc -base64 -A`; fi;;
                    5 ) echo ""; read -rp 'Secondary Target UNC (ex: \\\\192.168.50.25\\Backups ): ' SECONDARYUNC1; SECONDARYUNC="$SECONDARYUNC1"; SECONDARYUNCUPDATED="True";;
                    6 ) echo ""; if [ "$SECONDARYBACKUPMEDIA" == "Network" ]; then read -p 'Secondary Target Mount Point (ex: /tmp/mnt/backups ): ' SECONDARYUNCDRIVE; elif [ "$SECONDARYBACKUPMEDIA" == "USB" ]; then SECONDARYUSBTARGET="TRUE"; _GetMountPoint_ "Select a Secondary Target USB Backup Drive Mount Point: "; read -rsp $'Press any key to acknowledge...\n' -n1 key; fi; checkusbexclusion;;
                    7 ) echo ""; read -p 'Secondary Target Dir Path (ex: /router/GT-AX6000-Backup ): ' SECONDARYBKDIR; checkusbexclusion;;
                    8 ) echo ""; read -p 'Secondary Exclusion File Name (ex: /jffs/addons/backupmon.d/exclusions2.txt ): ' SECONDARYEXCLUSION; if [ "$BACKUPSWAP" == "0" ] && [ "$SECONDARYEXCLUSION" == "" ]; then SECONDARYEXCLUSION="$PFEXCLUSION"; fi;;
                    9 ) echo ""; read -p 'Secondary Backup Frequency (Weekly=W, Monthly=M, Yearly=Y, Perpetual=P) (W/M/Y/P?): ' SECONDARYFREQUENCY; SECONDARYFREQUENCY=$(echo "$SECONDARYFREQUENCY" | awk '{print toupper($0)}'); SECONDARYPURGE=0; if [ "$SECONDARYFREQUENCY" == "P" ]; then SECONDARYMODE="Basic"; read -p 'Purge Secondary Backups? (Yes=1/No=0) ' SECONDARYPURGE; read -p 'Secondary Backup Purge Age? (Days/Disabled=0) ' SECONDARYPURGELIMIT; else SECONDARYPURGELIMIT=0; fi;;
                    10 ) echo ""; read -p 'Secondary Backup Mode (Basic=0, Advanced=1) (0/1?): ' SECONDARYMODE; if [ "$SECONDARYMODE" == "0" ]; then SECONDARYMODE="Basic"; elif [ "$SECONDARYMODE" == "1" ]; then SECONDARYMODE="Advanced"; else SECONDARYMODE="Basic"; fi; if [ "$SECONDARYFREQUENCY" == "P" ]; then SECONDARYMODE="Basic"; fi;;
                    [Ee] ) break ;;
                    "" ) echo -e "\nError: Please use 1 - 10 or e=Exit\n";;
                    * ) echo -e "\nError: Please use 1 - 10 or e=Exit\n";;
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

                { echo 'BTUSERNAME="'"$BTUSERNAME"'"'
                  echo 'BTPASSWORD="'"$BTPASSWORD"'"'
                  echo 'UNC="'"$UNC"'"'
                  echo 'UNCDRIVE="'"$UNCDRIVE"'"'
                  echo 'EXTDRIVE="'"$EXTDRIVE"'"'
                  echo 'EXTLABEL="'"$EXTLABEL"'"'
                  echo 'BKDIR="'"$BKDIR"'"'
                  echo 'BACKUPMEDIA="'"$BACKUPMEDIA"'"'
                  echo 'EXCLUSION="'"$EXCLUSION"'"'
                  echo 'BACKUPSWAP='$BACKUPSWAP
                  echo 'SMBVER="'"$SMBVER"'"'
                  echo 'SCHEDULE='$SCHEDULE
                  echo 'SCHEDULEHRS='$SCHEDULEHRS
                  echo 'SCHEDULEMIN='$SCHEDULEMIN
                  echo 'SCHEDULEMODE="'"$SCHEDULEMODE"'"'
                  echo 'FREQUENCY="'"$FREQUENCY"'"'
                  echo 'MODE="'"$MODE"'"'
                  echo 'PURGE='$PURGE
                  echo 'PURGELIMIT='$PURGELIMIT
                  echo 'AMTMEMAIL='$AMTMEMAIL
                  echo 'AMTMEMAILSUCCESS='$AMTMEMAILSUCCESS
                  echo 'AMTMEMAILFAILURE='$AMTMEMAILFAILURE
                  echo 'SECONDARYSTATUS='$SECONDARYSTATUS
                  echo 'SECONDARYUSER="'"$SECONDARYUSER"'"'
                  echo 'SECONDARYPWD="'"$SECONDARYPWD"'"'
                  echo 'SECONDARYUNC="'"$SECONDARYUNC"'"'
                  echo 'SECONDARYUNCDRIVE="'"$SECONDARYUNCDRIVE"'"'
                  echo 'SECONDARYBKDIR="'"$SECONDARYBKDIR"'"'
                  echo 'SECONDARYBACKUPMEDIA="'"$SECONDARYBACKUPMEDIA"'"'
                  echo 'SECONDARYEXCLUSION="'"$SECONDARYEXCLUSION"'"'
                  echo 'SECONDARYFREQUENCY="'"$SECONDARYFREQUENCY"'"'
                  echo 'SECONDARYMODE="'"$SECONDARYMODE"'"'
                  echo 'SECONDARYPURGE='$SECONDARYPURGE
                  echo 'SECONDARYPURGELIMIT='$SECONDARYPURGELIMIT
                } > $CFGPATH
              echo -e "${CGreen}Applying config changes to BACKUPMON..."
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Successfully wrote a new config file" >> $LOGFILE
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
      { echo 'BTUSERNAME="admin"'
        echo 'BTPASSWORD="admin"'
        echo 'UNC="\\\\192.168.50.25\\Backups"'
        echo 'UNCDRIVE="/tmp/mnt/backups"'
        echo 'EXTDRIVE="/tmp/mnt/usbdrive"'
        echo 'EXTLABEL="usbdrive"'
        echo 'BKDIR="/router/GT-AX6000-Backup"'
        echo 'BACKUPMEDIA="Network"'
        echo 'EXCLUSION=""'
        echo 'BACKUPSWAP=0'
        echo 'SMBVER="2.1"'
        echo 'SCHEDULE=0'
        echo 'SCHEDULEHRS=2'
        echo 'SCHEDULEMIN=30'
        echo 'SCHEDULEMODE="BackupOnly"'
        echo 'FREQUENCY="M"'
        echo 'MODE="Basic"'
        echo 'PURGE=0'
        echo 'PURGELIMIT=0'
        echo 'AMTMEMAIL=0'
        echo 'AMTMEMAILSUCCESS=0'
        echo 'AMTMEMAILFAILURE=0'
        echo 'SECONDARYSTATUS=0'
        echo 'SECONDARYUSER="admin"'
        echo 'SECONDARYPWD="admin"'
        echo 'SECONDARYUNC="\\\\192.168.50.25\\SecondaryBackups"'
        echo 'SECONDARYUNCDRIVE="/tmp/mnt/secondarybackups"'
        echo 'SECONDARYBKDIR="/router/GT-AX6000-2ndBackup"'
        echo 'SECONDARYBACKUPMEDIA="Network"'
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

# testtarget is a function that allows you to play with settings to ensure your configuration works
testtarget () {

TESTUSER="admin"
TESTPWD="admin"
TESTUNC="\\\\192.168.50.25\\Backups"
TESTUNCDRIVE="/tmp/mnt/testbackups"
TESTBKDIR="/router/test-backup"
TESTBACKUPMEDIA="Network"
TESTUNCUPDATED="False"
TESTSMBVER="2.1"

while true; do
  clear
  logoNM
  echo ""
  echo -e "${CCyan}The Backup Target Network Connection Tester allows you to play with"
  echo -e "your connection variables, such as your username/password, network UNC"
  echo -e "path, target directories and local backup drive mount paths. If your"
  echo -e "network target is configured correctly, this utility will write a test"
  echo -e "folder out there, and copy a test file into the test folder in order"
  echo -e "to validate that read/write permissions are correct."
  echo ""
  echo -e "${CGreen}----------------------------------------------------------------"
  echo -e "${CGreen}Backup Target Network Connection Tester"
  echo -e "${CGreen}----------------------------------------------------------------"
  echo -e "${InvDkGray}${CWhite} 1  ${CClear}${CCyan}: Test Target Media Type              : ${CGreen}$TESTBACKUPMEDIA"
  if [ "$TESTBACKUPMEDIA" == "Network" ]; then
    echo -e "${InvDkGray}${CWhite} 2  ${CClear}${CCyan}: Test Target Username                : ${CGreen}$TESTUSER"
    echo -e "${InvDkGray}${CWhite} 3  ${CClear}${CCyan}: Test Target Password                : ${CGreen}$TESTPWD"
    if [ "$TESTUNCUPDATED" == "True" ]; then
      echo -en "${InvDkGray}${CWhite} 4  ${CClear}${CCyan}: Test Target UNC Path                : ${CGreen}"; printf '%s' $TESTUNC; printf "%s\n"
    else
      echo -en "${InvDkGray}${CWhite} 4  ${CClear}${CCyan}: Test Target UNC Path                : ${CGreen}"; echo $TESTUNC | sed -e 's,\\,\\\\,g'
    fi
  elif [ "$TESTBACKUPMEDIA" == "USB" ]; then
    echo -e "${InvDkGray}${CWhite} 2  ${CClear}${CDkGray}: Test Target Username                : ${CDkGray}$TESTUSER"
    echo -e "${InvDkGray}${CWhite} 3  ${CClear}${CDkGray}: Test Target Password                : ${CDkGray}$TESTPWD"
    if [ "$TESTUNCUPDATED" == "True" ]; then
      echo -en "${InvDkGray}${CWhite} 4  ${CClear}${CDkGray}: Test Target UNC Path                : ${CDkGray}"; printf '%s' $TESTUNC; printf "%s\n"
    else
      echo -en "${InvDkGray}${CWhite} 4  ${CClear}${CDkGray}: Test Target UNC Path                : ${CDkGray}"; echo $TESTUNC | sed -e 's,\\,\\\\,g'
    fi
  fi
  echo -e "${InvDkGray}${CWhite} 5  ${CClear}${CCyan}: Test Target Backup Mount Point      : ${CGreen}$TESTUNCDRIVE"
  echo -e "${InvDkGray}${CWhite} 6  ${CClear}${CCyan}: Test Target Dir Path                : ${CGreen}$TESTBKDIR"
  echo -e "${InvDkGray}${CWhite} 7  ${CClear}${CCyan}: Test CIFS/SMB Version               : ${CGreen}$TESTSMBVER"
  echo -e "${InvDkGray}${CWhite} |  ${CClear}"
  echo -e "${InvDkGray}${CWhite} t  ${CClear}${CCyan}: Test your Network Backup Connection"
  echo -e "${InvDkGray}${CWhite} p  ${CClear}${CCyan}: Import your Primary Backup Settings"
  echo -e "${InvDkGray}${CWhite} s  ${CClear}${CCyan}: Import your Secondary Backup Settings"
  echo -e "${InvDkGray}${CWhite} e  ${CClear}${CCyan}: Exit Back to Setup + Operations Menu"
  echo -e "${CGreen}----------------------------------------------------------------"
  echo ""
  printf "Selection: ${CClear}"
  read -r TESTINPUT
      case $TESTINPUT in
        1 ) echo ""; read -p 'Test Target Media Type (ex: Network=1 / USB=2) (Choose 1 or 2): ' TESTBACKUPMEDIA; if [ "$TESTBACKUPMEDIA" == "1" ]; then TESTBACKUPMEDIA="Network"; elif [ "$TESTBACKUPMEDIA" == "2" ]; then TESTBACKUPMEDIA="USB"; else TESTBACKUPMEDIA="Network"; fi;;
        2 ) echo ""; read -p 'Test Username: ' TESTUSER;;
        3 ) echo ""; read -rp 'Test Password: ' TESTPWD;;
        4 ) echo ""; read -rp 'Test Target UNC (ex: \\\\192.168.50.25\\Backups ): ' TESTUNC1; if [ -z $TESTUNC1 ]; then TESTUNC="\\\\\\\\192.168.50.25\\\\Backups"; else TESTUNC="$TESTUNC1"; fi; TESTUNCUPDATED="True";;
        5 ) echo ""; if [ "$TESTBACKUPMEDIA" == "Network" ]; then read -p 'Test Target Backup Mount Point (ex: /tmp/mnt/testbackups ): ' TESTUNCDRIVE; elif [ "$TESTBACKUPMEDIA" == "USB" ]; then TESTUSBTARGET="TRUE"; _GetMountPoint_ "Select a Test Target USB Backup Mount Point: "; read -rsp $'Press any key to acknowledge...\n' -n1 key; fi;;
        6 ) echo ""; read -p 'Test Target Dir Path (ex: /router/test-backup ): ' TESTBKDIR;;
        7 ) echo ""; read -p 'Test CIFS/SMB Version (ex: v2.1=1 / v2.0=2 / v1.0=3 / v3.0=4 / v3.02=5) (Choose 1, 2, 3, 4 or 5): ' TESTSMBVER; if [ "$TESTSMBVER" == "1" ]; then TESTSMBVER="2.1"; elif [ "$TESTSMBVER" == "2" ]; then TESTSMBVER="2.0"; elif [ "$TESTSMBVER" == "3" ]; then TESTSMBVER="1.0"; elif [ "$TESTSMBVER" == "4" ]; then TESTSMBVER="3.0"; elif [ "$TESTSMBVER" == "5" ]; then TESTSMBVER="3.02"; else TESTSMBVER="2.1"; fi;;
        [Ee] ) break ;;
        [Pp] ) TESTUSER=$BTUSERNAME; TESTPWD=$(echo $BTPASSWORD | openssl enc -d -base64 -A); TESTUNC=$UNC; TESTUNCDRIVE=$UNCDRIVE; TESTBKDIR=$BKDIR; TESTBACKUPMEDIA=$BACKUPMEDIA; TESTSMBVER=$SMBVER;;
        [Ss] ) TESTUSER=$SECONDARYUSER; TESTPWD=$(echo $SECONDARYPWD | openssl enc -d -base64 -A); TESTUNC=$SECONDARYUNC; TESTUNCDRIVE=$SECONDARYUNCDRIVE; TESTBKDIR=$SECONDARYBKDIR; TESTBACKUPMEDIA=$SECONDARYBACKUPMEDIA; TESTSMBVER=$SMBVER;;
        [Tt] )  # Connection test script
                if [ "$TESTUNCUPDATED" == "True" ]; then TESTUNC=$(echo -e "$TESTUNC"); fi
                echo ""
                echo -e "${CCyan}Messages:${CClear}"

                # Ping target to see if it's reachable
                CNT=0
                TRIES=3
                TARGETIP=$(echo $TESTUNC | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
                if [ ! -z $TARGETIP ]; then
                  while [ $CNT -lt $TRIES ]; do # Loop through number of tries
                    ping -q -c 1 -W 2 $TARGETIP > /dev/null 2>&1
                    RC=$?
                    if [ $RC -eq 0 ]; then  # If ping come back successful, then proceed
                      echo -e "${CGreen}INFO: Backup Target ($TARGETIP) reachable via PING.${CClear}"
                      break
                    else
                      echo -e "${CYellow}WARNING: Unable to PING Backup Target ($TARGETIP). Retrying...${CClear}"
                      sleep 3
                      CNT=$((CNT+1))
                      if [ $CNT -eq $TRIES ];then
                        echo -e "${CRed}ERROR: Unable to PING backup target ($TARGETIP). Please check your configuration/permissions.${CClear}"
                        break
                      fi
                    fi
                  done
                fi

                # Check to see if a local backup drive mount is available, if not, create one.
                if ! [ -d $TESTUNCDRIVE ]; then
                    mkdir -p $TESTUNCDRIVE
                    chmod 777 $TESTUNCDRIVE
                    echo -e "${CYellow}WARNING: External test drive mount point not set. Created under: $TESTUNCDRIVE ${CClear}"
                    sleep 3
                else
                  echo -e "${CGreen}INFO: External test drive mount point exists. Found under: ${CYellow}$TESTUNCDRIVE ${CClear}"
                fi

                # If everything successfully was created, proceed
                if ! mount | grep $TESTUNCDRIVE > /dev/null 2>&1; then

                    # Check the build to see if modprobe needs to be called
                    if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
                      modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
                    fi

                    if [ "$TESTBACKUPMEDIA" == "USB" ]; then
                      echo -en "${CGreen}STATUS: External test drive (USB) skipping mounting process.${CClear}"; printf "%s\n"
                    else
                      CNT=0
                      TRIES=3
                        while [ $CNT -lt $TRIES ]; do # Loop through number of tries
                          mount -t cifs $TESTUNC $TESTUNCDRIVE -o "vers=${TESTSMBVER},username=${TESTUSER},password=${TESTPWD}"  # Connect the UNC to the local backup drive mount
                          MRC=$?
                          if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
                            break
                          else
                            echo -e "${CYellow}WARNING: Unable to mount to external network drive. Retrying...${CClear}"
                            sleep 5
                            CNT=$((CNT+1))
                            if [ $CNT -eq $TRIES ];then
                              echo -e "${CRed}ERROR: Unable to mount to external network drive ($TESTUNCDRIVE). Please check your configuration. Exiting.${CClear}"
                              FAILURE="TRUE"
                              break
                            fi
                          fi
                        done
                    fi
                fi

                if [ "$FAILURE" == "TRUE" ]; then
                  read -rsp $'Press any key to acknowledge...\n' -n1 key
                fi

                # If the local mount is connected to the UNC, proceed
                if [ -n "`mount | grep $TESTUNCDRIVE`" ]; then

                    echo -en "${CGreen}STATUS: External test drive ("; printf "%s" "${TESTUNC}"; echo -en ") mounted successfully under: ${CYellow}$TESTUNCDRIVE ${CClear}"; printf "%s\n"

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
                    echo -e "${CRed}ERROR: Failed to run Network Backup Test Script -- Drive mount failed. Please check your configuration!${CClear}"
                    read -rsp $'Press any key to acknowledge...\n' -n1 key

                fi
                TESTUNCUPDATED="False"

        ;;
        "" ) echo -e "\nError: Please use 1 - 9 or Exit = e\n";;
        * ) echo -e "\nError: Please use 1 - 9 or Exit = e\n";;

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
    echo -e "\n${CCyan}Are you sure? Please type 'y' to validate you want to proceed.${CClear}"
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
        curl --silent --retry 3 "https://raw.githubusercontent.com/ViktorJp/backupmon/master/backupmon.sh" -o "/jffs/scripts/backupmon.sh" && chmod 755 "/jffs/scripts/backupmon.sh"
        echo ""
        echo -e "${CCyan}Download successful!${CClear}"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Successfully downloaded and installed BACKUPMON v$DLVersion" >> $LOGFILE
        echo ""
        read -rsp $'Press any key to restart BACKUPMON...\n' -n1 key
        exec /jffs/scripts/backupmon.sh -setup
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
        curl --silent --retry 3 "https://raw.githubusercontent.com/ViktorJp/backupmon/master/backupmon.sh" -o "/jffs/scripts/backupmon.sh" && chmod 755 "/jffs/scripts/backupmon.sh"
        echo ""
        echo -e "${CCyan}Download successful!${CClear}"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Successfully downloaded and installed BACKUPMON v$DLVersion" >> $LOGFILE
        echo ""
        read -rsp $'Press any key to restart BACKUPMON...\n' -n1 key
        exec /jffs/scripts/backupmon.sh -setup
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
# This function checks to see if the source and target are the same, that it throws up a warning to add the backup folder
# to the exclusion file

checkusbexclusion ()
{

if [ "$EXTDRIVE" == "$UNCDRIVE" ]; then
  BKDIREXCL=$(echo $BKDIR | sed 's/^.\{1\}//')
  if grep -q $BKDIREXCL $EXCLUSION; then 
    echo ""
    echo -e "${CGreen}SUCCESS: Primary USB Backup Folder already included in TAR Exclusion File${CCLear}"
    sleep 2
  else
    echo ""
    echo -e "${CRed}WARNING: Primary USB Backup Folder not found in TAR Exclusion File${CClear}"
    echo ""
    echo -e "${CCyan}Your settings indicate that your are backing up your USB drive to the same USB drive."
    echo -e "While it is possible to continue with this configuration, it is not recommended, as a"
    echo -e "failure of your USB drive will result in a complete loss of your backups. Also, by not"
    echo -e "exluding your backup folder in your TAR exclusion file, you will be backing up your"
    echo -e "backups, which will result in exponential growth of your backup files, and the time it"
    echo -e "will take to run your backups. It is recommended to add your backup folder to your TAR"
    echo -e "exclusion file now (assuming it is in '/mainfolder/subfolder' format)${CClear}"
    echo ""
    echo -e "Would you like to exclude your USB backup folder from your regular backups?"
    if promptyn " (y/n): "; then
      echo -e "$BKDIREXCL/*" >> $EXCLUSION
      echo ""
      echo -e "\n${CGreen}SUCCESS: Primary USB Backup Folder added to TAR Exclusion File${CCLear}"
      sleep 2
    else
      echo -e "\n\n${CRed}WARNING: Primary USB Backup Folder not added to TAR Exclusion File${CClear}"
      echo ""
      echo -e "${CCyan}You are assuming the risk and responsibility of your USB drive possibly running out"
      echo -e "of space due to exponential backup file growth, as well as the ever-increasing time"
      echo -e "it will take to run backups. Please consider the risk of loss of all backups if your"
      echo -e "USB drive fails. Consider adding your USB backup folder as an exclusion in your TAR"
      echo -e "exclusion file to mitigate some of these risks.${CClear}"
      echo ""
      read -rsp $'Press any key to acknowledge you are taking ownership of this risk...\n' -n1 key
    fi
  fi
fi

if [ $SECONDARYSTATUS -eq 1 ]; then
  if [ "$EXTDRIVE" == "$SECONDARYUNCDRIVE" ]; then
    SECONDARYBKDIREXCL=$(echo $SECONDARYBKDIR | sed 's/^.\{1\}//')
    if grep -q $SECONDARYBKDIREXCL $SECONDARYEXCLUSION; then 
      echo ""
      echo -e "${CGreen}SUCCESS: Secondary USB Backup Folder already included in TAR Exclusion File${CCLear}"
      sleep 2
    else
      echo ""
      echo -e "${CRed}WARNING: Secondary USB Backup Folder not found in TAR Exclusion File${CClear}"
      echo ""
      echo -e "${CCyan}Your settings indicate that your are backing up your USB drive to the same USB drive."
      echo -e "While it is possible to continue with this configuration, it is not recommended, as a"
      echo -e "failure of your USB drive will result in a complete loss of your backups. Also, by not"
      echo -e "exluding your backup folder in your TAR exclusion file, you will be backing up your"
      echo -e "backups, which will result in exponential growth of your backup files, and the time it"
      echo -e "will take to run your backups. It is recommended to add your backup folder to your TAR"
      echo -e "exclusion file now (assuming it is in '/mainfolder/subfolder' format)${CClear}"
      echo ""
      echo -e "Would you like to exclude your USB backup folder from your regular backups?"
      if promptyn " (y/n): "; then
        echo -e "$SECONDARYBKDIREXCL/*" >> $SECONDARYEXCLUSION
        echo ""
        echo -e "\n${CGreen}SUCCESS: Secondary USB Backup Folder added to TAR Exclusion File${CCLear}"
        sleep 2
      else
        echo -e "\n\n${CRed}WARNING: Secondary USB Backup Folder not added to TAR Exclusion File${CClear}"
        echo ""
        echo -e "${CCyan}You are assuming the risk and responsibility of your USB drive possibly running out"
        echo -e "of space due to exponential backup file growth, as well as the ever-increasing time"
        echo -e "it will take to run backups. Please consider the risk of loss of all backups if your"
        echo -e "USB drive fails. Consider adding your USB backup folder as an exclusion in your TAR"
        echo -e "exclusion file to mitigate some of these risks.${CClear}"
        echo ""
        read -rsp $'Press any key to acknowledge you are taking ownership of this risk...\n' -n1 key
      fi
    fi
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
         echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Purging backup older than $2 days -> $1" >> $LOGFILE
       fi
   fi
   return "$retCode"
}

# -------------------------------------------------------------------------------------------------------------------------

# Also coming to you from @Martinski! The following functions provide a mount point picker, slightly modified for my purposes
_GetMountPointSelectionIndex_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1 ; fi

   local theAllStr="${GRNct}all${NOct}"
   local numRegExp="([1-9]|[1-9][0-9])"
   local theExitStr="${GRNct}e${NOct}=Exit"
   local selectStr  promptStr  indexNum  indexList  multiIndexListOK

   if [ "$1" -eq 1 ]
   then selectStr="${GRNct}1${NOct}"
   else selectStr="${GRNct}1${NOct}-${GRNct}${1}${NOct}"
   fi

   if [ $# -lt 2 ] || [ "$2" != "-MULTIOK" ]
   then
       multiIndexListOK=false
       promptStr="Enter selection:[${selectStr}] [${theExitStr}]?"
   else
       multiIndexListOK=true
       promptStr="Enter selection:[${selectStr} | ${theAllStr}] [${theExitStr}]?"
   fi
   selectionIndex=0  multiIndex=false

   while true
   do
       printf "${promptStr}  " ; read -r userInput

       if [ -z "$userInput" ] || \
          echo "$userInput" | grep -qE "^(e|exit|Exit)$"
       then selectionIndex="NONE" ; break ; fi

       if "$multiIndexListOK" && \
          echo "$userInput" | grep -qE "^(all|All)$"
       then selectionIndex="ALL" ; break ; fi

       if echo "$userInput" | grep -qE "^${numRegExp}$" && \
          [ "$userInput" -gt 0 ] && [ "$userInput" -le "$1" ]
       then selectionIndex="$userInput" ; break ; fi

       if "$multiIndexListOK" && \
          echo "$userInput" | grep -qE "^${numRegExp}\-${numRegExp}[ ]*$"
       then
           index1st="$(echo "$userInput" | awk -F '-' '{print $1}')"
           indexMax="$(echo "$userInput" | awk -F '-' '{print $2}')"
           if [ "$index1st" -lt "$indexMax" ]  && \
              [ "$index1st" -gt 0 ] && [ "$index1st" -le "$1" ] && \
              [ "$indexMax" -gt 0 ] && [ "$indexMax" -le "$1" ]
           then
               indexNum="$index1st"
               indexList="$indexNum"
               while [ "$indexNum" -lt "$indexMax" ]
               do
                   indexNum="$((indexNum+1))"
                   indexList="${indexList},${indexNum}"
               done
               userInput="$indexList"
           fi
       fi

       if "$multiIndexListOK" && \
          echo "$userInput" | grep -qE "^${numRegExp}(,[ ]*${numRegExp}[ ]*)+$"
       then
           indecesOK=true
           indexList="$(echo "$userInput" | sed 's/ //g' | sed 's/,/ /g')"
           for theIndex in $indexList
           do
              if [ "$theIndex" -eq 0 ] || [ "$theIndex" -gt "$1" ]
              then indecesOK=false ; break ; fi
           done
           "$indecesOK" && selectionIndex="$indexList" && multiIndex=true && break
       fi

       printf "${REDct}INVALID selection.${NOct}\n"
   done
}

# -------------------------------------------------------------------------------------------------------------------------

##----------------------------------------##
## Modified by Martinski W. [2023-Nov-08] ##
##----------------------------------------##
_GetMountPointSelection_()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then printf "\n${REDct}**ERROR**${NOct}: No Parameters.\n" ; return 1 ; fi

   local mounPointCnt  mounPointVar=""  mounPointTmp=""
   local mountPointRegExp="^/dev/sd.* /tmp/mnt/.*"

   mounPointPath=""
   mounPointCnt="$(mount | grep -c "$mountPointRegExp")"
   if [ "$mounPointCnt" -eq 0 ]
   then
       printf "\n${REDct}**ERROR**${NOct}: Mount Points for USB-attached drives are *NOT* found.\n"
       return 1
   fi
   if [ "$mounPointCnt" -eq 1 ]
   then
       mounPointPath="$(mount | grep "$mountPointRegExp" | awk -F ' ' '{print $3}')"
       return 0
   fi
   local retCode=0  indexType  multiIndex=false  selectionIndex=0

   if [ $# -lt 2 ] || [ "$2" != "-MULTIOK" ]
   then indexType="" ; else indexType="$2" ; fi

   printf "\n$1\n"
   mounPointCnt=0
   while IFS="$(printf '\n')" read -r mounPointInfo
   do
       mounPointCnt="$((mounPointCnt + 1))"
       mounPointVar="MP_${mounPointCnt}_INFO"
       eval "MP_${mounPointCnt}_INFO=$(echo "$mounPointInfo" | sed 's/[(<; >)]/\\&/g')"
       printf "${GRNct}%3d${NOct}. " "$mounPointCnt"
       eval echo "\$${mounPointVar}"
   done <<EOT
$(mount | grep "$mountPointRegExp" | awk -F ' ' '{print $1,$2,$3,$4,$5}' | sort -dt ' ' -k 1)
EOT

   echo
   _GetMountPointSelectionIndex_ "$mounPointCnt" "$indexType"

   if [ "$selectionIndex" = "NONE" ] ; then return 1 ; fi

   while true
   do
       if [ "$indexType" = "-MULTIOK" ]
       then
           if [ "$selectionIndex" = "ALL" ]
           then
               mounPointTmp="$(mount | grep "$mountPointRegExp" | awk -F ' ' '{print $1,$3}' | sort -dt ' ' -k 1)"
               mounPointPath="$(echo "$mounPointTmp" | awk -F ' ' '{print $2}')"
               break
           fi
           if "$multiIndex"
           then
               for index in $selectionIndex
               do
                   mounPointVar="MP_${index}_INFO"
                   eval mounPointTmp="\$${mounPointVar}"
                   mounPointTmp="$(echo "$mounPointTmp" | awk -F ' ' '{print $3}')"
                   if [ -z "$mounPointPath" ]
                   then mounPointPath="$mounPointTmp"
                   else mounPointPath="${mounPointPath}\n${mounPointTmp}"
                   fi
               done
               break
           fi
       fi
       mounPointVar="MP_${selectionIndex}_INFO"
       eval mounPointTmp="\$${mounPointVar}"
       mounPointPath="$(echo "$mounPointTmp" | awk -F ' ' '{print $3}')"
       if [ ! -d "$mounPointPath" ] ; then mounPointPath="" ; fi
       break
   done

   if [ -z "$mounPointPath" ] ; then retCode=1 ; fi
   return "$retCode"
}

# -------------------------------------------------------------------------------------------------------------------------

_GetMountPoint_()
{
   local NOct="\033[0m"  REDct="\033[0;31m\033[1m"  GRNct="\033[1;32m\033[1m"
   local mounPointPath=""

   _GetMountPointSelection_ "$@"
   if [ $? -gt 0 ] || [ -z "$mounPointPath" ]
   then
       printf "\nNo Mount Points for USB-attached drives were selected.\n\n"
       return 1
   fi

   printf "\nMount Point Selected:\n${GRNct}${mounPointPath}${NOct}\n\n"

   ## Do whatever you need to do with value of "$mounPointPath" ##
   if [ "$USBSOURCE" == "TRUE" ]; then
    EXTDRIVE=$mounPointPath
    EXTLABEL=$(echo "${mounPointPath##*/}")
   elif [ "$USBTARGET" == "TRUE" ]; then
    UNCDRIVE=$mounPointPath
   elif [ "$SECONDARYUSBTARGET" == "TRUE" ]; then
    SECONDARYUNCDRIVE=$mounPointPath
   elif [ "$TESTUSBTARGET" == "TRUE" ]; then
    TESTUNCDRIVE=$mounPointPath
   fi
   
   USBSOURCE="FALSE"
   USBTARGET="FALSE"
   SECONDARYUSBTARGET="FALSE"
   TESTUSBTARGET="FALSE"
}

# -------------------------------------------------------------------------------------------------------------------------

_GetDefaultUSBMountPoint_()
{
   local mounPointPath  retCode=0
   local mountPointRegExp="^/dev/sd.* /tmp/mnt/.*"

   mounPointPath="$(grep -m1 "$mountPointRegExp" /proc/mounts | awk -F ' ' '{print $2}')"
   [ -z "$mounPointPath" ] && retCode=1
   echo "$mounPointPath" ; return "$retCode"
}

# -------------------------------------------------------------------------------------------------------------------------

##----------------------------------------##
## Modified by Martinski W. [2024-Feb-29] ##
##----------------------------------------##
#---------------------------------------------------------#
# The USB-attached drives may have multiple partitions
# with different file systems (NTFS, ext3, ext4, etc.),
# which means that multiple mount points can be found.
# Here we check if a mounted USB-attached drive exists;
# if not, we return a null string. If it exists, then
# we search for the Volume Labels; if found, we return
# the first label; otherwise, we return a null string.
#---------------------------------------------------------#
_CheckForMountPointAndVolumeLabel_()
{
   local theLabel  foundLabelOK=false
   local mounPointPaths  nvramLabels  blkidLabels  
   local mountPointRegExp="^/dev/sd.* /tmp/mnt/.*"
   local rwPartitions

   mounPointPaths="$(grep -E "$mountPointRegExp" /proc/mounts | awk -F ' ' '{print $2}')"
   [ -z "$mounPointPaths" ] && echo "" && return 1

   # Get a list of read-write mounted partitions
   rwPartitions=$(mount | awk '$6 ~ /\<rw\>/ {print $1}')
   
   # Ensure blkid only checks those read-write partitions
   blkidLabels="$(echo $rwPartitions | xargs -n 1 blkid | grep "^/dev/sd.*: LABEL=" | sort -dt ':' -k 1 | awk -F ' ' '{print $2}' | awk -F '"' '{print $2}')"
   nvramLabels="$(nvram show 2>/dev/null | grep -E "^usb_path_sd[a-z][0-9]_label=" | sort -dt '_' -k 3 | awk -F '=' '{print $2}')"
   { [ -z "$blkidLabels" ] && [ -z "$nvramLabels" ] ; } && echo "" && return 1

   theLabel=""
   for theLabel in $nvramLabels $blkidLabels
   do
       if echo "${mounPointPaths}" | grep -qE "/${theLabel}$"
       then foundLabelOK=true ; break ; fi
   done
   "$foundLabelOK" && echo "$theLabel" && return 0

   echo "" ; return 1
}

# -------------------------------------------------------------------------------------------------------------------------

########################################################################
# AMTM Email Notification Functionality generously donated by @Martinski!
#
# Creation Date: 2020-Jun-11 [Martinski W.]
# Last Modified: 2024-Feb-07 [Martinski W.]
# Modified for BACKUPMON Purposes [Viktor Jaep]
########################################################################

#-----------------------------------------------------------#
_DownloadCEMLibraryFile_()
{
   local msgStr  retCode
   case "$1" in
        update) msgStr="Updating" ;;
       install) msgStr="Installing" ;;
             *) return 1 ;;
   esac
   
   echo -e "${CGreen}STATUS: ${msgStr} the shared library script file to support email notifications...${CClear}" 
   echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: ${msgStr} the shared library script file to support email notifications..." >> $LOGFILE

   mkdir -m 755 -p "$CUSTOM_EMAIL_LIBDir"
   curl -kLSs --retry 3 --retry-delay 5 --retry-connrefused \
   "${CEM_LIB_URL}/$CUSTOM_EMAIL_LIBName" -o "$CUSTOM_EMAIL_LIBFile"
   curlCode="$?"

   if [ "$curlCode" -eq 0 ] && [ -f "$CUSTOM_EMAIL_LIBFile" ]
   then
       retCode=0
       chmod 755 "$CUSTOM_EMAIL_LIBFile"
       . "$CUSTOM_EMAIL_LIBFile"
       #printf "\nDone.\n"
   else
       retCode=1
       echo -e "${CRed}ERROR: Unable to download the shared library script file [$CUSTOM_EMAIL_LIBName].${CClear}"
       echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to download the shared library script file [$CUSTOM_EMAIL_LIBName]." >> $LOGFILE
   fi
   return "$retCode"
}

#-----------------------------------------------------------#
# ARG1: The email name/alias to be used as "FROM_NAME"
# ARG2: The email Subject string.
# ARG3: Full path of file containing the email Body text.
# ARG4: The email Body Title string [OPTIONAL].
#-----------------------------------------------------------#
_SendEMailNotification_()
{

   if [ -z "${amtmIsEMailConfigFileEnabled:+xSETx}" ]
   then
       echo -e "${CRed}ERROR: Email library script [$CUSTOM_EMAIL_LIBFile] *NOT* FOUND.${CClear}"
       echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Email library script [$CUSTOM_EMAIL_LIBFile] *NOT* FOUND." >> $LOGFILE
       return 1
   fi

   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then
       echo -e "${CRed}ERROR: INSUFFICIENT email parameters${CClear}"
       echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: INSUFFICIENT email parameters." >> $LOGFILE
       return 1
   fi
   local retCode  emailBodyTitleStr=""
   
   [ $# -gt 3 ] && [ -n "$4" ] && emailBodyTitleStr="$4"

   FROM_NAME="$1"
   _SendEMailNotification_CEM_ "$2" "-F=$3" "$emailBodyTitleStr"
   retCode="$?"
   
   if [ "$retCode" -eq 0 ]
   then
     echo -e "${CGreen}STATUS: Email notification was sent successfully [$2].${CClear}" 
     echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Email notification was sent successfully [$2]." >> $LOGFILE
   else
     echo -e "${CRed}ERROR: Failure to send email notification [Error Code: $retCode][$2].${CClear}"
     echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Failure to send email notification [$2]." >> $LOGFILE
   fi

   return "$retCode"
}

# -------------------------------------------------------------------------------------------------------------------------

# sendmessage is a function that sends an AMTM email based on success/failure during the backup process
# $1 = Success/Failure 0/1
# $2 = Component

sendmessage () {

#If AMTM email functionality is disabled, return back to the function call
if [ "$AMTMEMAIL" == "0" ]; then
  return
fi

  #Load, install or update the shared AMTM Email integration library
  if [ -f "$CUSTOM_EMAIL_LIBFile" ]
  then
    . "$CUSTOM_EMAIL_LIBFile"

    if [ -z "${CEM_LIB_VERSION:+xSETx}" ] || \
      _CheckLibraryUpdates_CEM_ "$CUSTOM_EMAIL_LIBDir" quiet
    then
      _DownloadCEMLibraryFile_ "update"
    fi
  else
      _DownloadCEMLibraryFile_ "install"
  fi

  cemIsFormatHTML=true
  cemIsVerboseMode=false
  tmpEMailBodyFile="/tmp/var/tmp/tmpEMailBody_${scriptFileNTag}.$$.TXT"

  #Pick the scenario and send email

  if [ "$2" == "Unable to mount network drive" ]; then
    emailSubject="FAILURE: Unable to mount network drive"
    emailBodyTitle="FAILURE: Unable to mount network drive"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>FAILURE: BACKUPMON</b> was unable to mount the primary network drive.\n"
    printf "Please check your network environment and configuration.\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  elif [ "$2" == "Unable to mount secondary network drive" ]; then
    emailSubject="FAILURE: Unable to mount secondary network drive"
    emailBodyTitle="FAILURE: Unable to mount secondary network drive"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>FAILURE: BACKUPMON</b> was unable to mount the secondary network drive.\n"
    printf "Please check your network environment and configuration.\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  elif [ "$2" == "Unable to unmount network drive" ]; then
    emailSubject="FAILURE: Unable to unmount network drive"
    emailBodyTitle="FAILURE: Unable to unmount network drive"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>FAILURE: BACKUPMON</b> was unable to unmount the primary network drive.\n"
    printf "Please check your network environment and configuration.\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  elif [ "$2" == "Unable to unmount secondary network drive" ]; then
    emailSubject="FAILURE: Unable to unmount secondary network drive"
    emailBodyTitle="FAILURE: Unable to unmount secondary network drive"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>FAILURE: BACKUPMON</b> was unable to unmount the secondary network drive.\n"
    printf "Please check your network environment and configuration.\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  elif [ "$2" == "Error creating JFFS tar file" ]; then
    emailSubject="FAILURE: Error creating JFFS tar file"
    emailBodyTitle="FAILURE: Error creating JFFS tar file"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>FAILURE: BACKUPMON</b> was unable to create/write the JFFS tar file.\n"
    printf "Please check your network environment and configuration.\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  elif [ "$2" == "JFFS tar file integrity failure" ]; then
    emailSubject="FAILURE: JFFS tar file integrity failure"
    emailBodyTitle="FAILURE: JFFS tar file integrity failure"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>FAILURE: BACKUPMON</b> experienced a JFFS tar file integrity issue.\n"
    printf "Please check your network environment and configuration.\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  elif [ "$2" == "Error creating EXT USB tar file" ]; then
    emailSubject="FAILURE: Error creating EXT USB tar file"
    emailBodyTitle="FAILURE: Error creating EXT USB tar file"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>FAILURE: BACKUPMON</b> was unable to create/write the EXT USB tar file.\n"
    printf "Please check your network environment and configuration.\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  elif [ "$2" == "EXT USB tar file integrity failure" ]; then
    emailSubject="FAILURE: EXT USB tar file integrity failure"
    emailBodyTitle="FAILURE: EXT USB tar file integrity failure"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>FAILURE: BACKUPMON</b> experienced a EXT USB tar file integrity issue.\n"
    printf "Please check your network environment and configuration.\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  elif [ "$2" == "Primary Backup completed successfully" ]; then
    emailSubject="SUCCESS: Primary Backup completed successfully"
    emailBodyTitle="SUCCESS: Primary Backup completed successfully"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>SUCCESS: BACKUPMON</b> completed a successful primary backup to destination: <b>${BACKUPMEDIA}</b>\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  elif [ "$2" == "Secondary Backup completed successfully" ]; then
    emailSubject="SUCCESS: Secondary Backup completed successfully"
    emailBodyTitle="SUCCESS: Secondary Backup completed successfully"
    {
    printf "<b>Date/Time:</b> $(date +'%b %d %Y %X')\n"
    printf "<b>Asus Router Model:</b> ${ROUTERMODEL}\n"
    printf "<b>Firmware/Build Number:</b> ${FWBUILD}\n"
    printf "<b>EXT USB Drive Label Name:</b> ${EXTLABEL}\n"
    printf "\n"
    printf "<b>SUCCESS: BACKUPMON</b> completed a successful secondary backup to destination: <b>${BACKUPMEDIA}</b>\n"
    printf "\n"
    } > "$tmpEMailBodyFile"
  fi

  if [ "$1" == "0" ] && [ "$AMTMEMAILSUCCESS" == "1" ]; then
    _SendEMailNotification_ "BACKUPMON v$Version" "$emailSubject" "$tmpEMailBodyFile" "$emailBodyTitle"
  fi
  
  if [ "$1" == "1" ] && [ "$AMTMEMAILFAILURE" == "1" ]; then
    _SendEMailNotification_ "BACKUPMON v$Version" "$emailSubject" "$tmpEMailBodyFile" "$emailBodyTitle"
  fi
  
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
  echo -e "${CYellow}$PURGELIMIT day${CCyan} limit you have configured."
  echo ""
  echo -e "${CCyan}Do you wish to proceed?${CClear}"
  if promptyn "(y/n): "; then

    echo ""
    echo -e "\n${CCyan}Messages:${CClear}"

    # Create the local backup drive mount directory
    if ! [ -d $UNCDRIVE ]; then
        mkdir -p $UNCDRIVE
        chmod 777 $UNCDRIVE
        echo -e "${CYellow}WARNING: External drive mount point not set. Created under: $UNCDRIVE ${CClear}"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External drive mount point not set. Created under: $UNCDRIVE" >> $LOGFILE
        sleep 3
    fi

    # If the mount does not exist yet, proceed
    if ! mount | grep $UNCDRIVE > /dev/null 2>&1; then

      # Check if the build supports modprobe
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      # Mount the local backup drive directory to the UNC
      if [ "$BACKUPMEDIA" == "USB" ]; then
        echo -en "${CGreen}STATUS: External drive (USB) skipping mounting process.${CClear}"; printf "%s\n"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External drive (USB) skipping mounting process." >> $LOGFILE
      else
        CNT=0
        TRIES=3
          while [ $CNT -lt $TRIES ]; do # Loop through number of tries
            UNENCPWD=$(echo $BTPASSWORD | openssl enc -d -base64 -A)
            mount -t cifs $UNC $UNCDRIVE -o "vers=${SMBVER},username=${BTUSERNAME},password=${UNENCPWD}"  # Connect the UNC to the local backup drive mount
            MRC=$?
            if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
              echo -en "${CGreen}STATUS: External network drive ("; printf "%s" "${UNC}"; echo -en ") mounted successfully under: $UNCDRIVE ${CClear}"; printf "%s\n"
              printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External network drive ( ${UNC} ) mounted successfully under: $UNCDRIVE" >> $LOGFILE
              break
            else
              echo -e "${CYellow}WARNING: Unable to mount to external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
              sleep 10
              CNT=$((CNT+1))
              if [ $CNT -eq $TRIES ];then
                echo -e "${CRed}ERROR: Unable to mount to external network drive. Please check your configuration. Exiting.${CClear}"
                logger "BACKUPMON ERROR: Unable to mount to external network drive. Please check your configuration!"
                echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to mount to external network drive. Please check your configuration!" >> $LOGFILE
                sendmessage 1 "Unable to mount network drive"
                echo -e "\n"
                exit 1
              fi
            fi
          done
      fi
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
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: No perpetual backup folders older than $PURGELIMIT days were found. Nothing to delete." >> $LOGFILE
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

  if [ "$FREQUENCY" != "P" ]; then
    echo -e "${CRed}ERROR: Perpetual backups are not configured. Please check your configuration. Exiting.${CClear}"
    echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Perpetual backups are not configured. Please check your configuration." >> $LOGFILE
    exit 1
  fi

  if [ "$PURGE" -eq 0 ]; then
    return
  fi

  echo ""
  echo -e "${CGreen}[Auto Purge Primary Backups Commencing]..."
  echo ""
  echo -e "${CCyan}Messages:${CClear}"

  # Create the local backup drive mount directory
  if ! [ -d $UNCDRIVE ]; then
      mkdir -p $UNCDRIVE
      chmod 777 $UNCDRIVE
      echo -e "${CYellow}WARNING: External drive mount point not set. Created under: $UNCDRIVE ${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External drive mount point not set. Created under: $UNCDRIVE" >> $LOGFILE
      sleep 3
  fi

  # If the mount does not exist yet, proceed
  if ! mount | grep $UNCDRIVE > /dev/null 2>&1; then

    # Check if the build supports modprobe
    if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
      modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
    fi

    # Mount the local backup drive directory to the UNC
    if [ "$BACKUPMEDIA" == "USB" ]; then
      echo -en "${CGreen}STATUS: External drive (USB) skipping mounting process.${CClear}"; printf "%s\n"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External drive (USB) skipping mounting process." >> $LOGFILE
    else
      CNT=0
      TRIES=3
        while [ $CNT -lt $TRIES ]; do # Loop through number of tries
          UNENCPWD=$(echo $BTPASSWORD | openssl enc -d -base64 -A)
          mount -t cifs $UNC $UNCDRIVE -o "vers=${SMBVER},username=${BTUSERNAME},password=${UNENCPWD}"  # Connect the UNC to the local backup drive mount
          MRC=$?
          if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
            echo -en "${CGreen}STATUS: External network drive ("; printf "%s" "${UNC}"; echo -en ") mounted successfully under: $UNCDRIVE ${CClear}"; printf "%s\n"
            printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External network drive ( ${UNC} ) mounted successfully under: $UNCDRIVE" >> $LOGFILE
            break
          else
            echo -e "${CYellow}WARNING: Unable to mount to external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
            sleep 10
            CNT=$((CNT+1))
            if [ $CNT -eq $TRIES ];then
              echo -e "${CRed}ERROR: Unable to mount to external network drive. Please check your configuration. Exiting.${CClear}"
              logger "BACKUPMON ERROR: Unable to mount to external network drive. Please check your configuration!"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to mount to external network drive. Please check your configuration!" >> $LOGFILE
              sendmessage 1 "Unable to mount network drive"
              echo -e "\n"
              exit 1
            fi
          fi
        done
    fi
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
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: No perpetual backup folders older than $PURGELIMIT days were found. Nothing to delete." >> $LOGFILE
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountdrv

        return

      else

        echo -e "${CGreen}STATUS: Perpetual backup folders older than $PURGELIMIT days deleted.${CClear}"
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountdrv

        return
      fi

  else

    echo -e "${CGreen}STATUS: Settling for 10 seconds..."
    sleep 10

    unmountdrv

    return
  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# purgebackups is a function that allows you to see which backups will be purged before deleting them...
purgesecondaries () {

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
  echo -e "${CCyan}by the ${CYellow}$SECONDARYPURGELIMIT day${CCyan} limit you have configured."
  echo ""
  echo -e "${CCyan}Do you wish to proceed?${CClear}"
  if promptyn "(y/n): "; then

    echo ""
    echo -e "\n${CCyan}Messages:${CClear}"

    # Create the local backup drive mount directory
    if ! [ -d $SECONDARYUNCDRIVE ]; then
        mkdir -p $SECONDARYUNCDRIVE
        chmod 777 $SECONDARYUNCDRIVE
        echo -e "${CYellow}WARNING: External Secondary drive mount point not set. Created under: $SECONDARYUNCDRIVE ${CClear}"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External Secondary drive mount point not set. Created under: $SECONDARYUNCDRIVE" >> $LOGFILE
        sleep 3
    fi

    # If the mount does not exist yet, proceed
    if ! mount | grep $SECONDARYUNCDRIVE > /dev/null 2>&1; then

      # Check if the build supports modprobe
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      # Mount the local backup drive directory to the UNC
      if [ "$SECONDARYBACKUPMEDIA" == "USB" ]; then
        echo -en "${CGreen}STATUS: Secondary external drive (USB) skipping mounting process.${CClear}"; printf "%s\n"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary external drive (USB) skipping mounting process." >> $LOGFILE
      else
        CNT=0
        TRIES=3
          while [ $CNT -lt $TRIES ]; do # Loop through number of tries
            UNENCSECPWD=$(echo $SECONDARYPWD | openssl enc -d -base64 -A)
            mount -t cifs $SECONDARYUNC $SECONDARYUNCDRIVE -o "vers=${SMBVER},username=${SECONDARYUSER},password=${UNENCSECPWD}"  # Connect the UNC to the local backup drive mount
            MRC=$?
            if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
              echo -en "${CGreen}STATUS: Secondary external network drive ("; printf "%s" "${SECONDARYUNC}"; echo -en ") mounted successfully under: $SECONDARYUNCDRIVE ${CClear}"; printf "%s\n"
              printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary external network drive ( ${SECONDARYUNC} ) mounted successfully under: $SECONDARYUNCDRIVE" >> $LOGFILE
              break
            else
              echo -e "${CYellow}WARNING: Unable to mount to secondary external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
              sleep 10
              CNT=$((CNT+1))
              if [ $CNT -eq $TRIES ];then
                echo -e "${CRed}ERROR: Unable to mount to secondary external network drive. Please check your configuration. Exiting.${CClear}"
                logger "BACKUPMON ERROR: Unable to mount to secondary external network drive. Please check your configuration!"
                echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to mount to secondary external network drive. Please check your configuration!" >> $LOGFILE
                sendmessage 1 "Unable to mount secondary network drive"
                echo -e "\n"
                exit 1
              fi
            fi
          done
      fi
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
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: No perpetual secondary backup folders older than $SECONDARYPURGELIMIT days were found. Nothing to delete." >> $LOGFILE
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

  if [ "$SECONDARYFREQUENCY" != "P" ]; then
    echo -e "${CRed}ERROR: Perpetual secondary backups are not configured. Please check your configuration. Exiting.${CClear}"
    echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Perpetual secondary backups are not configured. Please check your configuration." >> $LOGFILE
    exit 1
  fi

  if [ $SECONDARYPURGE -eq 0 ]; then
    return
  fi

  if [ $SECONDARYSTATUS -eq 0 ]; then
    return
  fi

  echo ""
  echo -e "${CGreen}[Auto Purge Secondary Backups Commencing]..."
  echo ""
  echo -e "${CCyan}Messages:${CClear}"

  # Create the local backup drive mount directory
  if ! [ -d $SECONDARYUNCDRIVE ]; then
      mkdir -p $SECONDARYUNCDRIVE
      chmod 777 $SECONDARYUNCDRIVE
      echo -e "${CYellow}WARNING: External secondary drive mount point not set. Created under: $SECONDARYUNCDRIVE ${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External secondary drive mount point not set. Created under: $SECONDARYUNCDRIVE" >> $LOGFILE
      sleep 3
  fi

  # If the mount does not exist yet, proceed
  if ! mount | grep $SECONDARYUNCDRIVE > /dev/null 2>&1; then

    # Check if the build supports modprobe
    if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
      modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
    fi

    # Mount the local backup drive directory to the UNC
    if [ "$SECONDARYBACKUPMEDIA" == "USB" ]; then
      echo -en "${CGreen}STATUS: Secondary External drive (USB) skipping mounting process.${CClear}"; printf "%s\n"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary External drive (USB) skipping mounting process." >> $LOGFILE
    else  
      CNT=0
      TRIES=3
        while [ $CNT -lt $TRIES ]; do # Loop through number of tries
          UNENCSECPWD=$(echo $SECONDARYPWD | openssl enc -d -base64 -A)
          mount -t cifs $SECONDARYUNC $SECONDARYUNCDRIVE -o "vers=${SMBVER},username=${SECONDARYUSER},password=${UNENCSECPWD}"  # Connect the UNC to the local backup drive mount
          MRC=$?
          if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
            echo -en "${CGreen}STATUS: Secondary external network drive ("; printf "%s" "${SECONDARYUNC}"; echo -en ") mounted successfully under: $SECONDARYUNCDRIVE ${CClear}"; printf "%s\n"
            printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary external network drive ( ${SECONDARYUNC} ) mounted successfully under: $SECONDARYUNCDRIVE" >> $LOGFILE
            break
          else
            echo -e "${CYellow}WARNING: Unable to mount to secondary external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
            sleep 10
            CNT=$((CNT+1))
            if [ $CNT -eq $TRIES ];then
              echo -e "${CRed}ERROR: Unable to mount to secondary external network drive. Please check your configuration. Exiting.${CClear}"
              logger "BACKUPMON ERROR: Unable to mount to secondary external network drive. Please check your configuration!"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to mount to secondary external network drive. Please check your configuration!" >> $LOGFILE
              sendmessage 1 "Unable to mount secondary network drive"
              echo -e "\n"
              exit 1
            fi
          fi
        done
    fi
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
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: No perpetual secondary backup folders older than $SECONDARYPURGELIMIT days were found. Nothing to delete." >> $LOGFILE
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountsecondarydrv

        return

      else

        echo -e "${CGreen}STATUS: Perpetual secondary backup folders older than $SECONDARYPURGELIMIT days deleted.${CClear}"
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountsecondarydrv

        return
      fi

  else

    echo -e "${CGreen}STATUS: Settling for 10 seconds..."
    sleep 10

    unmountsecondarydrv

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
    echo -e "${CRed}WARNING: BACKUPMON is not configured. Proceding with 1st time setup!"
    echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: BACKUPMON is not configured. Proceding with 1st time setup!" >> $LOGFILE
    sleep 3
    vconfig
  fi

  #Check to see if old conflicting variable names are being used
  if [ ! -z "$USERNAME" ]; then
    sed -i "s/USERNAME=/BTUSERNAME=/" "/jffs/addons/backupmon.d/backupmon.cfg"
    sed -i "s/PASSWORD=/BTPASSWORD=/" "/jffs/addons/backupmon.d/backupmon.cfg"
    source $CFGPATH
  fi

  updatecheck

  while true; do
    clear
    logoNM
    # Check for updates
    if [ "$UpdateNotify" != "0" ]; then
      echo -e "${CRed} $UpdateNotify"
    fi
    echo ""
    echo -e "${InvDkGray}${CWhite}                    Setup + Operations Menu                     ${CClear}"
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${CGreen}Backup Operations"
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
    echo -e "${InvDkGray}${CWhite} ep ${CClear}${CCyan}: Edit your Primary TAR Exclusion File"
    if [ $SECONDARYSTATUS -eq 1 ]; then
      echo -e "${InvDkGray}${CWhite} es ${CClear}${CCyan}: Edit your Secondary TAR Exclusion File"
    else
      echo -e "${InvDkGray}${CWhite} es ${CClear}${CDkGray}: Edit your Secondary TAR Exclusion File"
    fi
    echo ""
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${CGreen}Testing + Diagnostics Operations"
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${InvDkGray}${CWhite} ts ${CClear}${CCyan}: Test your Network Backup Target"
    echo -e "${InvDkGray}${CWhite} te ${CClear}${CCyan}: Test AMTM Email Communications"
    echo ""
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${CGreen}Setup + Configuration"
    echo -e "${CGreen}----------------------------------------------------------------"
    echo -e "${InvDkGray}${CWhite} sc ${CClear}${CCyan}: Setup and Configure BACKUPMON"
    echo -e "${InvDkGray}${CWhite} vl ${CClear}${CCyan}: View logs"
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
            #sh /jffs/scripts/backupmon.sh -backup
            if [ "$UpdateNotify" == "0" ]; then
              echo -e "${CGreen}BACKUPMON v$Version"
            else
              echo -e "${CGreen}BACKUPMON v$Version ${CRed}-- $UpdateNotify"
            fi
            echo ""
            echo -e "${CGreen}[Primary Backup Commencing]...          "
            echo ""
            echo -e "${CCyan}Messages:${CClear}"
            backup
            sendmessage 0 "Primary Backup completed successfully"
            secondary               #Run secondary backups
            if [ $SECONDARYSTATUS -eq 1 ]; then
              sendmessage 0 "Secondary Backup completed successfully"
            fi
          ;;

          rs)
            clear
            #sh /jffs/scripts/backupmon.sh -restore
            if [ "$UpdateNotify" == "0" ]; then
              echo -e "${CGreen}BACKUPMON v$Version"
            else
              echo -e "${CGreen}BACKUPMON v$Version ${CRed}-- $UpdateNotify"
            fi
            echo ""
            restore
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
          
          te)
            clear
            logoNM
            echo ""
            echo -e "${CCyan}This test assumes that you have AMTM Email set up correctly. If"
              echo -e "${CCyan}you still need to configure this feature, open up AMTM -> (em)"
              echo -e "${CCyan}to add your email server info, credentials, ports, protocols,"
              echo -e "${CCyan}and other pertinent info.${CClear}"
              echo ""
              echo -e "Would you like to send a TEST email from BACKUPMON?"
              if promptyn "(y/n): "; then
                echo ""

                if [ -f "$CUSTOM_EMAIL_LIBFile" ]
                  then
                    . "$CUSTOM_EMAIL_LIBFile"

                    if [ -z "${CEM_LIB_VERSION:+xSETx}" ] || \
                      _CheckLibraryUpdates_CEM_ "$CUSTOM_EMAIL_LIBDir" quiet
                    then
                      echo ""
                      _DownloadCEMLibraryFile_ "update"
                    fi
                  else
                    echo ""
                    _DownloadCEMLibraryFile_ "install"
                fi
                
                cemIsFormatHTML=true
                cemIsVerboseMode=true
                emailBodyTitle="Testing Email Notification"
                emailSubject="TEST: BACKUPMON Email Notification"
                tmpEMailBodyFile="/tmp/var/tmp/tmpEMailBody_${scriptFileNTag}.$$.TXT"

                {
                printf "This is a <b>TEST</b> to check & verify if sending email notifications is working well from <b>BACKUPMON</b>.\n"
                } > "$tmpEMailBodyFile"

                _SendEMailNotification_ "BACKUPMON v$Version" "$emailSubject" "$tmpEMailBodyFile" "$emailBodyTitle"

                echo ""
                read -rsp $'Press any key to acknowledge...\n' -n1 key
                
              fi
          ;;
          
          ep)
            export TERM=linux
            nano +999999 --linenumbers $EXCLUSION
          ;;
          
          es)
            if [ $SECONDARYSTATUS -eq 1 ]; then
              export TERM=linux
              nano +999999 --linenumbers $SECONDARYEXCLUSION
            fi
          ;;
          
          vl)
            echo ""
            vlogs
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
backup () {

  # Check to see if a leftover copy of backupmon.cfg is still sitting in /jffs/scripts and delete it
  rm -f /jffs/scripts/backupmon.cfg

  # Check to see if a local backup drive mount is available, if not, create one.
  if ! [ -d $UNCDRIVE ]; then
      mkdir -p $UNCDRIVE
      chmod 777 $UNCDRIVE
      echo -e "${CYellow}WARNING: External drive mount point not set. Newly created under: $UNCDRIVE ${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External drive mount point not set. Newly created under: $UNCDRIVE" >> $LOGFILE
      sleep 3
  fi

  # Check for the Swap File Exclusion
  if [ "$BACKUPSWAP" == "0" ]; then
    excludeswap
  fi

  # If everything successfully was created, proceed
  if ! mount | grep $UNCDRIVE > /dev/null 2>&1; then

      # Check the build to see if modprobe needs to be called
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      if [ "$BACKUPMEDIA" == "USB" ]; then
        echo -en "${CGreen}STATUS: External drive (USB) skipping mounting process.${CClear}"; printf "%s\n"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External drive (USB) skipping mounting process." >> $LOGFILE
      else
        CNT=0
        TRIES=3
          while [ $CNT -lt $TRIES ]; do # Loop through number of tries
            UNENCPWD=$(echo $BTPASSWORD | openssl enc -d -base64 -A)
            mount -t cifs $UNC $UNCDRIVE -o "vers=${SMBVER},username=${BTUSERNAME},password=${UNENCPWD}"  # Connect the UNC to the local backup drive mount
            MRC=$?
            if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
              break
            else
              echo -e "${CYellow}WARNING: Unable to mount to external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
              sleep 10
              CNT=$((CNT+1))
              if [ $CNT -eq $TRIES ];then
                echo -e "${CRed}ERROR: Unable to mount to external network drive. Please check your configuration. Exiting.${CClear}"
                logger "BACKUPMON ERROR: Unable to mount to external network drive. Please check your configuration!"
                echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to mount to external network drive. Please check your configuration!" >> $LOGFILE
                sendmessage 1 "Unable to mount network drive"
                echo -e "\n"
                exit 1
              fi
            fi
          done
      fi
  fi
  
  # Check to see if EXT USB is backing up to EXT USB
  if [ "$EXTDRIVE" == "$UNCDRIVE" ]; then
    BKDIREXCL=$(echo $BKDIR | sed 's/^.\{1\}//')
    if grep -q $BKDIREXCL $EXCLUSION; then
      echo -e "${CGreen}STATUS: **High Risk** -> EXT USB is backing up to EXT USB. TAR exclusion is in place.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: **High Risk** -> EXT USB is backing up to EXT USB. TAR exclusion is in place." >> $LOGFILE
    else
      echo -e "${CYellow}WARNING: **High Risk** -> EXT USB is backing up to EXT USB. TAR exclusion is missing!${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: **High Risk** -> EXT USB is backing up to EXT USB. TAR exclusion is missing!" >> $LOGFILE
    fi
  fi

  # If the local mount is connected to the UNC, proceed
  if [ -n "`mount | grep $UNCDRIVE`" ]; then
      if [ "$BACKUPMEDIA" == "USB" ]; then
        echo -en "${CGreen}STATUS: External drive (USB) mounted successfully as: $UNCDRIVE ${CClear}"; printf "%s\n"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External drive (USB) mounted successfully as: $UNCDRIVE" >> $LOGFILE
      else
        echo -en "${CGreen}STATUS: External network drive ("; printf "%s" "${UNC}"; echo -en ") mounted successfully under: $UNCDRIVE ${CClear}"; printf "%s\n"
        printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External network drive ( ${UNC} ) mounted successfully under: $UNCDRIVE" >> $LOGFILE
      fi
      
      # Create the backup directories and daily directories if they do not exist yet
      if ! [ -d "${UNCDRIVE}${BKDIR}" ]; then 
        mkdir -p "${UNCDRIVE}${BKDIR}" 
        echo -e "${CGreen}STATUS: Backup Directory successfully created."
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Backup Directory successfully created." >> $LOGFILE
      fi
      
      # Create frequency folders by week, month, year or perpetual
      if [ $FREQUENCY == "W" ]; then
        if ! [ -d "${UNCDRIVE}${BKDIR}/${WDAY}" ]
          then mkdir -p "${UNCDRIVE}${BKDIR}/${WDAY}"
          echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Daily Backup Directory successfully created." >> $LOGFILE
        fi
      elif [ $FREQUENCY == "M" ]; then
        if ! [ -d "${UNCDRIVE}${BKDIR}/${MDAY}" ]
          then mkdir -p "${UNCDRIVE}${BKDIR}/${MDAY}"
          echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Daily Backup Directory successfully created." >> $LOGFILE
        fi
      elif [ $FREQUENCY == "Y" ]; then
        if ! [ -d "${UNCDRIVE}${BKDIR}/${YDAY}" ]
          then mkdir -p "${UNCDRIVE}${BKDIR}/${YDAY}"
          echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Daily Backup Directory successfully created." >> $LOGFILE
        fi
      elif [ $FREQUENCY == "P" ]; then
        PDAY=$(date +"%Y%m%d-%H%M%S")
        if ! [ -d "${UNCDRIVE}${BKDIR}/${PDAY}" ]; then
          mkdir -p "${UNCDRIVE}${BKDIR}/${PDAY}"
          echo -e "${CGreen}STATUS: Daily Backup Directory successfully created.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Daily Backup Directory successfully created." >> $LOGFILE
        fi
      fi

      if [ $MODE == "Basic" ]; then
        # Remove old tar files if they exist in the daily folders
        if [ $FREQUENCY == "W" ]; then
          [ -f ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar*
          [ -f ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg* ] && rm ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg*
          [ -f ${UNCDRIVE}${BKDIR}/${WDAY}/routerfw.txt* ] && rm ${UNCDRIVE}${BKDIR}/${WDAY}/routerfw.txt*
          [ -f ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar*
        elif [ $FREQUENCY == "M" ]; then
          [ -f ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar*
          [ -f ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg* ] && rm ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg*
          [ -f ${UNCDRIVE}${BKDIR}/${MDAY}/routerfw.txt* ] && rm ${UNCDRIVE}${BKDIR}/${MDAY}/routerfw.txt*
          [ -f ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar*
        elif [ $FREQUENCY == "Y" ]; then
          [ -f ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar*
          [ -f ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg* ] && rm ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg*
          [ -f ${UNCDRIVE}${BKDIR}/${YDAY}/routerfw.txt* ] && rm ${UNCDRIVE}${BKDIR}/${YDAY}/routerfw.txt*
          [ -f ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar* ] && rm ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar*
        elif [ $FREQUENCY == "P" ]; then
          [ -f ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar* ] && rm ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar*
          [ -f ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg* ] && rm ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg*
          [ -f ${UNCDRIVE}${BKDIR}/${PDAY}/routerfw.txt* ] && rm ${UNCDRIVE}${BKDIR}/${PDAY}/routerfw.txt*
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
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz.${CClear}" 
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${WDAY}/jffs.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${UNCDRIVE}${BKDIR}/${WDAY}/routerfw.txt
          echo -e "${CGreen}STATUS: Finished copying ${CYellow}routerfw.txt${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/routerfw.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying routerfw.txt to ${UNCDRIVE}${BKDIR}/${WDAY}/routerfw.txt" >> $LOGFILE
          sleep 1

        elif [ $FREQUENCY == "M" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz.${CClear}" 
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${MDAY}/jffs.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${UNCDRIVE}${BKDIR}/${MDAY}/routerfw.txt
          echo -e "${CGreen}STATUS: Finished copying ${CYellow}routerfw.txt${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/routerfw.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying routerfw.txt to ${UNCDRIVE}${BKDIR}/${MDAY}/routerfw.txt" >> $LOGFILE
          sleep 1

        elif [ $FREQUENCY == "Y" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz.${CClear}" 
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${YDAY}/jffs.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${UNCDRIVE}${BKDIR}/${YDAY}/routerfw.txt
          echo -e "${CGreen}STATUS: Finished copying ${CYellow}routerfw.txt${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/routerfw.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying routerfw.txt to ${UNCDRIVE}${BKDIR}/${YDAY}/routerfw.txt" >> $LOGFILE
          sleep 1

        elif [ $FREQUENCY == "P" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
                    
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz.${CClear}" 
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${PDAY}/jffs.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${PDAY}/nvram.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${UNCDRIVE}${BKDIR}/${PDAY}/routerfw.txt
          echo -e "${CGreen}STATUS: Finished copying ${CYellow}routerfw.txt${CGreen} to ${UNCDRIVE}${BKDIR}/${PDAY}/routerfw.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying routerfw.txt to ${UNCDRIVE}${BKDIR}/${PDAY}/routerfw.txt" >> $LOGFILE
          sleep 1
        fi

        # If a TAR exclusion file exists, use it for the USB drive backup
        if [ "$EXTLABEL" != "NOTFOUND" ]; then
          echo -e "${CGreen}STATUS: Starting backup of ${CYellow}EXT Drive${CGreen} on $(date). Please stand by...${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Starting backup of EXT Drive on $(date)" >> $LOGFILE
          timerstart=$(date +%s)
          if [ $FREQUENCY == "W" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating JFFS tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart )) 
            logger "BACKUPMON INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "JFFS tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz.${CClear}"  
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            fi

          elif [ $FREQUENCY == "M" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart )) 
            logger "BACKUPMON INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz.${CClear}"  
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            fi

          elif [ $FREQUENCY == "Y" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart )) 
            logger "BACKUPMON INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz.${CClear}"  
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            fi

          elif [ $FREQUENCY == "P" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz.${CClear}"  
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${PDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            fi
          fi
        else
          echo -e "${CYellow}WARNING: External USB drive not found. Skipping backup."
          logger "BACKUPMON WARNING: External USB drive not found. Skipping backup."
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External USB drive not found. Skipping backup." >> $LOGFILE
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
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz.${CClear}"  
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${WDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${WDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram-${datelabel}.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${WDAY}/nvram-${datelabel}.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${UNCDRIVE}${BKDIR}/${WDAY}/routerfw-${datelabel}.txt
          echo -e "${CGreen}STATUS: Finished copying ${CYellow}routerfw.txt${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/routerfw-${datelabel}.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying routerfw.txt to ${UNCDRIVE}${BKDIR}/${WDAY}/routerfw-${datelabel}.txt" >> $LOGFILE
          sleep 1

        elif [ $FREQUENCY == "M" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz.${CClear}"  
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${MDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${MDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram-${datelabel}.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${MDAY}/nvram-${datelabel}.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${UNCDRIVE}${BKDIR}/${MDAY}/routerfw-${datelabel}.txt
          echo -e "${CGreen}STATUS: Finished copying ${CYellow}routerfw.txt${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/routerfw-${datelabel}.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying routerfw.txt to ${UNCDRIVE}${BKDIR}/${MDAY}/routerfw-${datelabel}.txt" >> $LOGFILE
          sleep 1

        elif [ $FREQUENCY == "Y" ]; then
          if ! [ -z $EXCLUSION ]; then
            tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz -X $EXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}JFFS${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up JFFS to ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz.${CClear}"  
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${YDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${UNCDRIVE}${BKDIR}/${YDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished backing up ${CYellow}NVRAM${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram-${datelabel}.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up NVRAM to ${UNCDRIVE}${BKDIR}/${YDAY}/nvram-${datelabel}.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${UNCDRIVE}${BKDIR}/${YDAY}/routerfw-${datelabel}.txt
          echo -e "${CGreen}STATUS: Finished copying ${CYellow}routerfw.txt${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/routerfw-${datelabel}.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying routerfw.txt to ${UNCDRIVE}${BKDIR}/${YDAY}/routerfw-${datelabel}.txt" >> $LOGFILE
          sleep 1
        fi

        # If a TAR exclusion file exists, use it for the USB drive backup
        if [ "$EXTLABEL" != "NOTFOUND" ]; then
          echo -e "${CGreen}STATUS: Starting backup of ${CYellow}EXT Drive${CGreen} on $(date). Please stand by...${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Starting backup of EXT Drive on $(date)" >> $LOGFILE
          timerstart=$(date +%s)
          if [ $FREQUENCY == "W" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}" 
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            fi

          elif [ $FREQUENCY == "M" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}" 
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            fi

          elif [ $FREQUENCY == "Y" ]; then
            if ! [ -z $EXCLUSION ]; then
              tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $EXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished backing up ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished backing up EXT Drive in $timertotal sec to ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}" 
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for ${UNCDRIVE}${BKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            fi
          fi
        else
          echo -e "${CYellow}WARNING: External USB drive not found. Skipping backup."
          logger "BACKUPMON WARNING: External USB drive not found. Skipping backup."
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External USB drive not found. Skipping backup." >> $LOGFILE
        fi
      fi

      #added copies of the backupmon.sh, backupmon.cfg, exclusions list and NVRAM to backup location for easy copy/restore
      cp /jffs/scripts/backupmon.sh ${UNCDRIVE}${BKDIR}/backupmon.sh
      echo -e "${CGreen}STATUS: Finished copying ${CYellow}backupmon.sh${CGreen} script to ${UNCDRIVE}${BKDIR}.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying backupmon.sh script to ${UNCDRIVE}${BKDIR}" >> $LOGFILE
      cp $CFGPATH ${UNCDRIVE}${BKDIR}/backupmon.cfg
      echo -e "${CGreen}STATUS: Finished copying ${CYellow}backupmon.cfg${CGreen} file to ${UNCDRIVE}${BKDIR}.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying backupmon.cfg file to ${UNCDRIVE}${BKDIR}" >> $LOGFILE

      if ! [ -z $EXCLUSION ]; then
        EXCLFILE=$(echo $EXCLUSION | sed 's:.*/::')
        cp $EXCLUSION ${UNCDRIVE}${BKDIR}/$EXCLFILE
        echo -e "${CGreen}STATUS: Finished copying ${CYellow}$EXCLFILE${CGreen} file to ${UNCDRIVE}${BKDIR}.${CClear}"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying $EXCLFILE file to ${UNCDRIVE}${BKDIR}" >> $LOGFILE
      fi

      #Please note: the nvram.txt export is for reference only. This file cannot be used to restore from, just to reference from.
      nvram show 2>/dev/null > ${UNCDRIVE}${BKDIR}/nvram.txt
      echo -e "${CGreen}STATUS: Finished copying reference ${CYellow}nvram.txt${CGreen} extract to ${UNCDRIVE}${BKDIR}.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying reference nvram.txt extract to ${UNCDRIVE}${BKDIR}" >> $LOGFILE
      
      #include restore instructions in the backup location
      { echo 'RESTORE INSTRUCTIONS'
        echo ''
        echo 'IMPORTANT:'
        echo 'Asus Router Model:' ${ROUTERMODEL}
        echo 'Firmware/Build Number:' ${FWBUILD}
        echo 'EXT USB Drive Label Name:' ${EXTLABEL}
        echo ''
        echo 'WARNING: Do NOT attempt to restore if your Asus Router Model or Firmware/Build Numbers differ from your backups!'
        echo ''
        echo 'Please ensure your have performed the following before restoring your backups:'
        echo '1.) Enable SSH in router UI, and connect via an SSH Terminal (like PuTTY).'
        echo '2.) Run "AMTM" and format a new USB drive on your router - label it exactly the same name as before (see above)! Reboot.'
        echo '3.) After reboot, SSH back in to AMTM, create your swap file (if required). This action should automatically enable JFFS.'
        echo '4.) From the UI, verify JFFS scripting enabled in the router OS, if not, enable and perform another reboot.'
        echo '5.) Restore the backupmon.sh & backupmon.cfg files (located under your backup folder) into your /jffs/scripts folder.'
        echo '6.) Run "sh backupmon.sh -setup" and ensure that all of the settings are correct before running a restore.'
        echo '7.) Run "sh backupmon.sh -restore", pick which backup you want to restore, and confirm before proceeding!'
        echo '8.) After the restore finishes, perform another reboot.  Everything should be restored as normal!'
      } > ${UNCDRIVE}${BKDIR}/instructions.txt
      echo -e "${CGreen}STATUS: Finished copying restoration ${CYellow}instructions.txt${CGreen} file to ${UNCDRIVE}${BKDIR}.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished copying restoration instructions.txt file to ${UNCDRIVE}${BKDIR}" >> $LOGFILE
      echo -e "${CGreen}STATUS: Settling for 10 seconds..."
      sleep 10

      # Unmount the locally connected mounted drive
      unmountdrv

  else

      # There's problems with mounting the drive - check paths and permissions!
      echo -e "${CRed}ERROR: Failed to run Backup Script -- Drive mount failed. Please check your configuration!${CClear}"
      logger "BACKUPMON ERROR: Failed to run Backup Script -- Drive mount failed. Please check your configuration!"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Failed to run Backup Script -- Drive mount failed. Please check your configuration!" >> $LOGFILE
      sleep 3

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# backup routine by @Jeffrey Young showing a great way to connect to an external network location to dump backups to
secondary () {

  if [ $SECONDARYSTATUS -eq 0 ]; then
    return
  fi

  # Run a secondary backup
  echo ""
  echo -e "${CGreen}[Secondary Backup Commencing]..."
  echo ""
  echo -e "${CCyan}Messages:${CClear}"

  # Check to see if a local backup drive mount is available, if not, create one.
  if ! [ -d $SECONDARYUNCDRIVE ]; then
      mkdir -p $SECONDARYUNCDRIVE
      chmod 777 $SECONDARYUNCDRIVE
      echo -e "${CYellow}WARNING: Secondary external mount point not set. Newly created under: $SECONDARYUNCDRIVE ${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: Secondary external mount point not set. Newly created under: $SECONDARYUNCDRIVE" >> $LOGFILE
      sleep 3
  fi

  # Check for the Swap File Exclusion
  if [ "$BACKUPSWAP" == "0" ]; then
    excludeswap
  fi

  # If everything successfully was created, proceed
  if ! mount | grep $SECONDARYUNCDRIVE > /dev/null 2>&1; then

      # Check the build to see if modprobe needs to be called
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      if [ "$SECONDARYBACKUPMEDIA" == "USB" ]; then
        echo -en "${CGreen}STATUS: Secondary external drive (USB) skipping mounting process.${CClear}"; printf "%s\n"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary external drive (USB) skipping mounting process." >> $LOGFILE
      else
        CNT=0
        TRIES=3
          while [ $CNT -lt $TRIES ]; do # Loop through number of tries
            UNENCSECPWD=$(echo $SECONDARYPWD | openssl enc -d -base64 -A)
            mount -t cifs $SECONDARYUNC $SECONDARYUNCDRIVE -o "vers=${SMBVER},username=${SECONDARYUSER},password=${UNENCSECPWD}"  # Connect the UNC to the local backup drive mount
            MRC=$?
            if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
              break
            else
              echo -e "${CYellow}WARNING: Unable to mount to secondary external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
              sleep 10
              CNT=$((CNT+1))
              if [ $CNT -eq $TRIES ];then
                echo -e "${CRed}ERROR: Unable to mount to secondary external network drive. Please check your configuration. Exiting.${CClear}"
                logger "BACKUPMON ERROR: Unable to mount to secondary external network drive. Please check your configuration!"
                echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to mount to secondary external network drive. Please check your configuration!" >> $LOGFILE
                sendmessage 1 "Unable to mount secondary network drive"
                echo -e "\n"
                exit 1
              fi
            fi
          done
      fi
  fi

  # Check to see if EXT USB is backing up to EXT USB
  if [ "$EXTDRIVE" == "$SECONDARYUNCDRIVE" ]; then
    SECONDARYBKDIREXCL=$(echo $SECONDARYBKDIR | sed 's/^.\{1\}//')
    if grep -q $SECONDARYBKDIREXCL $SECONDARYEXCLUSION; then
      echo -e "${CGreen}STATUS: **High Risk** -> EXT USB is backing up to EXT USB. TAR exclusion is in place.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: **High Risk** -> EXT USB is backing up to EXT USB. TAR exclusion is in place." >> $LOGFILE
    else
      echo -e "${CYellow}WARNING: **High Risk** -> EXT USB is backing up to EXT USB. TAR exclusion is missing!${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: **High Risk** -> EXT USB is backing up to EXT USB. TAR exclusion is missing!" >> $LOGFILE
    fi
  fi

  # If the local mount is connected to the UNC, proceed
  if [ -n "`mount | grep $SECONDARYUNCDRIVE`" ]; then

      if [ "$SECONDARYBACKUPMEDIA" == "USB" ]; then
        echo -en "${CGreen}STATUS: Secondary external drive (USB) mounted successfully as: $SECONDARYUNCDRIVE ${CClear}"; printf "%s\n"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary external drive (USB) mounted successfully as: $SECONDARYUNCDRIVE" >> $LOGFILE
      else
        echo -en "${CGreen}STATUS: Secondary external network drive ("; printf "%s" "${SECONDARYUNC}"; echo -en ") mounted successfully under: $SECONDARYUNCDRIVE ${CClear}"; printf "%s\n"
        printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary external network drive ( ${SECONDARYUNC} ) mounted successfully under: $SECONDARYUNCDRIVE" >> $LOGFILE
      fi

      # Create the secondary backup directories and daily directories if they do not exist yet
      if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}" ]; then 
        mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}"
        echo -e "${CGreen}STATUS: Secondary Backup Directory successfully created."
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary Backup Directory successfully created." >> $LOGFILE
      fi

      # Create frequency folders by week, month, year or perpetual
      if [ $SECONDARYFREQUENCY == "W" ]; then
        if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}" ]; then
          mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}"
          echo -e "${CGreen}STATUS: Daily Secondary Backup Directory successfully created.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Daily Secondary Backup Directory successfully created." >> $LOGFILE
        fi
      elif [ $SECONDARYFREQUENCY == "M" ]; then
        if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}" ]; then
          mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}"
          echo -e "${CGreen}STATUS: Daily Secondary Backup Directory successfully created.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Daily Secondary Backup Directory successfully created." >> $LOGFILE
        fi
      elif [ $SECONDARYFREQUENCY == "Y" ]; then
        if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}" ]; then
          mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}"
          echo -e "${CGreen}STATUS: Daily Secondary Backup Directory successfully created.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Daily Secondary Backup Directory successfully created." >> $LOGFILE
        fi
      elif [ $SECONDARYFREQUENCY == "P" ]; then
        PDAY=$(date +"%Y%m%d-%H%M%S")
        if ! [ -d "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}" ]; then
          mkdir -p "${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}"
          echo -e "${CGreen}STATUS: Daily Secondary Backup Directory successfully created.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Daily Secondary Backup Directory successfully created." >> $LOGFILE
        fi
      fi

      if [ $SECONDARYMODE == "Basic" ]; then
        # Remove old tar files if they exist in the daily folders
        if [ $SECONDARYFREQUENCY == "W" ]; then
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/routerfw.txt* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/routerfw.txt*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar*
        elif [ $SECONDARYFREQUENCY == "M" ]; then
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/routerfw.txt* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/routerfw.txt*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar*
        elif [ $SECONDARYFREQUENCY == "Y" ]; then
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/routerfw.txt* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/routerfw.txt*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar*
        elif [ $SECONDARYFREQUENCY == "P" ]; then
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg*
          [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/routerfw.txt* ] && rm ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/routerfw.txt*
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
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating secondary JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in Secondary JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in Secondary JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz.${CClear}" 
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/routerfw.txt
          echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}routerfw.txt${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/routerfw.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of routerfw.txt to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/routerfw.txt" >> $LOGFILE
          sleep 1

        elif [ $SECONDARYFREQUENCY == "M" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating secondary JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in Secondary JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in Secondary JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz.${CClear}" 
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/routerfw.txt
          echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}routerfw.txt${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/routerfw.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of routerfw.txt to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/routerfw.txt" >> $LOGFILE
          sleep 1

        elif [ $SECONDARYFREQUENCY == "Y" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating secondary JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in Secondary JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in Secondary JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz.${CClear}" 
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/routerfw.txt
          echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}routerfw.txt${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/routerfw.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of routerfw.txt to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/routerfw.txt" >> $LOGFILE
          sleep 1

        elif [ $SECONDARYFREQUENCY == "P" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating secondary JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in Secondary JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in Secondary JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz.${CClear}" 
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/jffs.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/nvram.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/routerfw.txt
          echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}routerfw.txt${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/routerfw.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of routerfw.txt to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/routerfw.txt" >> $LOGFILE
          sleep 1

        fi

        # If a TAR exclusion file exists, use it for the USB drive backup
        if [ "$EXTLABEL" != "NOTFOUND" ]; then
          echo -e "${CGreen}STATUS: Starting secondary backup of ${CYellow}EXT Drive${CGreen} on $(date). Please stand by...${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Starting secondary backup of EXT Drive on $(date)" >> $LOGFILE
          timerstart=$(date +%s)
          if [ $SECONDARYFREQUENCY == "W" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating secondary EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating JFFS tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in secondary EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in secondary EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "JFFS tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz.${CClear}"  
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            fi

          elif [ $SECONDARYFREQUENCY == "M" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating secondary EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in secondary EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in secondary EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz.${CClear}"  
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            fi

          elif [ $SECONDARYFREQUENCY == "Y" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating secondary EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in secondary EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in secondary EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz.${CClear}"  
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            fi

          elif [ $SECONDARYFREQUENCY == "P" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating secondary EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in secondary EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in secondary EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz.${CClear}"  
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${PDAY}/${EXTLABEL}.tar.gz" >> $LOGFILE
            fi
          fi
        else
          echo -e "${CYellow}WARNING: External USB drive not found. Skipping backup."
          logger "BACKUPMON WARNING: External USB drive not found. Skipping backup."
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External USB drive not found. Skipping backup." >> $LOGFILE
        fi

      elif [ $SECONDARYMODE == "Advanced" ]; then

        datelabel=$(date +"%Y%m%d-%H%M%S")
        # If a TAR exclusion file exists, use it for the /jffs backup
        if [ $SECONDARYFREQUENCY == "W" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating secondary JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating EXT USB tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in Secondary JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in Secondary JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "EXT USB tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz.${CClear}"  
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram-${datelabel}.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/nvram-${datelabel}.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/routerfw-${datelabel}.txt
          echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}routerfw.txt${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/routerfw-${datelabel}.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of routerfw.txt to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/routerfw-${datelabel}.txt" >> $LOGFILE
          sleep 1

        elif [ $SECONDARYFREQUENCY == "M" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating secondary JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in Secondary JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in Secondary JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz.${CClear}"  
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram-${datelabel}.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/nvram-${datelabel}.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/routerfw-${datelabel}.txt
          echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}routerfw.txt${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/routerfw-${datelabel}.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of routerfw.txt to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/routerfw-${datelabel}.txt" >> $LOGFILE
          sleep 1

        elif [ $SECONDARYFREQUENCY == "Y" ]; then
          if ! [ -z $SECONDARYEXCLUSION ]; then
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C /jffs . >/dev/null
          else
            tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz -C /jffs . >/dev/null
          fi
          TE=$?
          if [ $TE -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected creating secondary JFFS tar file. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary JFFS tar file." >> $LOGFILE
            sendmessage 1 "Error creating JFFS tar file"
            echo -e "\n"
            exit 1
          fi
          
          logger "BACKUPMON INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}JFFS${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of JFFS to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          sleep 1

          #Verify file integrity
          tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz >/dev/null
          TI=$?
          if [ $TI -ne 0 ]; then
            echo -e "${CRed}ERROR: Errors detected in Secondary JFFS tar file integrity. Exiting Script!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in Secondary JFFS tar file integrity. Exiting." >> $LOGFILE
            sendmessage 1 "JFFS tar file integrity failure"
            echo -e "\n"
            exit 1
          elif [ $TI -eq 0 ]; then
            echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz.${CClear}"  
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/jffs-${datelabel}.tar.gz" >> $LOGFILE
          fi

          #Save a copy of the NVRAM
          nvram save ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram-${datelabel}.cfg >/dev/null 2>&1
          logger "BACKUPMON INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram-${datelabel}.cfg"
          echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}NVRAM${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram-${datelabel}.cfg.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of NVRAM to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/nvram-${datelabel}.cfg" >> $LOGFILE
          sleep 1

          #include current router model/firmware/build info in the backup location
          { echo 'RESTOREMODEL="'"$ROUTERMODEL"'"'
            echo 'RESTOREBUILD="'"$FWBUILD"'"'
          } > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/routerfw-${datelabel}.txt
          echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}routerfw.txt${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/routerfw-${datelabel}.txt.${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of routerfw.txt to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/routerfw-${datelabel}.txt" >> $LOGFILE
          sleep 1
        fi

        # If a TAR exclusion file exists, use it for the USB drive backup
        if [ "$EXTLABEL" != "NOTFOUND" ]; then
          echo -e "${CGreen}STATUS: Starting secondary backup of ${CYellow}EXT Drive${CGreen} on $(date). Please stand by...${CClear}"
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Starting secondary backup of EXT Drive on $(date)" >> $LOGFILE
          timerstart=$(date +%s)
          if [ $SECONDARYFREQUENCY == "W" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating secondary EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in secondary EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in secondary EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}" 
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${WDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            fi

          elif [ $SECONDARYFREQUENCY == "M" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating secondary EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in secondary EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in secondary EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}" 
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${MDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            fi

          elif [ $SECONDARYFREQUENCY == "Y" ]; then
            if ! [ -z $SECONDARYEXCLUSION ]; then
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz -X $SECONDARYEXCLUSION -C $EXTDRIVE . >/dev/null
            else
              tar -zcf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz -C $EXTDRIVE . >/dev/null
            fi
            TE=$?
            if [ $TE -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected creating secondary EXT Drive tar file. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected creating secondary EXT Drive tar file." >> $LOGFILE
              sendmessage 1 "Error creating EXT USB tar file"
              echo -e "\n"
              exit 1
            fi
            
            timerend=$(date +%s); timertotal=$(( timerend - timerstart ))
            logger "BACKUPMON INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz"
            echo -e "${CGreen}STATUS: Finished secondary backup of ${CYellow}EXT Drive${CGreen} in ${CYellow}$timertotal sec${CGreen} to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary backup of EXT Drive in $timertotal sec to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            sleep 1
            
            #Verify file integrity
            tar -tzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz >/dev/null
            TI=$?
            if [ $TI -ne 0 ]; then
              echo -e "${CRed}ERROR: Errors detected in secondary EXT Drive tar file integrity. Exiting Script!${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Errors detected in secondary EXT Drive tar file integrity. Exiting." >> $LOGFILE
              sendmessage 1 "EXT USB tar file integrity failure"
              echo -e "\n"
              exit 1
            elif [ $TI -eq 0 ]; then
              echo -e "${CGreen}STATUS: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz.${CClear}" 
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished integrity check for secondary ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${YDAY}/${EXTLABEL}-${datelabel}.tar.gz" >> $LOGFILE
            fi
          fi
        else
          echo -e "${CYellow}WARNING: External USB drive not found. Skipping backup."
          logger "BACKUPMON WARNING: External USB drive not found. Skipping backup."
          echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External USB drive not found. Skipping backup." >> $LOGFILE
        fi
      fi

      #added copies of the backupmon.sh, backupmon.cfg, exclusions list and NVRAM to backup location for easy copy/restore
      cp /jffs/scripts/backupmon.sh ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/backupmon.sh
      echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}backupmon.sh${CGreen} script to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of backupmon.sh script to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}" >> $LOGFILE
      cp $CFGPATH ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/backupmon.cfg
      echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}backupmon.cfg${CGreen} file to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of backupmon.cfg file to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}" >> $LOGFILE

      if ! [ -z $SECONDARYEXCLUSION ]; then
        EXCLFILE=$(echo $SECONDARYEXCLUSION | sed 's:.*/::')
        cp $SECONDARYEXCLUSION ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/$EXCLFILE
        echo -e "${CGreen}STATUS: Finished secondary copy of ${CYellow}$EXCLFILE${CGreen} file to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of $EXCLFILE file to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}" >> $LOGFILE
      fi

      #Please note: the nvram.txt export is for reference only. This file cannot be used to restore from, just to reference from.
      nvram show 2>/dev/null > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/nvram.txt
      echo -e "${CGreen}STATUS: Finished secondary reference copy of ${CYellow}nvram.txt${CGreen} extract to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary reference copy of nvram.txt extract to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}" >> $LOGFILE

      #include restore instructions in the backup location
      { echo 'RESTORE INSTRUCTIONS'
        echo ''
        echo 'IMPORTANT:'
        echo 'Asus Router Model:' ${ROUTERMODEL}
        echo 'Firmware/Build Number:' ${FWBUILD}
        echo 'EXT USB Drive Label Name:' ${EXTLABEL}
        echo ''
        echo 'WARNING: Do NOT attempt to restore if your Asus Router Model or Firmware/Build Numbers differ from your backups!'
        echo ''
        echo 'Please ensure your have performed the following before restoring your backups:'
        echo '1.) Enable SSH in router UI, and connect via an SSH Terminal (like PuTTY).'
        echo '2.) Run "AMTM" and format a new USB drive on your router - label it exactly the same name as before (see above)! Reboot.'
        echo '3.) After reboot, SSH back in to AMTM, create your swap file (if required). This action should automatically enable JFFS.'
        echo '4.) From the UI, verify JFFS scripting enabled in the router OS, if not, enable and perform another reboot.'
        echo '5.) Restore the backupmon.sh & backupmon.cfg files (located under your backup folder) into your /jffs/scripts folder.'
        echo '6.) Run "sh backupmon.sh -setup" and ensure that all of the settings are correct before running a restore.'
        echo '7.) Run "sh backupmon.sh -restore", pick which backup you want to restore, and confirm before proceeding!'
        echo '8.) After the restore finishes, perform another reboot.  Everything should be restored as normal!'
      } > ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/instructions.txt
      echo -e "${CGreen}STATUS: Finished secondary copy of restoration ${CYellow}instructions.txt${CGreen} file to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}.${CClear}"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Finished secondary copy of restoration instructions.txt file to ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}" >> $LOGFILE
      echo -e "${CGreen}STATUS: Settling for 10 seconds..."
      sleep 10

      # Unmount the locally connected mounted drive
      unmountsecondarydrv

  else

      # There's problems with mounting the drive - check paths and permissions!
      echo -e "${CRed}ERROR: Failed to run Secondary Backup Script -- Drive mount failed. Please check your configuration!${CClear}"
      logger "BACKUPMON ERROR: Failed to run Secondary Backup Script -- Drive mount failed. Please check your configuration!"
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Failed to run Secondary Backup Script -- Drive mount failed. Please check your configuration!" >> $LOGFILE
      sleep 3

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# restore function is a routine that allows you to pick a backup to be restored
restore () {

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
  echo -e "${CGreen}2.) Run 'AMTM' and format a new USB drive on your router - label it exactly the same name as before! Reboot."
  echo -e "${CYellow}    (please refer to your restore instruction.txt file to find your original EXT USB drive label)"
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
          "" ) echo -e "\nError: Please use either P or S.\n";;
          * ) echo -e "\nError: Please use either P or S.\n";;
        esac
    done
  else
    SOURCE="Primary"
  fi

  echo -e "${CCyan}Messages:${CClear}"

  if [ "$SOURCE" == "Primary" ]; then

    # Create the local backup drive mount directory
    if ! [ -d $UNCDRIVE ]; then
        mkdir -p $UNCDRIVE
        chmod 777 $UNCDRIVE
        echo -e "${CYellow}WARNING: External drive mount point not set. Created under: $UNCDRIVE ${CClear}"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External drive mount point not set. Created under: $UNCDRIVE" >> $LOGFILE
        sleep 3
    fi

    # If the mount does not exist yet, proceed
    if ! mount | grep $UNCDRIVE > /dev/null 2>&1; then

      # Check if the build supports modprobe
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      # Mount the local backup drive directory to the UNC
      if [ "$BACKUPMEDIA" == "USB" ]; then
        echo -en "${CGreen}STATUS: External drive (USB) skipping mounting process.${CClear}"; printf "%s\n"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External drive (USB) skipping mounting process." >> $LOGFILE
      else
        CNT=0
        TRIES=3
          while [ $CNT -lt $TRIES ]; do # Loop through number of tries
            UNENCPWD=$(echo $BTPASSWORD | openssl enc -d -base64 -A)
            mount -t cifs $UNC $UNCDRIVE -o "vers=${SMBVER},username=${BTUSERNAME},password=${UNENCPWD}"  # Connect the UNC to the local backup drive mount
            MRC=$?
            if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
              echo -en "${CGreen}STATUS: External network drive ("; printf "%s" "${UNC}"; echo -en ") mounted successfully under: $UNCDRIVE ${CClear}"; printf "%s\n"
              printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External network drive ( ${UNC} ) mounted successfully under: $UNCDRIVE" >> $LOGFILE
              break
            else
              echo -e "${CYellow}WARNING: Unable to mount to external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
              sleep 10
              CNT=$((CNT+1))
              if [ $CNT -eq $TRIES ];then
                echo -e "${CRed}ERROR: Unable to mount to external network drive. Please check your configuration. Exiting.${CClear}"
                logger "BACKUPMON ERROR: Unable to mount to external network drive. Please check your configuration!"
                echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to mount to external network drive. Please check your configuration!" >> $LOGFILE
                sendmessage 1 "Unable to mount secondary network drive"
                echo -e "\n"
                exit 1
              fi
            fi
          done
      fi
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
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountdrv; echo -e "${CClear}"; return; fi
                if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "M" ]; then
                echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 02 or 27) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountdrv; echo -e "${CClear}"; return; fi
                if [ ${#BACKUPDATE1} -gt 2 ] || [ ${#BACKUPDATE1} -lt 2 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 2 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "Y" ]; then
                echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 002 or 270) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountdrv; echo -e "${CClear}"; return; fi
                if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "P" ]; then
                echo -e "${CGreen}Enter the exact folder name of the backup you wish to restore? (ex: 20230909-083422) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountdrv; echo -e "${CClear}"; return; fi
                if [ ${#BACKUPDATE1} -gt 15 ] || [ ${#BACKUPDATE1} -lt 15 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 15 characters for the folder name format"; echo ""
                else
                  ok=1
                fi
              fi
            done

            if [ -z "$BACKUPDATE1" ]; then 
              echo ""
              echo -e "${CRed}ERROR: Invalid backup set chosen. Exiting script...${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Invalid backup set chosen. Exiting script..." >> $LOGFILE
              echo ""
              exit 1
            else 
              BACKUPDATE=$BACKUPDATE1
            fi

            if [ $MODE == "Basic" ]; then
              if [ -f ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/routerfw.txt ]; then
                source ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/routerfw.txt
              fi
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
                echo ""
                echo -e "${CGreen}Enter the EXACT file name (including extensions) of the routerfw.txt file to be referenced?${CClear}"
                read ADVRTRFW
                if [ -f ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVRTRFW} ]; then
                  source ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVRTRFW}
                fi
                break
              fi
            fi
        done

        # Determine router model
        [ -z "$(nvram get odmpid)" ] && ROUTERMODEL="$(nvram get productid)" || ROUTERMODEL="$(nvram get odmpid)" # Thanks @thelonelycoder for this logic

        if [ ! -z $RESTOREMODEL ]; then
          if [ "$ROUTERMODEL" != "$RESTOREMODEL" ]; then
            echo ""
            echo -e "${CRed}ERROR: Original source router model is different from target router model."
            echo -e "${CRed}ERROR: Restorations can only be performed on the same source/target router model or you may brick your router!"
            echo -e "${CRed}ERROR: If you are certain source/target routers are the same, please check and re-save your configuration!${CClear}"
            logger "BACKUPMON ERROR: Original source router model is different from target router model. Please check your configuration!"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Original source router model is different from target router model. Please check your configuration!" >> $LOGFILE
            echo ""
            echo -e "${CGreen}Would you like to continue to restore from backup?"
            if promptyn "(y/n): "; then
              echo ""
              echo ""
              echo -e "${CYellow}WARNING: Continuing restore using backup saved from a different source router model.${CClear}"
              echo -e "${CYellow}WARNING: This may have disastrous effects on the operation and stabiliity of your router.${CClear}"
              echo -e "${CYellow}WARNING: By continuing, you accept full responsibility for these actions.${CClear}"
            else
              exit 0
            fi
          fi
        fi

        # Determine mismatched firmware
        if [ ! -z $RESTOREBUILD ]; then
          if [ "$FWBUILD" != "$RESTOREBUILD" ]; then
            echo ""
            echo -e "${CRed}ERROR: Original source router firmware/build is different from target router firmware/build."
            echo -e "${CRed}ERROR: Restorations can only be performed on the same router firmware/build or you may brick your router!"
            echo -e "${CRed}ERROR: If you are certain router firmware/build is the same, please check and re-save your configuration!${CClear}"
            logger "BACKUPMON ERROR: Original source router firmware/build is different from target router firmware/build. Please check your configuration!"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Original source router firmware/build is different from target router firmware/build. Please check your configuration!" >> $LOGFILE
            echo ""
            echo -e "${CGreen}Would you like to continue to restore from backup?"
            if promptyn "(y/n): "; then
              echo ""
              echo ""
              echo -e "${CYellow}WARNING: Continuing restore using backup saved with older router firmware/build.${CClear}"
              echo -e "${CYellow}WARNING: This may have disastrous effects on the operation and stabiliity of your router.${CClear}"
              echo -e "${CYellow}WARNING: By continuing, you accept full responsibility for these actions.${CClear}"
            else
              exit 0
            fi
          fi
        fi

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
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz to /jffs" >> $LOGFILE
            tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/jffs.tar.gz -C /jffs >/dev/null
            if [ "$EXTLABEL" != "NOTFOUND" ]; then
              echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz to $EXTDRIVE${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz to $EXTDRIVE" >> $LOGFILE
              tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz -C $EXTDRIVE >/dev/null
              TE=$?
              if [ $TE -eq 0 ]; then
                echo -e "${CGreen}No TAR errors detected on restore to $EXTDRIVE${CClear}"
              else
                echo -e "${CRed}ERROR: TAR errors detected on restore to $EXTDRIVE${CClear}"
                echo -e "${CRed}Would you like to proceed with the restoration process?${CClear}"
                echo ""
                if promptyn "(y/n): "; then
                  echo ""
                  echo -e "\n${CGreen}Proceeding...${CClear}\n"
                  sleep 1
                else
                  echo ""
                  echo -e "${CRed}Exiting...${CClear}\n"
                  echo ""
                  exit 1
                fi
              fi
            else
              echo -e "${CYellow}WARNING: External USB drive not found. Skipping restore."
              logger "BACKUPMON WARNING: External USB drive not found. Skipping restore."
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External USB drive not found. Skipping restore." >> $LOGFILE
            fi
            echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/nvram.cfg to NVRAM${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/nvram.cfg to NVRAM" >> $LOGFILE
            nvram restore ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/nvram.cfg >/dev/null 2>&1
            echo ""
            echo -e "${CGreen}STATUS: Backups were successfully restored to their original locations. Forcing reboot now!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Backups were successfully restored to their original locations. Forcing reboot!" >> $LOGFILE
            echo ""
            rm -f /jffs/scripts/backupmon.cfg
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
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVJFFS} to /jffs" >> $LOGFILE
            tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVJFFS} -C /jffs >/dev/null
            if [ "$EXTLABEL" != "NOTFOUND" ]; then
              echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVUSB} to $EXTDRIVE${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVUSB} to $EXTDRIVE" >> $LOGFILE
              tar -xzf ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVUSB} -C $EXTDRIVE >/dev/null
              TE=$?
              if [ $TE -eq 0 ]; then
                echo -e "${CGreen}No TAR errors detected on restore to $EXTDRIVE${CClear}"
              else
                echo -e "${CRed}ERROR: TAR errors detected on restore to $EXTDRIVE${CClear}"
                echo -e "${CRed}Would you like to proceed with the restoration process?${CClear}"
                echo ""
                if promptyn "(y/n): "; then
                  echo ""
                  echo -e "\n${CGreen}Proceeding...${CClear}\n"
                else
                  echo ""
                  echo -e "${CRed}Exiting...${CClear}\n"
                  echo ""
                  exit 1
                fi
              fi
            else
              echo -e "${CYellow}WARNING: External USB drive not found. Skipping restore."
              logger "BACKUPMON WARNING: External USB drive not found. Skipping restore."
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External USB drive not found. Skipping restore." >> $LOGFILE
            fi
            echo -e "${CGreen}Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVNVRAM} to NVRAM${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVNVRAM} to NVRAM" >> $LOGFILE
            nvram restore ${UNCDRIVE}${BKDIR}/${BACKUPDATE}/${ADVNVRAM} >/dev/null 2>&1
            echo ""
            echo -e "${CGreen}STATUS: Backups were successfully restored to their original locations. Forcing reboot now!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Backups were successfully restored to their original locations. Forcing reboot!" >> $LOGFILE
            echo ""
            rm -f /jffs/scripts/backupmon.cfg
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
        return

      else

        # Exit gracefully
        echo ""
        echo ""
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountdrv

        echo -e "${CClear}"
        return

      fi

    else

      # Exit gracefully
      echo ""
      echo ""
      echo -e "${CGreen}STATUS: Settling for 10 seconds..."
      sleep 10

      unmountdrv

      echo -e "${CClear}"
      return

    fi

  elif [ "$SOURCE" == "Secondary" ]; then

    # Create the local backup drive mount directory
    if ! [ -d $SECONDARYUNCDRIVE ]; then
        mkdir -p $SECONDARYUNCDRIVE
        chmod 777 $SECONDARYUNCDRIVE
        echo -e "${CYellow}WARNING: Secondary External drive mount point not set. Created under: $SECONDARYUNCDRIVE ${CClear}"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: Secondary External drive mount point not set. Created under: $SECONDARYUNCDRIVE" >> $LOGFILE
        sleep 3
    fi

    # If the mount does not exist yet, proceed
    if ! mount | grep $SECONDARYUNCDRIVE > /dev/null 2>&1; then

      # Check if the build supports modprobe
      if [ $(find /lib -name md4.ko | wc -l) -gt 0 ]; then
        modprobe md4 > /dev/null    # Required now by some 388.x firmware for mounting remote drives
      fi

      # Mount the local backup drive directory to the Secondary UNC
      if [ "$SECONDARYBACKUPMEDIA" == "USB" ]; then
        echo -en "${CGreen}STATUS: Secondary external drive (USB) skipping mounting process.${CClear}"; printf "%s\n"
        echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary external drive (USB) skipping mounting process." >> $LOGFILE
      else
        CNT=0
        TRIES=3
          while [ $CNT -lt $TRIES ]; do # Loop through number of tries
            UNENCSECPWD=$(echo $SECONDARYPWD | openssl enc -d -base64 -A)
            mount -t cifs $SECONDARYUNC $SECONDARYUNCDRIVE -o "vers=${SMBVER},username=${SECONDARYUSER},password=${UNENCSECPWD}"  # Connect the UNC to the local backup drive mount
            MRC=$?
            if [ $MRC -eq 0 ]; then  # If mount come back successful, then proceed
              echo -en "${CGreen}STATUS: External secondary network drive ("; printf "%s" "${SECONDARYUNC}"; echo -en ") mounted successfully under: $SECONDARYUNCDRIVE ${CClear}"; printf "%s\n"
              printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External secondary network drive ( ${SECONDARYUNC} ) mounted successfully under: $SECONDARYUNCDRIVE" >> $LOGFILE
              break
            else
              echo -e "${CYellow}WARNING: Unable to mount to secondary external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
              sleep 10
              CNT=$((CNT+1))
              if [ $CNT -eq $TRIES ];then
                echo -e "${CRed}ERROR: Unable to mount to secondary external network drive. Please check your configuration. Exiting.${CClear}"
                logger "BACKUPMON ERROR: Unable to mount to secondary external network drive. Please check your configuration!"
                echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to mount to secondary external network drive. Please check your configuration!" >> $LOGFILE
                sendmessage 1 "Unable to mount secondary network drive"
                echo -e "\n"
                exit 1
              fi
            fi
          done
      fi
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
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountsecondarydrv; echo -e "${CClear}"; return; fi
                if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "M" ]; then
                echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 02 or 27) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountsecondarydrv; echo -e "${CClear}"; return; fi
                if [ ${#BACKUPDATE1} -gt 2 ] || [ ${#BACKUPDATE1} -lt 2 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 2 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "Y" ]; then
                echo -e "${CGreen}Enter the Day # of the backup you wish to restore? (ex: 002 or 270) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountsecondarydrv; echo -e "${CClear}"; return; fi
                if [ ${#BACKUPDATE1} -gt 3 ] || [ ${#BACKUPDATE1} -lt 3 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 3 characters for the day format"; echo ""
                else
                  ok=1
                fi
              elif [ $FREQUENCY == "P" ]; then
                echo -e "${CGreen}Enter the exact folder name of the backup you wish to restore? (ex: 20230909-083422) (e=Exit): "
                read BACKUPDATE1
                if [ $BACKUPDATE1 == "e" ]; then echo ""; echo -e "${CGreen}STATUS: Settling for 10 seconds..."; sleep 10; unmountsecondarydrv; echo -e "${CClear}"; return; fi
                if [ ${#BACKUPDATE1} -gt 15 ] || [ ${#BACKUPDATE1} -lt 15 ]
                then
                  echo -e "${CRed}ERROR: Invalid entry. Please use 15 characters for the folder name format"; echo ""
                else
                  ok=1
                fi
              fi
            done

            if [ -z "$BACKUPDATE1" ]; then
              echo ""
              echo -e "${CRed}ERROR: Invalid backup set chosen. Exiting script...${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Invalid backup set chosen. Exiting script..." >> $LOGFILE
              echo ""
              exit 1
            else 
              BACKUPDATE=$BACKUPDATE1
            fi

            if [ $SECONDARYMODE == "Basic" ]; then
              if [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/routerfw.txt ]; then
                source ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/routerfw.txt
              fi
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
                echo ""
                echo -e "${CGreen}Enter the EXACT file name (including extensions) of the routerfw.txt file to be referenced?${CClear}"
                read ADVRTRFW
                if [ -f ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVRTRFW} ]; then
                  source ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVRTRFW}
                fi
                break
              fi
            fi
        done

        # Determine router model
        [ -z "$(nvram get odmpid)" ] && ROUTERMODEL="$(nvram get productid)" || ROUTERMODEL="$(nvram get odmpid)" # Thanks @thelonelycoder for this logic

        if [ ! -z $RESTOREMODEL ]; then
          if [ "$ROUTERMODEL" != "$RESTOREMODEL" ]; then
            echo ""
            echo -e "${CRed}ERROR: Original source router model is different from target router model."
            echo -e "${CRed}ERROR: Restorations can only be performed on the same source/target router model or you may brick your router!"
            echo -e "${CRed}ERROR: If you are certain source/target routers are the same, please check and re-save your configuration!${CClear}"
            logger "BACKUPMON ERROR: Original source router model is different from target router model. Please check your configuration!"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Original source router model is different from target router model. Please check your configuration!" >> $LOGFILE
            echo ""
            echo -e "${CGreen}Would you like to continue to restore from backup?"
            if promptyn "(y/n): "; then
              echo ""
              echo ""
              echo -e "${CYellow}WARNING: Continuing restore using backup saved from a different source router model.${CClear}"
              echo -e "${CYellow}WARNING: This may have disastrous effects on the operation and stabiliity of your router.${CClear}"
              echo -e "${CYellow}WARNING: By continuing, you accept full responsibility for these actions.${CClear}"
            else
              exit 0
            fi
          fi
        fi

        # Determine mismatched firmware
        if [ ! -z $RESTOREBUILD ]; then
          if [ "$FWBUILD" != "$RESTOREBUILD" ]; then
            echo ""
            echo -e "${CRed}ERROR: Original source router firmware/build is different from target router firmware/build."
            echo -e "${CRed}ERROR: Restorations can only be performed on the same router firmware/build or you may brick your router!"
            echo -e "${CRed}ERROR: If you are certain router firmware/build is the same, please check and re-save your configuration!${CClear}"
            logger "BACKUPMON ERROR: Original source router firmware/build is different from target router firmware/build. Please check your configuration!"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Original source router firmware/build is different from target router firmware/build. Please check your configuration!" >> $LOGFILE
            echo ""
            echo -e "${CGreen}Would you like to continue to restore from backup?"
            if promptyn "(y/n): "; then
              echo ""
              echo ""
              echo -e "${CYellow}WARNING: Continuing restore using backup saved with older router firmware/build.${CClear}"
              echo -e "${CYellow}WARNING: This may have disastrous effects on the operation and stabiliity of your router.${CClear}"
              echo -e "${CYellow}WARNING: By continuing, you accept full responsibility for these actions.${CClear}"
            else
              exit 0
            fi
          fi
        fi

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
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/jffs.tar.gz to /jffs" >> $LOGFILE
            tar -xzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/jffs.tar.gz -C /jffs >/dev/null
            if [ "$EXTLABEL" != "NOTFOUND" ]; then
              echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz to $EXTDRIVE${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz to $EXTDRIVE" >> $LOGFILE
              tar -xzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${EXTLABEL}.tar.gz -C $EXTDRIVE >/dev/null
              TE=$?
              if [ $TE -eq 0 ]; then
                echo -e "${CGreen}No TAR errors detected on restore to $EXTDRIVE${CClear}"
              else
                echo -e "${CRed}ERROR: TAR errors detected on restore to $EXTDRIVE${CClear}"
                echo -e "${CRed}Would you like to proceed with the restoration process?${CClear}"
                echo ""
                if promptyn "(y/n): "; then
                  echo ""
                  echo -e "\n${CGreen}Proceeding...${CClear}\n"
                else
                  echo ""
                  echo -e "${CRed}Exiting...${CClear}\n"
                  echo ""
                  exit 1
                fi
              fi
            else
              echo -e "${CYellow}WARNING: External USB drive not found. Skipping restore."
              logger "BACKUPMON WARNING: External USB drive not found. Skipping restore."
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External USB drive not found. Skipping restore." >> $LOGFILE
            fi
            echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/nvram.cfg to NVRAM${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/nvram.cfg to NVRAM" >> $LOGFILE
            nvram restore ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/nvram.cfg >/dev/null 2>&1
            echo ""
            echo -e "${CGreen}STATUS: Secondary backups were successfully restored to their original locations.  Forcing reboot now!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary backups were successfully restored to their original locations.  Forcing reboot!" >> $LOGFILE
            echo ""
            rm -f /jffs/scripts/backupmon.cfg
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
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVJFFS} to /jffs" >> $LOGFILE
            tar -xzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVJFFS} -C /jffs >/dev/null
            if [ "$EXTLABEL" != "NOTFOUND" ]; then
              echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVUSB} to $EXTDRIVE${CClear}"
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVUSB} to $EXTDRIVE" >> $LOGFILE
              tar -xzf ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVUSB} -C $EXTDRIVE >/dev/null
              TE=$?
              if [ $TE -eq 0 ]; then
                echo -e "${CGreen}No TAR errors detected on restore to $EXTDRIVE${CClear}"
              else
                echo -e "${CRed}ERROR: TAR errors detected on restore to $EXTDRIVE${CClear}"
                echo -e "${CRed}Would you like to proceed with the restoration process?${CClear}"
                echo ""
                if promptyn "(y/n): "; then
                  echo ""
                  echo -e "\n${CGreen}Proceeding...${CClear}\n"
                else
                  echo ""
                  echo -e "${CRed}Exiting...${CClear}\n"
                  echo ""
                  exit 1
                fi
              fi
            else
              echo -e "${CYellow}WARNING: External USB drive not found. Skipping restore."
              logger "BACKUPMON WARNING: External USB drive not found. Skipping restore."
              echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - WARNING: External USB drive not found. Skipping restore." >> $LOGFILE
            fi
            echo -e "${CGreen}Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVNVRAM} to NVRAM${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Restoring ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVNVRAM} to NVRAM" >> $LOGFILE
            nvram restore ${SECONDARYUNCDRIVE}${SECONDARYBKDIR}/${BACKUPDATE}/${ADVNVRAM} >/dev/null 2>&1
            echo ""
            echo -e "${CGreen}STATUS: Secondary backups were successfully restored to their original locations.  Forcing reboot now!${CClear}"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary backups were successfully restored to their original locations.  Forcing reboot!" >> $LOGFILE
            echo ""
            rm -f /jffs/scripts/backupmon.cfg
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
        return

      else

        # Exit gracefully
        echo ""
        echo ""
        echo -e "${CGreen}STATUS: Settling for 10 seconds..."
        sleep 10

        unmountsecondarydrv

        echo -e "${CClear}"
        return

      fi

    else

      # Exit gracefully
      echo ""
      echo ""
      echo -e "${CGreen}STATUS: Settling for 10 seconds..."
      sleep 10

      unmountsecondarydrv

      echo -e "${CClear}"
      return

    fi

  fi

}

# -------------------------------------------------------------------------------------------------------------------------

# unmountdrv is a function to gracefully unmount the drive, and retry for up to 30 seconds
unmountdrv () {

  if [ "$BACKUPMEDIA" == "USB" ]; then
     echo -e "${CGreen}STATUS: External USB drive continues to stay mounted.${CClear}"
     echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External USB drive continues to stay mounted." >> $LOGFILE
  else
    CNT=0
    TRIES=3
      while [ $CNT -lt $TRIES ]; do # Loop through number of tries
        umount -l $UNCDRIVE  # unmount the local backup drive from the UNC
        URC=$?
        if [ $URC -eq 0 ]; then  # If umount come back successful, then proceed
          echo -en "${CGreen}STATUS: External network drive ("; printf "%s" "${UNC}"; echo -e ") unmounted successfully.${CClear}"
          printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: External network drive ( ${UNC} ) unmounted successfully." >> $LOGFILE
          break
        else
          echo -e "${CYellow}WARNING: Unable to unmount from external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
          sleep 10
          CNT=$((CNT+1))
          if [ $CNT -eq $TRIES ];then
            echo -e "${CRed}ERROR: Unable to unmount from external network drive. Please check your configuration. Exiting.${CClear}"
            logger "BACKUPMON ERROR: Unable to unmount from external network drive. Please check your configuration!"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to unmount from external network drive. Please check your configuration!" >> $LOGFILE
            sendmessage 1 "Unable to unmount network drive"
            echo -e "\n"
            exit 1
          fi
        fi
      done
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# unmountsecondarydrv is a function to gracefully unmount the secondary drive, and retry for up to 30 seconds
unmountsecondarydrv () {

  if [ "$SECONDARYBACKUPMEDIA" == "USB" ]; then
     echo -e "${CGreen}STATUS: Secondary external USB drive continues to stay mounted.${CClear}"
     echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary external USB drive continues to stay mounted." >> $LOGFILE
  else
    CNT=0
    TRIES=3
      while [ $CNT -lt $TRIES ]; do # Loop through number of tries
        umount -l $SECONDARYUNCDRIVE  # unmount the local backup drive from the Secondary UNC
        URC=$?
        if [ $URC -eq 0 ]; then  # If umount come back successful, then proceed
          echo -en "${CGreen}STATUS: Secondary external network drive ("; printf "%s" "${SECONDARYUNC}"; echo -e ") unmounted successfully.${CClear}"
          printf "%s\n" "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Secondary external network drive ( ${SECONDARYUNC} ) unmounted successfully." >> $LOGFILE
          break
        else
          echo -e "${CYellow}WARNING: Unable to unmount from secondary external network drive. Trying every 10 seconds for 30 seconds.${CClear}"
          sleep 10
          CNT=$((CNT+1))
          if [ $CNT -eq $TRIES ];then
            echo -e "${CRed}ERROR: Unable to unmount from secondary external network drive. Please check your configuration. Exiting.${CClear}"
            logger "BACKUPMON ERROR: Unable to unmount from secondary external network drive. Please check your configuration!"
            echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Unable to unmount from secondary external network drive. Please check your configuration!" >> $LOGFILE
            sendmessage 1 "Unable to unmount secondary network drive"
            echo -e "\n"
            exit 1
          fi
        fi
      done
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# unmountdrv is a function to gracefully unmount the drive, and retry for up to 30 seconds
unmounttestdrv () {

  if [ "$TESTBACKUPMEDIA" == "USB" ]; then
     echo -e "${CGreen}STATUS: Test external USB drive continues to stay mounted.${CClear}"
  else
    CNT=0
    TRIES=3
      while [ $CNT -lt $TRIES ]; do # Loop through number of tries
        umount -l $TESTUNCDRIVE  # unmount the local backup drive from the UNC
        URC=$?
        if [ $URC -eq 0 ]; then  # If umount come back successful, then proceed
          echo -en "${CGreen}STATUS: External test tetwork drive ("; printf "%s" "${TESTUNC}"; echo -e ") unmounted successfully.${CClear}"
          break
        else
          echo -e "${CYellow}WARNING: Unable to unmount from external test network drive. Retrying...${CClear}"
          sleep 5
          CNT=$((CNT+1))
          if [ $CNT -eq $TRIES ];then
            echo -e "${CRed}ERROR: Unable to unmount from external test network drive. Please check your configuration. Exiting.${CClear}"
            read -rsp $'Press any key to acknowledge...\n' -n1 key
            break
          fi
        fi
      done
  fi
}

# -------------------------------------------------------------------------------------------------------------------------

# checkplaintxtpwds is a function to check if old plaintext pwds are still in use due to change to new base64 pwd storage change
checkplaintxtpwds () {

  #Check to see if old conflicting variable names are being used
  if [ ! -z "$USERNAME" ]; then
    sed -i "s/USERNAME=/BTUSERNAME=/" "/jffs/addons/backupmon.d/backupmon.cfg"
    sed -i "s/PASSWORD=/BTPASSWORD=/" "/jffs/addons/backupmon.d/backupmon.cfg"
    source $CFGPATH
  fi

  #echo $PASSWORD | base64 -d > /dev/null 2>&1
  echo "$BTPASSWORD" | openssl enc -d -base64 -A | grep -vqE '[^[:graph:]]'
  PRI="$?"
  #echo $SECONDARYPWD | base64 -d > /dev/null 2>&1
  echo "$SECONDARYPWD" | openssl enc -d -base64 -A | grep -vqE '[^[:graph:]]'
  SEC="$?"

  if [ "$BACKUPMEDIA" == "Network" ]; then
    if [ "$PRI" == "1" ]; then
      echo -e "${CRed}ERROR: Plaintext passwords are still being used in the config file. Please go under the BACKUPMON setup menu"
      echo -e "to reconfigure your primary and/or secondary target backup passwords, and save your config. New changes to the"
      echo -e "way passwords are encoded and saved requires your immediate attention!${CClear}"
      echo ""
      read -rsp $'Press any key to enter setup menu...\n' -n1 key
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Plaintext passwords detected. Please check your configuration!" >> $LOGFILE
      vsetup
      exit 0
    fi
  fi

  if [ "$SECONDARYBACKUPMEDIA" == "Network" ]; then
    if [ "$SEC" == "1" ] && [ $SECONDARYSTATUS -eq 1 ]; then
      echo -e "${CRed}ERROR: Plaintext passwords are still being used in the config file. Please go under the BACKUPMON setup menu"
      echo -e "to reconfigure your primary and/or secondary target backup passwords, and save your config. New changes to the"
      echo -e "way passwords are encoded and saved requires your immediate attention!${CClear}"
      echo ""
      read -rsp $'Press any key to enter setup menu...\n' -n1 key
      echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Plaintext passwords detected. Please check your configuration!" >> $LOGFILE
      vsetup
      exit 0
    fi
  fi
  
}


# -------------------------------------------------------------------------------------------------------------------------

# excludeswap is a function to write a swap file exlusion file, or to add to an existing exlusions file
excludeswap () {

# First check to see if the swap file exlusion file exists, if not, create it. Thanks to @ScottW for the ideas!

swapname=$(cat /proc/swaps | awk 'NR==2 {print $1}' | sed 's|.*/||') >/dev/null 2>&1 

if [ ! -f $PFEXCLUSION ]; then
  
  if [ ! -z $swapname ] || [ $swapname != "" ]; then
    { echo $swapname
    } > $PFEXCLUSION
    echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - INFO: Page File Backup Exclusion File created" >> $LOGFILE
  else
    echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: Page File does not exist" >> $LOGFILE
  fi

fi
  
# Check to see if the exclusion file/path has been defined, if not, use the pagefile exclusion file in its place

if [ "$BACKUPSWAP" == "0" ]; then
  
  if [ -z "$EXCLUSION" ] || [ "$EXCLUSION" == "" ]; then
    EXCLUSION="$PFEXCLUSION"
  fi
  
    if [ -z "$SECONDARYEXCLUSION" ] || [ "$SECONDARYEXCLUSION" == "" ]; then
    SECONDARYEXCLUSION="$PFEXCLUSION"
  fi

  # Check to see if an exlusion file is in place, and make sure the swap has been added to it.

  if ! grep -q -F "$swapname" $EXCLUSION; then
    echo "$swapname" >> $EXCLUSION
  fi
  
  if ! grep -q -F "$swapname" $SECONDARYEXCLUSION; then
    echo "$swapname" >> $SECONDARYEXCLUSION
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

# Check for and add an alias for BACKUPMON
if ! grep -F "sh /jffs/scripts/backupmon.sh" /jffs/configs/profile.add >/dev/null 2>/dev/null; then
  echo "alias backupmon=\"sh /jffs/scripts/backupmon.sh\" # backupmon" >> /jffs/configs/profile.add
fi

# Determine router model
[ -z "$(nvram get odmpid)" ] && ROUTERMODEL="$(nvram get productid)" || ROUTERMODEL="$(nvram get odmpid)" # Thanks @thelonelycoder for this logic

#Get FW Version for inclusion in instructions.txt and to check before a restore
FWVER=$(nvram get firmver | tr -d '.')
BUILDNO=$(nvram get buildno)
EXTENDNO=$(nvram get extendno)
if [ -z $EXTENDNO ]; then EXTENDNO=0; fi
FWBUILD=$FWVER"."$BUILDNO"_"$EXTENDNO

# Check to see if EXT drive exists
USBPRODUCT="$(nvram get usb_path1_product)"
EXTLABEL="$(_CheckForMountPointAndVolumeLabel_)"
LABELSIZE=$(echo $EXTLABEL | sed 's/ //g' | wc -m)

# If there's no label or product, there's no EXT USB Drive, else the label might be blank
if [ -z "$EXTLABEL" ] && [ -z "$USBPRODUCT" ]; then
  EXTLABEL="NOTFOUND"
elif [ $LABELSIZE -le 1 ]; then
  clear
  echo -e "${CYellow}WARNING: External USB Drive Label Name is not sufficient, or unable to detect default sda drive label."
  echo ""
  echo -e "${CRed}BACKUPMON MAY NOT FUNCTION CORRECTLY IN THIS SCENARIO${CClear}"
  echo ""
  echo -e "${CYellow}Should your drive be without a label, please give it a value, other than blank. Omit any spaces."
  echo -e "Example: EXTUSB, or SAMSUNG-SSD... etc.${CClear}"
  echo -e "$(date +'%b %d %Y %X') $(nvram get lan_hostname) BACKUPMON[$$] - **ERROR**: External USB Drive Label Name is not sufficient, or unable to detect default sda drive label. Please investigate." >> $LOGFILE
  echo ""
  echo -e "${CGreen}[Continuing in 10 seconds]..."
  sleep 10
fi

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

# Check to see if a second command is being passed to remove color
if [ "$2" == "-bw" ]
  then
    blackwhite
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
      echo -e "${CRed}ERROR: BACKUPMON is not configured.  Please run 'backupmon.sh -setup' first."
      echo -e "${CClear}"
      exit 0
    fi
    checkplaintxtpwds    #Check for plaintext passwords
    restore              #Run the restore routine
    trimlogs             #Trim the logs
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
    if [ "$UpdateNotify" == "0" ]; then
     echo -e "${CGreen}BACKUPMON v$Version"
    else
      echo -e "${CGreen}BACKUPMON v$Version ${CRed}-- $UpdateNotify"
    fi
    
    # Determine if the config is local or under /jffs/addons/backupmon.d
    if [ -f $CFGPATH ]; then #Making sure file exists before proceeding
      source $CFGPATH
    elif [ -f /jffs/scripts/backupmon.cfg ]; then
      source /jffs/scripts/backupmon.cfg
      cp /jffs/scripts/backupmon.cfg /jffs/addons/backupmon.d/backupmon.cfg
    else
      clear
      echo -e "${CRed}ERROR: BACKUPMON is not configured.  Please run 'backupmon.sh -setup' first."
      echo -e "${CClear}"
      exit 0
    fi
    checkplaintxtpwds     #Check for plaintext passwords
    autopurge             #Purge primary backups
    autopurgesecondaries  #Purge secondary backups
    trimlogs              #Trim the logs
    echo ""
  exit 0
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
      echo -e "${CRed}ERROR: BACKUPMON is not configured.  Please run 'backupmon.sh -setup' first."
      echo -e "${CClear}"
      exit 0
    fi
    checkplaintxtpwds
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
      echo -e "${CRed}ERROR: BACKUPMON is not configured.  Please run 'backupmon.sh -setup' first."
      echo -e "${CClear}"
      exit 1
    fi
    checkplaintxtpwds
    BSWITCH="False"
fi

# Check for the Swap File Exclusion
if [ "$BACKUPSWAP" == "0" ]; then
  excludeswap
fi

updatecheck

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

echo -e "${CCyan}Asus Router Model: ${CGreen}${ROUTERMODEL}"
echo -e "${CCyan}Firmware/Build Number: ${CGreen}${FWBUILD}"
echo -e "${CCyan}External USB Drive Mount Path: ${CGreen}${EXTDRIVE}"
if [ $FREQUENCY == "W" ]; then FREQEXPANDED="Weekly"; fi
if [ $FREQUENCY == "M" ]; then FREQEXPANDED="Monthly"; fi
if [ $FREQUENCY == "Y" ]; then FREQEXPANDED="Yearly"; fi
if [ $FREQUENCY == "P" ]; then FREQEXPANDED="Perpetual"; fi
  
if [ "$BACKUPMEDIA" == "USB" ]; then  
  echo -e "${CCyan}Backing up to ${CGreen}USB${CCyan} mounted to ${CGreen}${UNCDRIVE}"
else
  echo -en "${CCyan}Backing up to ${CGreen}"; printf "%s" "${UNC}"; echo -e "${CCyan} mounted to ${CGreen}${UNCDRIVE}"
fi
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
echo -e "${CGreen}[Primary Backup Commencing]...          "
echo ""
echo -e "${CCyan}Messages:${CClear}"

checkplaintxtpwds       #Check for plaintext passwords
backup                  #Run primary backups
sendmessage 0 "Primary Backup completed successfully"
secondary               #Run secondary backups
if [ $SECONDARYSTATUS -eq 1 ]; then
  sendmessage 0 "Secondary Backup completed successfully"
fi

if [ $PURGE -eq 1 ] && [ "$BSWITCH" == "True" ]; then  
  autopurge             #Run autopurge on primary backups
fi

if [ $SECONDARYPURGE -eq 1 ] && [ "$BSWITCH" == "True" ]; then
  autopurgesecondaries  #Run autopurge on secondary backups
fi

trimlogs                #Trim the logs

BSWITCH="False"
echo -e "${CClear}"
exit 0

#} #2>&1 | tee $LOG | logger -t $(basename $0)[$$]  # uncomment/comment to enable/disable debug mode
