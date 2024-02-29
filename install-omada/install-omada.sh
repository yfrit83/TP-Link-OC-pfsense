#!/bin/sh

# install-omada.sh
# Install the TP-Link Omada Controller software on a FreeBSD machine (presumably running pfSense).

# The latest version of Omada Controller:
OMADA_SOFTWARE_URL="https://static.tp-link.com/upload/software/2024/202401/20240112/Omada_SDN_Controller_v5.13.23_linux_x64.tar.gz"


# The rc script associated with this branch or fork:
RC_SCRIPT_URL="https://raw.githubusercontent.com/yfrit83/TP-Link-OC-pfsense/master/rc.d/omada.sh"

JRE_HOME="/usr/local/openjdk8/jre"

CURRENT_MONGODB_VERSION=mongodb42

# If pkg-ng is not yet installed, bootstrap it:
if ! /usr/sbin/pkg -N 2> /dev/null; then
  echo "FreeBSD pkgng not installed. Installing..."
  env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg bootstrap
  echo " done."
fi

# If installation failed, exit:
if ! /usr/sbin/pkg -N 2> /dev/null; then
  echo "ERROR: pkgng installation failed. Exiting."
  exit 1
fi

# Determine this installation's Application Binary Interface
ABI=`/usr/sbin/pkg config abi`

# FreeBSD package source:
FREEBSD_PACKAGE_URL="https://pkg.freebsd.org/${ABI}/latest/"

# FreeBSD package list:
FREEBSD_PACKAGE_LIST_URL="${FREEBSD_PACKAGE_URL}packagesite.pkg"

# Stop the controller if it's already running...
# First let's try the rc script if it exists:
if [ -f /usr/local/etc/rc.d/omada.sh ]; then
  echo -n "Stopping the omada service..."
  /usr/sbin/service omada.sh stop
  echo " done."
fi

# Then to be doubly sure, let's make sure omada *.jar isn't running for some other reason:
if [ $(ps ax | grep "eap.home=/opt/tplink/EAPController") -ne 0 ]; then
  echo -n "Killing ace.jar process..."
  /bin/kill -15 `ps ax | grep "eap.home=/opt/tplink/EAPController" | awk '{ print $1 }'`
  echo " done."
fi

# And then make sure mongodb doesn't have the db file open:
if [ $(ps ax | grep -c "/opt/tplink/EAPController/data/[d]b") -ne 0 ]; then
  echo -n "Killing mongod process..."
  /bin/kill -15 `ps ax | grep "/opt/tplink/EAPController/data/[d]b" | awk '{ print $1 }'`
  echo " done."
fi

# Repairs Mongodb database in case of corruption
mongod --dbpath /opt/tplink/EAPController/data/db --repair

# If an installation exists, we'll need to back up configuration:
if [ -d /opt/tplink/EAPController/data ]; then
  echo "Backing up omada data..."
  BACKUPFILE=/var/backups/omadac-`date +"%Y%m%d_%H%M%S"`.tgz
  /usr/bin/tar -vczf ${BACKUPFILE} /opt/tplink/EAPController/data
fi

# Add the fstab entries apparently required for OpenJDKse:
if [ $(grep -c fdesc /etc/fstab) -eq 0 ]; then
  echo -n "Adding fdesc filesystem to /etc/fstab..."
  echo -e "fdesc\t\t\t/dev/fd\t\tfdescfs\trw\t\t0\t0" >> /etc/fstab
  echo " done."
fi

if [ $(grep -c proc /etc/fstab) -eq 0 ]; then
  echo -n "Adding procfs filesystem to /etc/fstab..."
  echo -e "proc\t\t\t/proc\t\tprocfs\trw\t\t0\t0" >> /etc/fstab
  echo " done."
fi

# Run mount to mount the two new filesystems:
echo -n "Mounting new filesystems..."
/sbin/mount -a
echo " done."


echo "Removing discontinued packages..."
old_mongos=`pkg info | grep mongodb | grep -v ${CURRENT_MONGODB_VERSION}`
for old_mongo in "${old_mongos}"; do
  package=`echo "$old_mongo" | cut -d' ' -f1`
  pkg unlock -yq ${package}
  env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg delete ${package}
done
echo " done."



# Install mongodb, OpenJDK, and tar (required to unpack Omada download):
# -F skips a package if it's already installed, without throwing an error.
echo "Installing required packages..."
#uncomment below for pfSense 2.2.x:
#env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install mongodb openjdk unzip pcre v8 snappy

fetch ${FREEBSD_PACKAGE_LIST_URL}
tar vfx packagesite.pkg

