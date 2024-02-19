# BACKUPMON v1.5.6
![image](https://github.com/ViktorJp/BACKUPMON/assets/97465574/671c7e01-6343-4f10-8139-bdf53ba28779)

**First off** -- HUGE thanks to @Jeffrey Young for sharing his original backup script. His script is the main engine of BACKUPMON, and all credit goes to him! BACKUPMON is simply a wrapper around Jeff's backup script functionality, adding easy-to-use menus, more status feedback, and the ability to launch a restore based on your previous backups. Also, big thanks to @Martinski for his many contributions as well as his extremely helpful AMTM email library script, and huge props to @visortgw for contributing to the backup methodologies thread with his scripts and wisdom!

**Executive Summary**: BACKUPMON is a shell script that provides backup and restore capabilities for your Asus-Merlin firmware router's JFFS, NVRAM and external USB drive environments. By creating a network share off a NAS, server, or other device, BACKUPMON can point to this location, and perform a daily backup to this mounted drive. To perform daily, unattended backups, simply add a statement to your cron schedule, and launch backupmon.sh at any time you wish. During a situation of need to restore a backup after a catastrophic event with either your router or attached USB storage, simply copy the backupmon.sh & .cfg files over to a newly formatted /jffs/scripts folder, ensuring that your external USB storage was formatted with the same exact name (which is retrievable from the instructions.txt in your backup folder), and perform the restore by running the "backupmon.sh -restore" command, selecting the backup you want to use, and going through the prompts to complete the restoration of both your JFFS, NVRAM and external USB drive environments.

**Use-case**: BACKUPMON was designed to backup from, and restore to an already configured router from an external network resource, given a situation of a corrupted USB drive, botched Entware environment, or other general corruption issues. It can, however, also restore you back to a previous state if you decide to completely wipe your router or external drive from scratch. You can use it to move from one external USB drive to another... say, upgrading from a flashdrive to an SSD! You could also use it to restore your environment to a similar router if your old one dies, and you pick up the same model + firmware level as a replacement.

Here are a couple of different network/USB backup scenarios that it is able to handle (as of v1.35):

* **Router USB Drive -> External network device/share** (on your local network)
* **Router USB Drive -> Local network share** (could be mounted to a secondary partition on your USB Drive, or secondary USB Drive)
* **Router USB Drive -> Secondary Router USB Drive** (plugged into the secondary USB port)
* **Router USB Drive -> Router USB Drive** (backing up to itself into a separate folder... of course, not recommended, but possible)
* **Router USB Drive Partition 1 -> Router USB Drive Partition 2** (kinda like the one above, but gives it a little more separation)

If you do go down the path of backing your USB drive to your USB drive, it's possible, not recommended. The safest way still is to store backups is far away from the device being backed up... so use at your own risk.

**What it should NOT be used for**: It is not meant to restore backups from one particular model of router (ex: RT-AC86U), to a different shiny new model (ex: GT-AX6000) that you just picked up. In this case, it's still best to set your new router up from scratch, and selectively import any critical files manually from your .TAR backups to your new router if needed. Also, please do not restore your settings/backups from an older firmware to a newer firmware. Your CFG (settings) file is meant for the current firmware you're on, so if you do restore, make sure it's still on the same firmware as before.

**Requirements:**
* This script will allow you to back up one partition of your choice. You are no longer limited to sda1.
* Your Network Backup Target must be able to speak the CIFS/SMB protocol, as that is the method currently used to back up your files across the network. CIFS (Common Internet File System) is a dialect of the SMB (Server Message Block) protocol, and is a very broad standard supported by Windows, Linux and Apple devices. I am looking into supporting NFS as well in the very near future.
* You now have the option to backup from USB1 to USB2, or USB to itself... though not recommended.
* Your External USB should have a valid drive label. Having a blank label may create issues backing up or restoring.

