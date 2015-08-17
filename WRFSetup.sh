#!/usr/bin/env bash
#Grab variables
. variables
fet=$force_extract_tars #for convenience
for param in "$@"; do
	if [ "$param" == "--verbose" ] || [ "$param" == "-v" ]; then
		verbose=true
	fi
done

#Get the command to use when grabbing subscripts from GitHub.
[ "$(which wget)" == "" ] && pull_command="curl -fsSL" || pull_command="wget -qO -"

#Download the update_rc.sh and get_profile.sh scripts from my repo and run their contents within the current shell via an anonymous file descriptor.
. <($pull_command "https://raw.githubusercontent.com/Toberumono/Miscellaneous/master/general/update_rc.sh")
. <($pull_command "https://raw.githubusercontent.com/Toberumono/Miscellaneous/master/general/get_profile.sh")
. <($pull_command "https://raw.githubusercontent.com/Toberumono/Miscellaneous/master/general/unsudo.sh")

########################################################################
#####                       Support Functions                      #####
########################################################################

#echos 1 if the directory exists and has files in it
unpacked_test() {
	[ -d "$1" ] && [ "$(ls -A $1)" != "" ] && echo "1" || echo "0"
}

#Takes folder to test, tarball name, tar parameters, should it add '../' to the test path for the -C component
#The last two arguments are optional,
unpack_wrf_tarball() {
	[ "$#" -gt "2" ] && local params="$3" || local params="-xz"
	if ( ! $fet ) && [ "$(unpacked_test $1)" -eq "1" ]; then
		echo "Already unpacked the $2 tarball.  Skipping."
	else
		[ ! -e "$2" ] && return 1
		( [ "$#" -lt "4" ] || ( $4 ) ) && local outpath="$1/../" || local outpath="$1"
		$unsudo mkdir -p "$1"
		$unsudo pv "$2" | $unsudo tar $params "-C" "$outpath"
		echo "Unpacked the $2 tarball"
	fi
	return 0
}

unpack_fail() {
	read -n1 -p "$1 has not been unpacked and no $1 tarball was found. [Press Enter to continue, any other key to quit] " yn
	[ "$yn" != "" ] && echo "" && exit 1 || echo "Continuing"
	unset yn
}

#name of namelist file, is it a backup or a restore (must equal "back up" or "restore"), path to folder with namelist file relative to directory (without a trailing '/') (optional)
backup_restore_namelist() {
	[ "$#" -gt "2" ] && [ "$3" != "" ] && local np="$3" || local np="."
	if [ -e "$np/$1" ]; then
		[ "$2" == "back up" ] && $unsudo cp "$np/$1" "$backup_dir/$1.back" || $unsudo cp "$backup_dir/$1.back" "$np/$1"
	else
		echo "No $1 to $2."
	fi
}

#########################################################################
#####            Unusual Variable Settings Confirmations            #####
#########################################################################

if ( ! $keep_namelists ); then
	read -p "keep_namelists in 'variables' is currently set to false. If you proceed, you will loose any existing namelist files. Is this okay? [y/N] " yn
	yn=$(echo "${yn:0:1}" | tr '[:upper:]' '[:lower:]')
	if [ "$yn" != "y" ]; then
		keep_namelists=true
		echo "Changed keep_namelists to true for this run. Please change the value in 'variables' if you wish to avoid this prompt."
	else
		read -p "Leaving keep_namelists false. Some existing namelists may be deleted. Press [Enter] to continue."
	fi
	unset yn
fi

#########################################################################
#####                       Installation Logic                      #####
#########################################################################

checkable="pv git wget gcc gfortran ncl csh m4 doxygen"
#Install necessary software
if [ "$(which apt)" != "" ]; then
	echo "Using apt."
	if [ "$unsudo" == "" ]; then
		echo "No sudo.  Skipping installation."
	else
		installation="build-essential pv gcc gfortran git wget curl libjasper-dev jasper zlib1g zlib1g-dev libncarg0 libpng12-0 libpng12-dev libx11-dev"
		installation=$installation" libcairo2-dev libpixman-1-dev csh m4 doxygen libhdf5-dev libnetcdf-dev netcdf-bin ncl-ncarg mpich"
		apt-get install $installation
	fi
elif [ "$(which yum)" != "" ]; then
	echo "Using yum."
	if [ "$unsudo" == "" ]; then
		echo "No sudo.  Skipping installation."
	else
		installation="git wget jasper jasper-libs jasper-devel zlib zlib-devel libpng12 libpng12-devel libX11 libX11-devel"
		installation=$installation" cairo cairo-devel pixman pixman-devel m4 doxygen hdf5 hdf5-devel netcdf netcdf-fortran"
		installation=$installation" netcdf-devel netcdf-fortran-devel mpich tcsh"
		yum groupinstall 'Development Tools' && yum install $installation
	fi