AddPkg () {
  pkgname=$1
  pkg unlock -yq $pkgname
  pkginfo=`grep "\"name\":\"$pkgname\"" packagesite.yaml`
  pkgvers=`echo $pkginfo | pcregrep -o1 '"version":"(.*?)"' | head -1`
  pkgurl="${FREEBSD_PACKAGE_URL}`echo $pkginfo | pcregrep -o1 '"path":"(.*?)"' | head -1`"

  # compare version for update/install
  if [ `pkg info | grep -c $pkgname-$pkgvers` -eq 1 ]; then
    echo "Package $pkgname-$pkgvers already installed."
  else
    env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg add -f "$pkgurl" || exit 1

    # if update openjdk8 then force detele snappyjava to reinstall for new version of openjdk
    if [ "$pkgname" == "openjdk8" ]; then
      pkg unlock -yq snappyjava
      env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg delete snappyjava
    fi
  fi
  pkg lock -yq $pkgname
}

#Add the following Packages for installation or reinstallation (if something was removed)
AddPkg png
AddPkg brotli
AddPkg freetype2
AddPkg fontconfig
AddPkg alsa-lib
AddPkg mpdecimal
AddPkg python37
AddPkg libfontenc
AddPkg mkfontscale
AddPkg dejavu
AddPkg giflib
AddPkg xorgproto
AddPkg libXdmcp
AddPkg libXau
AddPkg libxcb
AddPkg libICE
AddPkg libSM
AddPkg libX11
AddPkg libXfixes
AddPkg libXext
AddPkg libXi
AddPkg libXt
AddPkg libXtst
AddPkg libXrender
AddPkg libinotify
AddPkg javavmwrapper
AddPkg java-zoneinfo
AddPkg openjdk8
#AddPkg snappyjava
#AddPkg snappy
AddPkg cyrus-sasl
AddPkg icu
AddPkg boost-libs
AddPkg ${CURRENT_MONGODB_VERSION}
AddPkg unzip
AddPkg pcre

# Clean up downloaded package manifest:
rm packagesite.*

echo " done."

# Switch to a temp directory for the OMADA Controller download:
cd `mktemp -d -t tplink`

# Download the controller from Ubiquiti (assuming acceptance of the EULA):
echo -n "Downloading the omada controller software..."
/usr/bin/fetch ${OMADA_SOFTWARE_URL} -o Omada_Controller.tar.gz
echo " done."

# Unpack the archive into the /usr/local directory:
# (the -o option overwrites the existing files without complaining)
echo -n "Installing OMADA Controller in /opt/tplink/EAPController..."
mkdir -p /opt/tplink/EAPController
tar -xvzC /opt/tplink/EAPController -f Omada_Controller.tar.gz --strip-components=1
echo " done."

# Update OMADA's symbolic link for mongod to point to the version we just installed:
echo -n "Updating mongod link..."
/bin/ln -sf /usr/local/bin/mongod /opt/tplink/EAPController/bin/mongod
/bin/ln -sf /usr/local/bin/mongo /opt/tplink/EAPController/bin/mongo
echo " done."

# Update OMADA's symbolic link for Java to point to the version we just installed:
echo -n "Updating Java link..."
/bin/ln -sf ${JAVA_HOME} /opt/tplink/EAPController/jre
echo " done."

# Fetch the rc script from github:
echo -n "Installing rc script..."
/usr/bin/fetch -o /usr/local/etc/rc.d/omada.sh ${RC_SCRIPT_URL}
echo " done."

# Fix permissions so it'll run
chmod +x /usr/local/etc/rc.d/omada.sh

# Add the startup variable to rc.conf.local.
# Eventually, this step will need to be folded into pfSense, which manages the main rc.conf.
# In the following comparison, we expect the 'or' operator to short-circuit, to make sure the file exists and avoid grep throwing an error.
if [ ! -f /etc/rc.conf.local ] || [ $(grep -c omada_enable /etc/rc.conf.local) -eq 0 ]; then
  echo -n "Enabling the omada service..."
  echo "omada_enable=YES" >> /etc/rc.conf.local
  echo " done."
fi

# Restore the backup:
if [ ! -z "${BACKUPFILE}" ] && [ -f ${BACKUPFILE} ]; then
  echo "Restoring omadac data..."
  mv /opt/tplink/EAPController/data /opt/tplink/EAPController/data-`date +%Y%m%d-%H%M`
  /usr/bin/tar -vxzf ${BACKUPFILE} -C /
fi

# Start it up:
echo -n "Starting the omada service..."
/usr/sbin/service omada.sh start
echo " done."
