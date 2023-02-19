#!/bin/sh

# section:introduction
# 
# !!! READ ME !!!
#
# The script is not complete. Some parts are either missing
# or are not configured in such way you might want them to be.
# Please navigate to corresponing parts and adjust them to your liking.
#
# Script is devided into following setions.
# For navigation search for 'section:<section_name>'.
#
# introduction
# functions
# constants
# read-input
# disk-setup
# base-installation
# base-bootstrap
# finalization
# base-timezone
# base-localization
# base-networking
# base-system-shell
# base-users
# base-update-hooks
# base-boot
# the-most-important-thing
# advanced-pacman-configuration
# advanced-include-universe-repository
# advanced-enable-arch-repositories
# advanced-makepkg-configuration
# advanced-package-installation
# advanced-dotfiles-installation
# advanced-touchpad-tap-click-setting
# advanced-yay-installation
# advanced-custom-neovim-installtion

# section:functions
# basic helper funcitons

# $1 ... read prompt
read_yes_no() {
	printf "%s [y/n] " "$1"
	read -r answer
	echo "$answer" | grep -q '^[Yy]' || return 1
}

# $1 ... variable name
# $2 ... read prompt
read_plain() {
	printf "%s" "$2"
	read -r plain
	eval "$1"="$plain"
}

# $1 ... variable name
# $2 ... read prompt
read_secret() {
	printf "%s" "$2"
	stty -echo
	read -r secret
	stty echo
	echo ""
	eval "$1"="$secret"
}

# $1 ... user for whom the password is read
# $2 ... variable to which the password is set
read_password_for() {
	while true; do
		read_secret "$2" "Password for $1: "
		read_secret _password "Repeat password for $1: "
		[ "$( eval echo "\$$2" )" = "$_password" ] && break
		echo "Passwords are not the same."
	done
}

self_name="$( basename "$0" )"

print_help() {
	printf " === Help for %s ===

The script recognize these options:
 -i|--install)
\tThis actually launches the installation process.
 -b|--bootstrap)
\tThis is meant to be used by script itself,
\twhen auto-executing in chroot.
\tIt requires 4 positional arguments:
\t\tusername
\t\tpassword
\t\troot_password
\t\tencryption_password
 -h|--help)
\tThis option is rather idiomatic.
\tIt apparently show this help text.
\tThe same behavior is without any option used.

Process of designed execution:
 1) open the %s script
 2) navigate to 'section:introduction'
 3) follow the steps in the commentary
 4) save your modifications
 5) execute the installation '%s --install'

Notes:
 - the script options are not meant to be combined
 - the execution of installation before proper modifications
   to the script might have enxpected results
" "$self_name" "$self_name" "$self_name"
}

install=false
bootstrap=false

while [ "$#" -gt "0" ]; do
	case "$1" in
		-i|--install)
			install=true
			;;
		-b|--bootstrap)
			bootstrap=true
			for i in $( seq 2 4 ); do
				if [ -z "$( eval echo "\$$i" )" ]; then
					echo "Bad arguments for '-b|--bootstrap' option. Run '$self_name -h' for help." >&2
					exit 1
				fi
			done
			username="$2"
			password="$3"
			root_password="$4"
			shift 3
			;;
		-h|--help) ;;
		*)
			echo "Uknown option. Run '$self_name -h' for help." >&2
			exit 1
			;;
	esac
	shift
done


# section:constants
ARCH_LINUX_REPO_LIST="https://github.com/archlinux/svntogit-packages/raw/packages/pacman-mirrorlist/trunk/mirrorlist"
COUNTRY=""
PART_NUM_PREFIX=""

DISK="/dev/sda"
HOSTNAME="artix"
DOTFILES="https://github.com/bulirma/dotfiles.git"

DISKP="$DISK$PART_NUM_PREFIX"


