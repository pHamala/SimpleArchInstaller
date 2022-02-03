#!/bin/bash
clear
simplearchinstaller (){
echo -ne "
-------------------------------------------------------------------------
                    Simple Arch Installer 
-------------------------------------------------------------------------
"
}

simplearchinstaller

# Enter userinfo

read -p "Please enter your username: " username

echo -ne "Please enter your password: \n"
read -s password 

read -rep "Please enter your hostname: " hostname
clear

simplearchinstaller

# selection for disk type

lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print NR,"/dev/"$2" - "$3}' # show disks with /dev/ prefix and size
echo -ne "
------------------------------------------------------------------------
    THIS WILL FORMAT AND DELETE ALL DATA ON THE DISK                  
------------------------------------------------------------------------
"
read -p "Please enter full path to disk: (example /dev/sda): " disk
clear

simplearchinstaller

# Detect timezone
time_zone="$(curl --fail https://ipapi.co/timezone)"
clear
simplearchinstaller
echo -ne "System detected your timezone to be '$time_zone' \n"
echo -ne "Is this correct? yes/no:" 
read answer
case $answer in
    y|Y|yes|Yes|YES)
    timezone=$time_zone;;
    n|N|no|NO|No)
    echo "Please enter your desired timezone e.g. Europe/London :" 
    read new_timezone
    timezone=$new_timezone;;
    *) echo "Wrong option. Try again";;
esac

clear

# Prepare disk for installation
echo -ne "
-------------------------------------------------------------------------
                    Formatting disk 
-------------------------------------------------------------------------
"
pacman -S --noconfirm gptfdisk btrfs-progs
clear

# Prepare disk
simplearchinstaller
sgdisk -Z ${disk} 
sgdisk -a 2048 -o ${disk} 


if [[ "${disk}" =~ "nvme" ]]; then
    partition1=${disk}p1
    partition2=${disk}p2
    partition3=${disk}p3
else
    partition1=${disk}1
    partition2=${disk}2
    partition3=${disk}3
fi

# Create partitions to disk

if [[ ${BOOT_TYPE} =~ "BIOS" ]]; then

    sgdisk -n 1::+2M --typecode=1:ef02 --change-name=1:'BIOS' ${disk} # partition 1 (BIOS Boot Partition)
    sgdisk -A 1:set:2 ${disk}
    sgdisk -n 2::+4000M --typecode=2:8200 --change-name=2:'SWAP' ${disk} # partition 2 (Swap Partition)
    sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' ${disk} # partition 3 (Root)

    # Create filesystems for BIOS
    
    mkfs.ext2 -L "BIOS" ${partition1}
    mkswap -L "SWAP" ${partition2}
    mkfs.btrfs -L ROOT ${partition3} -f 

    # Mount created partitions
    swapon ${partition2}
    mount -t btrfs ${partition3} /mnt


else

    sgdisk -n 1::+1000M --typecode=1:ef00 --change-name=1:'EFI' ${disk} # partition 1 (UEFI Boot Partition)
    sgdisk -n 2::+4000M --typecode=2:8200 --change-name=2:'SWAP' ${disk} # partition 2 (Swap Partition)
    sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' ${disk} # partition 3 (Root)

    # Create filesystems for UEFI

    mkfs.vfat -F32 -n "EFI" ${partition1}
    mkswap -L "SWAP" ${partition2}
    mkfs.btrfs -L ROOT ${partition3} -f 

    # Mount created partitions
    swapon ${partition2}
    mount -t btrfs ${partition3} /mnt

fi   
clear

# Install Arch Basic Packages
echo -ne "
-------------------------------------------------------------------------
                    Installing Packages
-------------------------------------------------------------------------
"
pacstrap /mnt base base-devel linux linux-firmware sudo
clear

# Generate fstab file

genfstab -pU /mnt >> /mnt/etc/fstab

# Generate locale
echo -ne "
-------------------------------------------------------------------------
                    Generating locales
-------------------------------------------------------------------------
"
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf
arch-chroot /mnt locale-gen
clear

# Setup system clock
echo -ne "
-------------------------------------------------------------------------
                    Setting up system clock and timezone
-------------------------------------------------------------------------
"
arch-chroot /mnt timedatectl set-ntp true
arch-chroot /mnt timedatectl --no-ask-password set-timezone $timezone
arch-chroot /mnt hwclock --systohc --localtime
sleep 3
clear

# Set hostname
echo $hostname > /mnt/etc/hostname
clear

echo -ne "
-------------------------------------------------------------------------
                    Setting up users and passwords 
-------------------------------------------------------------------------
"

# Set root password
echo -en "$password\n$password" | passwd

# Create new user
arch-chroot /mnt useradd -m -g users -G users,audio,lp,optical,storage,video,wheel,games,power,scanner -s /bin/bash $username

# Add user password
echo "$username:$password" | chpasswd --root /mnt

# Add user as a sudoer
arch-chroot /mnt echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo
sleep 3
clear

echo -ne "
-------------------------------------------------------------------------
                    Installing GRUB
-------------------------------------------------------------------------
"

# Install Grub
arch-chroot /mnt /bin/bash << EOF

# Check if disk is sdd/hdd or NVME
if [[ "${disk}" =~ "nvme" ]]; then
    partition1=${DISK}p1

else
    partition1=${disk}1

fi

# Check if boot type is BIOS or UEFI
if [[ -d "/sys/firmware/efi" ]]; then
    
    pacman -S grub efibootmgr os-prober --noconfirm
    mkdir /boot/efi
    mount ${partition1} /boot/efi
    grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
    grub-mkconfig -o /boot/grub/grub.cfg 
    

else [[ ! -d "/sys/firmware/efi" ]]; 
    
    pacman -S grub os-prober --noconfirm
    mkdir /boot
    mount ${partition1} /boot
    grub-install ${disk}
    grub-mkconfig -o /boot/grub/grub.cfg 

fi

clear
EOF
sleep 5
rm -R /root/SimpleArchInstaller
umount /mnt
swapoff ${partition2}



