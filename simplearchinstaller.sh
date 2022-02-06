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

read -rep "Please enter your username: " username

echo -ne "Please enter your password: \n"
read -sr password 

read -rep "Please enter your hostname: " hostname
clear



# selection for disk type
simplearchinstaller
lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print NR,"/dev/"$2" - "$3}' # show disks with /dev/ prefix and size
echo -ne "
------------------------------------------------------------------------
    THIS WILL FORMAT AND DELETE ALL DATA ON THE DISK                  
------------------------------------------------------------------------
"
read -rep "Please enter full path to disk: (example /dev/sda): " disk
clear

# Enter keymap
simplearchinstaller
echo -ne "
If you are unsure what keymap you should choose, quit this script
with CTRL+C and type ls /usr/share/kbd/keymaps/**/*.map.gz
------------------------------------------------------------------------                
"
read -rep "Please enter your keymap: " keymap
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
    echo "Please enter your desired timezone e.g. Europe/Berlin :" 
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

    mkswap ${partition2}
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
    
    mkswap ${partition2}
    swapon ${partition2}
    mount -t btrfs ${partition3} /mnt

fi   
clear

# determine processor-type 

proc_type=$(lscpu)
if grep -E "GenuineIntel" <<< ${proc_type}; then
    ucode=intel-ucode
    
elif grep -E "AuthenticAMD" <<< ${proc_type}; then
    ucode=amd-ucode    
 
fi
clear

# Determine Graphic Drivers find and install
echo -ne "
-------------------------------------------------------------------------
                    Determining GPU
-------------------------------------------------------------------------
"
sleep 3
gpu_type=$(lspci)
if grep -E "NVIDIA|GeForce" <<< ${gpu_type}; then
    gpu=nvidia nvidia-xconfig

elif lspci | grep 'VGA' | grep -E "Radeon|AMD"; then
    gpu=xf86-video-amdgpu

elif grep -E "Integrated Graphics Controller" <<< ${gpu_type}; then
    gpu=libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa

elif grep -E "Intel Corporation UHD" <<< ${gpu_type}; then
    gpu=ibva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
fi
clear


# Optimize mirrorlist and pacman for faster downloads
echo -ne "
-------------------------------------------------------------------------
                    Optimizing mirrors and pacman 
-------------------------------------------------------------------------
"
sleep 3
iso=$(curl -4 ifconfig.co/country-iso)
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
pacman -S --noconfirm reflector rsync
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
reflector -a 48 -c $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
clear

# Install Arch Basic Packages
echo -ne "
-------------------------------------------------------------------------
                    Installing Base Arch Packages
-------------------------------------------------------------------------
"
sleep 3
pacstrap /mnt base base-devel linux linux-firmware sudo $ucode $gpu networkmanager dhclient nano
clear

# Generate locale
echo -ne "
-------------------------------------------------------------------------
                    Generating locales and set keymap
-------------------------------------------------------------------------
"
sleep 3
# Generate fstab file
genfstab -pU /mnt >> /mnt/etc/fstab

# Generate locale
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf
arch-chroot /mnt locale-gen

# Add persistent keymap
arch-chroot /mnt localectl --no-convert set-keymap $keymap
clear

# Setup system clock
echo -ne "
-------------------------------------------------------------------------
                    Setting up system clock and timezone
-------------------------------------------------------------------------
"
sleep 3
arch-chroot /mnt timedatectl set-ntp true
arch-chroot /mnt timedatectl --no-ask-password set-timezone $timezone
arch-chroot /mnt hwclock --systohc --localtime
sleep 3
clear

# Set hostname
arch-chroot /mnt echo $hostname > /mnt/etc/hostname
clear

echo -ne "
-------------------------------------------------------------------------
                    Setting up users and passwords 
-------------------------------------------------------------------------
"

sleep 3
# Set root password
echo -en "$password\n$password" | passwd

# Create new user
arch-chroot /mnt useradd -m -g users -G users,audio,lp,optical,storage,video,wheel,games,power,scanner -s /bin/bash $username

# Add user password
echo "$username:$password" | chpasswd --root /mnt
clear

echo -ne "
-------------------------------------------------------------------------
                    Installing Xorg
-------------------------------------------------------------------------
"
sleep 3
arch-chroot /mnt pacman -S --noconfirm --needed mesa xorg xorg-server xorg-apps xorg-drivers xorg-xkill xorg-xinit xterm xwayland egl-wayland xwayland $gpu 

echo -ne "
-------------------------------------------------------------------------
                    Installing additional packages
-------------------------------------------------------------------------
"
sleep 3
pacman -S --noconfirm --needed cups bluez bluez-libs bluez-utils networkmanager ntfs-3g p7zip zip 

# Enable system services
echo -ne "
-------------------------------------------------------------------------
                    Enabling services
-------------------------------------------------------------------------
"
sleep 3
systemctl enable fstrim.timer
systemctl enable NetworkManager  
systemctl enable cups
systemctl enable bluetooth

echo -ne "
-------------------------------------------------------------------------
                    Finalize install
-------------------------------------------------------------------------
"

# Install Grub
sleep 3
arch-chroot /mnt /bin/bash << EOF

# Add user as sudoer
echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo

# Check if boot type is BIOS or UEFI
if [[ -d "/sys/firmware/efi" ]]; then
    
    mkinitcpio -p linux
    pacman -S grub efibootmgr os-prober --noconfirm
    mkdir /boot/efi
    mount ${partition1} /boot/efi
    grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
    grub-mkconfig -o /boot/grub/grub.cfg 
    
else 
    
    mkinitcpio -p linux
    pacman -S grub os-prober --noconfirm
    grub-install --target=i386-pc ${disk}
    grub-mkconfig -o /boot/grub/grub.cfg 

fi

clear
EOF

simplearchinstaller
rm -R /root/SimpleArchInstaller
echo -ne "
            Arch Linux installed successfully, reboot and enjoy!
-------------------------------------------------------------------------
"