elif [ "$(which brew)" != "" ]; then
	echo "Using brew."
	fortran_flag=""
	( $verbose ) && brew="brew -v" || brew="brew"
	installation="pv ncurses cairo libpng szip lzlib pixman doxygen mpich2 --build-from-source tcsh hdf5 jasper"
	#Install prep software
	[ "$(which git)" == "" ] && brew install "git"		|| echo "Found git"
	[ "$(which wget)" == "" ] && brew install "wget"	|| echo "Found wget"
	$unsudo $brew tap homebrew/science homebrew/dupes caskroom/cask
	#If any of gcc, g++, or gfortran is not installed, install one via Homebrew.
	if [ "$(which gcc)" == "" ] || [ "$(which gfortran)" == "" ] || [ "$(which g++)" == "" ]; then
		($pull_command "https://raw.githubusercontent.com/Toberumono/Miscellaneous/master/general/brew_gcc.sh") | $unsudo bash
		source "$profile"
		fortran_flag="--default-fortran-flags"
	fi
	$unsudo $brew cask install ncar-ncl
	ncl_current="$(brew --prefix)/ncl-current"
	[ -e "$ncl_current" ] && rm "$ncl_current"
	ncl_cask="$(ls -td -1 $(brew --prefix)/ncl-* | head -1)"
	ln -sf "$ncl_cask" "$ncl_current"
	update_rc "Brewed NCAR-NCL" "$profile" "NCARG_ROOT=$ncl_current" 'PATH="'"$ncl_current"'/bin:$PATH"' \
		'DYLD_FALLBACK_LIBRARY_PATH='"$(dirname $(gfortran --print-file-name libgfortran.3.dylib))"':$DYLD_FALLBACK_LIBRARY_PATH'
	source "$profile"
	[ "$(which m4)" == "" ] && installation="m4 "$installation || echo "Found m4"
	installation="$installation netcdf"' --with-fortran --with-cxx-compat'
	$unsudo $brew install $fortran_flag $installation
else
	echo "Could not find apt, yum, or brew.  Proceed without attempting to install support software and libraries?"
	read -n1 -p "Press Enter to continue, any other key to quit." yn
	if [ "$yn" != "" ]; then
		echo ""
		echo "Setup Canceled.  Quitting."
		exit 1;
	else
		echo "Continuing without attempting to install support software and libraries."
	fi
fi

failed=""
for item in $checkable; do
	[ "$(which $item)" == "" ] && failed="$failed $item"
done
[ "$(which mpicc)" == "" ] || [ "$(which mpif90)" == "" ] && failed="$failed mpich"
[ "$(which nc-config)" == "" ] && failed="$failed netcdf"

if [ "$failed" != "" ]; then
	echo "Failed to install:${failed}."
	echo "Please install these items manually or try running this again with sudo privileges."
	exit 1
fi

#Rename .tars to correct capitalization
wrf_tar="WRFV$wrf_version"
wps_tar="WPSV$wrf_version"
chm_tar="WRFV$wrf_major_version-Chem-$wrf_version"

[ -e "$wrf_tar.TAR.gz" ] && $unsudo mv "$wrf_tar.TAR.gz" "$wrf_tar.tar.gz"
[ -e "$wps_tar.TAR.gz" ] && $unsudo mv "$wps_tar.TAR.gz" "$wps_tar.tar.gz"
[ -e "$chm_tar.TAR.gz" ] && $unsudo mv "$chm_tar.TAR.gz" "$chm_tar.tar.gz"

#Unpack tars if needed
( $verbose ) && verbose_unpack="v" || verbose_unpack=""
unpack_wrf_tarball "$wrf_path" "$wrf_tar.tar.gz" "-xz${verbose_unpack}"
[ $? != 0 ] && unpack_fail "WRF"

unpack_wrf_tarball "$wps_path" "$wps_tar.tar.gz" "-xz${verbose_unpack}"
[ $? != 0 ] && unpack_fail "WPS"

unpack_wrf_tarball "$wrf_chem_path" "$chm_tar.tar.gz" "-xz${verbose_unpack}"
[ $? != 0 ] && unpack_fail "WRF-Chem"

unpack_wrf_tarball "$geog_path" "geog_complete.tar.bz2" "-xj${verbose_unpack}" false
if [ $? != 0 ]; then
	unpack_wrf_tarball "$geog_path" "geog_minimum.tar.bz2" "-xj${verbose_unpack}" false
	[ $? != 0 ] && unpack_fail "GEOGRID"
fi

netcdf_prefix="$(nc-config --prefix)"

#Set environment variables
if [ "$unsudo" == "" ]; then #Export variables for when this script is not run with sudo.
	export WRFIO_NCD_LARGE_FILE_SUPPORT=1
	export NETCDF=$netcdf_prefix
	export $mpich_compilers
else #Add the environment variables to $unsudo
	unsudo=$unsudo" WRFIO_NCD_LARGE_FILE_SUPPORT=1 NETCDF=$netcdf_prefix $mpich_compilers"