if $install; then

	# section:read-input
	read_plain username "Username: "
	read_password_for "$username" password
	read_yes_no "Use same password for root?" && root_password="$password" || read_password_for root root_password
	read_password_for "disk encryption" encryption_password

	# section:disk-setup
	#parted -s "$DISK"
	#	mklabel gpt \
	#	mkpart boot fat32 2MiB 384MiB \
	#	mkpart swap linux-swap 384MiB 2434MiB \
	#	mkpart root ext4 2434MiB 100%
	
	parted -s "$DISK" \
		mklabel msdos \
		mkpart primary 2MiB 386MiB \
		mkpart primary 386MiB 100%

	#dd bs=4096 if=/dev/urandom iflag=nocache of="${DISKP}2" oflag=direct status=progress || true

	printf "%s" "$encryption_password" | cryptsetup luksFormat "${DISKP}2" -
	printf "%s" "$encryption_password" | cryptsetup open "${DISKP}2" cryptlvm -

	pvcreate /dev/mapper/cryptlvm
	vgcreate SysDiskGroup /dev/mapper/cryptlvm
	lvcreate -L 2G SysDiskGroup -n swap
	lvcreate -L 16G SysDiskGroup -n root
	lvcreate -l 100%FREE SysDiskGroup -n home

	mkfs.ext4 /dev/SysDiskGroup/root
	mkfs.ext4 /dev/SysDiskGroup/home
	mkswap /dev/SysDiskGroup/swap
	mkfs.fat -F32 "${DISKP}1"

	swapon /dev/SysDiskGroup/swap

	mount /dev/SysDiskGroup/root /mnt
	mount --mkdir /dev/SysDiskGroup/home /mnt/home
	mount --mkdir "${DISKP}1" /mnt/boot
	
	# section:base-installation
	#basestrap /mnt base base-devel linux linux-firmware runit elogind-runit connman connman-runit grub cryptsetup lvm2 lvm2-runit zsh dash
	basestrap /mnt base base-devel linux linux-firmware openrc elogind-openrc connman connman-openrc grub cryptsetup lvm2 lvm2-openrc zsh dash
	fstabgen -U /mnt >>/mnt/etc/fstab

	# section:bootstrap
	cp "$0" "/mnt/root/$self_name"
	lsblk -f >/mnt/root/disks-info.txt
	artix-chroot /mnt /bin/sh -c "sh /root/$self_name -b $username $password $root_password"
	
	# section:finalization
	rm -f "/mnt/root/$self_name"
	umount -R /mnt

elif $bootstrap; then

	# section:base-timezone
	ln -sf /usr/share/zoneinfo/UTC /etc/localtime
	hwclock --systohc
	
	# section:base-localization
	echo "
	en_US.UTF-8 UTF-8
	en_US ISO-8859-1" >>/etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" >/etc/locale.conf
	
	# section:base-networking
	echo "$HOSTNAME" >/etc/hostname
	echo "
	127.0.0.1	localhost
	::1		localhost
	127.0.0.1	$HOSTNAME.localdomain $HOSTNAME" >>/etc/hosts
	#ln -s /etc/runit/sv/connmand /etc/runit/runsvdir/default
	rc-update add connmand

	# section:base-system-shell
	unlink /bin/sh
	ln -s /usr/bin/dash /bin/sh
	
	# section:base-users
	echo "root:$root_password" | chpasswd
	useradd -m -G wheel -s /bin/zsh "$username"
	echo "$username:$password" | chpasswd
	echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-runart

	# section:base-update-hooks
	sed -i 's/^HOOKS=(.*)$/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
	
	#mkinitcpio -P
	mkinitcpio -p linux

	dbus-uuidgen >/var/lib/dbus/machine-id
	
	# section:base-boot
	# adding important partitions to default grub config
	ppartname="$( basename "${DISKP}2" )"
	ppartuuid="$( awk "/$ppartname/ { print \$4; }" /root/disks-info.txt )"
	vpartuuid="$( awk '/SysDiskGroup-root/ { print $4; }' /root/disks-info.txt )"
	match_re='^GRUB_CMDLINE_LINUX_DEFAULT=".*"$'
	match="$( grep "$match_re" /etc/default/grub )"
	modified="$( echo "$match" | sed "s/\"$/ cryptdevice=UUID=$ppartuuid:cryptlvm root=UUID=$vpartuuid\"/" )"
	sed -i "s/$match/$modified/" /etc/default/grub

	#grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub "$DISK"
	grub-install --target=i386-pc "$DISK"
	grub-mkconfig -o /boot/grub/grub.cfg

	rm -f /root/disks-info.txt
	
	# section:the-most-important-thing
	rmmod pcspkr
	echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf
	
	# section:advanced-pacman-configuration
	sed -Ei 's/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//' /etc/pacman.conf
	grep -q 'ILoveCandy' /etc/pacman.conf || sed -i '/#VerbosePkgLists/a ILoveCandy' /etc/pacman.conf
	
	# section:advanced-include-universe-repository
	if ! grep -q "^\[universe\]" /etc/pacman.conf; then
		echo "
[universe]
Server = https://universe.artixlinux.org/\$arch
Server = https://mirror1.artixlinux.org/universe/\$arch
Server = https://mirror.pascalpuffke.de/artix-universe/\$arch
Server = https://artixlinux.qontinuum.space/artixlinux/universe/os/\$arch
Server = https://mirror1.cl.netactuate.com/artix/universe/\$arch
Server = https://ftp.crifo.org/artix-universe/" >>/etc/pacman.conf
		pacman --noconfirm -Sy
		pacman-key --init
	fi

	# section:advanced-enable-arch-repositories
	pacman --noconfirm -S wget
	wget $ARCH_LINUX_REPO_LIST -O /etc/pacman.d/mirrorlist-arch
	# uncomment servers for specified country
	temp_list="$( mktemp )"
	awk -v country="$COUNTRY" '/^ *$/ { p = 0; } // { l = $0; } /^#.*/ && p == 1 { sub("^#", "", l); } // { print l; } $0 ~ country { p = 1; }' /etc/pacman.d/mirrorlist-arch >"$temp_list"
	cp "$temp_list" /etc/pacman.d/mirrorlist-arch
	rm -f "$temp_list"
	pacman --noconfirm --needed -S \
		artix-keyring artix-archlinux-support
	for _repo in extra community multilib; do
		grep -q "^\[$_repo\]" /etc/pacman.conf ||
			echo "
[$_repo]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
	done
	pacman --noconfirm -Sy
	pacman-key --populate archlinux

	# section:advanced-makepkg-configuration
	sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

	# section:advanced-package-installation
	pacman --noconfirm -S \
		git \
		ttf-liberation noto-fonts noto-fonts-extra noto-fonts-emoji \
		alacritty \
		xorg-server xorg-xinit xorg-xsetroot \
		xorg-xprop xorg-xdpyinfo xorg-xrandr \
		xf86-video-intel \
		libxinerama libxft \
		udisks2 ntfs-3g \
		libnotify dunst \
		sxiv mpv xwallpaper xclip scrot \
		zsh-syntax-highlighting \
		man-db tree entr \
		htop connman-gtk \
		acpi \
		pulseaudio pavucontrol pamixer \
		vim \
		openssh rsync \
		lua python shellcheck cmake \
		zathura zathura-pdf-mupdf \
		unzip \
		firefox \
		herbstluftwm rofi polybar slock \
		xorg-xbacklight
	
	# section:advanced-dotfiles-installation
	temp_dir="$( sudo -u "$username" mktemp -d )"
	sudo -u "$username" git clone --depth 1 "$DOTFILES" "$temp_dir" && {
		sudo -u "$username" cp -rfT "$temp_dir" "/home/$username"
		sudo -u "$username" rm "/home/$username/LICENSE" "/home/$username/README.md"
	}
	rm -rf "$temp_dir"
	
	# section:advanced-touchpad-tap-click-setting
	[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
		Identifier "libinput touchpad catchall"
		MatchIsTouchpad "on"
		MatchDevicePath "/dev/input/event*"
		Driver "libinput"
		Option "Tapping" "on"
	EndSection' >/etc/X11/xorg.conf.d/40-libinput.conf

	#srcdir="/home/$username/.local/src"

	## section:advanced-yay-installation
	#sudo -u "$username" mkdir -p "$srcdir"
	#sudo -u "$username" git -C "$srcdir" clone --depth 1 \
	#	--signle-branch --no-tags -q "https://aur.archlinux.org/yay.git" \
	#	"$srcdir/yay"
	#sudo -u "$username" -D "$srcdir/yay" makepkg --noconfirm -si

	## section:advanced-custom-neovim-installation
	#sudo -u "$username" git -C "$srcdir" clone \
	#	"https://github.com/neovim/neovim.git" "$srcdir/neovim"
	#sudo -u "$username" make -C "$srcdir/neovim" CMAKE_BUILD_TYPE=RelWithDebInfo
	#sudo -u "$username" make -C "$srcdir/neovim" install
	#sudo -u "$username" git -C "$srcdir" clone \
	#	"https://github.com/bulirma/mynvim.git" "$srcdir/mynvim"
	#sudo -u "$username" ln -s "$srcdir/mynvim" "/home/$username/.config/nvim"
	
else
	print_help
fi