fi

#Configure and Compile
yn="y"
if [ -e "$wrf_path/run/wrf.exe" ]; then
	read -p "WRF has already been compiled. Would you like to recompile it? [y/N] " yn
	yn=$(echo "${yn:0:1}" | tr '[:upper:]' '[:lower:]')
fi
if [ "$yn" == "y" ]; then
	cd $wrf_path #Starting WRF

	#Back up namelist.input
	( $keep_namelists ) && ( backup_restore_namelist "namelist.input" "back up" "./run" ) || echo "Skipping backing up the WRF Namelist file."
	$unsudo ./configure 2>&1 | $unsudo tee ./configure.log #Configure WRF, and output to both a log file and the terminal.

	#Run the WRF regex fixes if they are enabled in 'variables'
	#This just adds -lgomp to the LIB_EXTERNAL variable.
	( $use_wrf_regex_fixes ) && $unsudo perl -0777 -i -pe 's/(LIB_EXTERNAL[ \t]*=([^\\\n]*\\\n)*[^\n]*)\n/$1 -lgomp\n/is' ./configure.wrf || echo "Skipping WRF regex fixes."

	#$unsudo ./compile wrf 2>&1 | $unsudo tee ./compile_wrf.log #Compile WRF, and output to both a log file and the terminal.
	$unsudo ./compile #Calling compile without arguments causes a list of valid test cases and such to be printed to the terminal.

	echo "Please enter the test case you would like to run (this can include the '-j n' part) or wrf [Default: wrf]:"
	read test_case
	test_case=$(echo "$test_case" | tr '[:upper:]' '[:lower:]')
	[ "$test_case" == "" ] && b="wrf" || b="$test_case"
	$unsudo ./compile "$b" 2>&1 | $unsudo tee ./compile_"$b".log
	
	#Restore namelist.input
	( $keep_namelists ) && ( backup_restore_namelist "namelist.input" "restore" "./run" ) || echo "Skipping restoring the WRF Namelist file."

	cd ../ #Finished WRF
else
	echo "Skipping reconfiguring and recompiling WRF."
fi

yn="y"
if [ -e "$wps_path/geogrid.exe" ] && [ -e "$wps_path/metgrid.exe" ] && [ -e "$wps_path/ungrib.exe" ]; then
	read -p "WPS has already been compiled. Would you like to recompile it? [y/N] " yn
	yn=$(echo "${yn:0:1}" | tr '[:upper:]' '[:lower:]')
fi
if [ "$yn" == "y" ]; then
	cd $wps_path #Starting WPS

	#Back up namelist.wps
	( $keep_namelists ) && ( backup_restore_namelist "namelist.wps" "back up" ) || echo "Skipping backing up the WPS Namelist file."

	$unsudo ./configure #2>&1 | $unsudo tee ./configure.log #The WPS configure does something that messes with logging, so this is disabled for now.
	echo "For reasons unknown, WPS's configure sometimes adds invalid command line options to DM_FC and DM_CC and neglects to add some required links to NCARG_LIBS."
	echo "However, this script fixes those problems, so... No need to worry about it."
	if ( $use_wps_regex_fixes ); then
		#Remove -f90 and -cc from the configure.wps file
		$unsudo perl -0777 -i -pe 's/[ \t]*(-f90=($\([^\(]*\))|[^ \t\n]*)|-cc=($\([^\(]*\))|[^ \t\n]*)*)[ \t]*//igs' ./configure.wps
		#Add -lcairo, -lfontconfig, -lpixman-1, and -lfreetype to NCARG_LIBS
		$unsudo perl -0777 -i -pe 's/(NCARG_LIBS[ \t]*=([^\\\n]*\\\n)*[^\n]*)\n/$1 -lcairo -lfontconfig -lpixman-1 -lfreetype\n/is' ./configure.wps
		#Add -lgomp to WRF_LIBS
		$unsudo perl -0777 -i -pe 's/(WRF_LIB[ \t]*=([^\\\n]*\\\n)*[^\n]*)\n/$1 -lgomp\n/is' ./configure.wps
	else
		echo "Skipping WPS regex fixes."
	fi
	$unsudo ./compile 2>&1 | $unsudo tee ./compile.log
	$unsudo ./compile plotgrids 2>&1 | $unsudo tee ./compile_plotgrids.log

	#Restore namelist.wps
	( $keep_namelists ) && ( backup_restore_namelist "namelist.wps" "restore" ) || echo "Skipping restoring the WPS Namelist file."

	cd ../ #Finished WPS
else
	echo "Skipping reconfiguring and recompiling WPS."
fi

echo "Please confirm that all of the executables have been appropriately created in the WRFV$wrf_major_version and WPS directories."
echo "You will still need to get boundary data for your simulations.  If you want an automated script to do this, see my WRF-Runner project at github.com/Toberumono/WRF-Runner"
