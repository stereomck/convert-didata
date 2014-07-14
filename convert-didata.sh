#!/bin/bash

# VARIABLES and CONSTANTS
INPUT_DIR="/Users/mkent/DiDataTest/adapter/input"
OUTPUT_DIR="/Users/mkent/DiDataTest/adapter/output"
ARCHIVE_DIR="/Users/mkent/DiDataTest/adapter/archive"
BACKUP_DIR="/Users/mkent/DiDataTest/adapter/backup"
PROCESS_DIR="/Users/mkent/DiDataTest/adapter/processing"
DIR_SUFFIX="`date +%s`"
OVF_TOOL="/Applications/VMware OVF Tool/ovftool"

#FUNCTIONS and SUBROUTINES
#FUNCTION: main - keeps main logic up top
function main {
	echo "#-Starting Conversions ..."
	
	cd $INPUT_DIR
	for D in *; do
        if [ -d "${D}" ]; then
            echo "--Processing ${D} ..."
            echo "---Backing up files to backup directory ..."
            cp -R "${D}" "${BACKUP_DIR}"/"${D}"
            echo "---Backup Complete."
            echo "---Moving ${D} to processing directory ..."
            mv "${D}" "${PROCESS_DIR}"
            #TODO: prevent duplicate named directories.
            echo "---Move Complete."
            
            #Set the "Name" to the folder name. This is for the manifest later
            echo "---Setting workload name ..."
            NAME="${D}"
            echo "---Name of workload is ${D}."
            
            #Set the ovf path
            echo "---Setting OVF Path ..."
            OVF_PATH=$(find "${PROCESS_DIR}"/"${D}" -name "*.ovf")
            echo "---OVF Path is ${OVF_PATH}."
            
            #Set the ovf filename
            echo "---Setting OVF filename"
            OVF_FILE="${OVF_PATH##*/}"
            echo "---OVF Filename is ${OVF_FILE}."
            
            #Set the OVF File name without extension
            echo "---Setting OVF Name - no ext"
            OVF_PRE="${OVF_FILE%.*}"
            echo "---OVF Name -no ext- is ${OVF_PRE}"
            
            #Make sure that the disks are at least 10GB
            ensure10GBMinDisk
            
            #Make sure that if the OS is CentOS, we set it to RHEL
            ensureRHEL
            
            #Make sure that a NIC and Network is specified
            ensureNIC
            
            #Make sure the VMDK has toolsVersion
            ensureVMToolsVersion
            
            #Generate the Manifest
            generateManifest
            
            # Unset Vars
            D=""
            NAME=""
            OVF_PATH=""
            OVF_FILE=""
            echo "--Processing ${D} complete."
        fi  
	done
	echo  "#-Conversions Complete."
}

#FUNCTION: ensure10GBMinDisk - Ensure that the disks are at least 10GB
function ensure10GBMinDisk() {
    echo "---Ensure Disks are at least 10GB ..."
    check=$(sed -n '/ovf:capacity="[0-9]" ovf:capacityAllocationUnits="byte \* 2\^30"/p' $OVF_PATH | wc -l)
    if [ "$check" != "0" ]; then
    	echo "----###Updating Disk Capacity to 10GB ..."
    	sed -i.bak 's/ovf:capacity="[0-9]" ovf:capacityAllocationUnits="byte \* 2\^30"/ovf:capacity="10" ovf:capacityAllocationUnits="byte \* 2\^30"/g' $OVF_PATH
	fi
	echo "---Ensure Disks Complete."
}

#FUNCTION: ensureRHEL - Relabel CentOS to RHEL
function ensureRHEL {
	# Find Potentially incompatible CentOS OS Versions
	# Look for CentOS and switch to equiv RHEL
	# centOS6 32: id=106;osType=centosGuest
	# centOS6 64: id=107;osType=centos64Guest
	# rhel6 32: id=79;osType=rhel6Guest
	# rhel6 64: id=80;osType=rhel6_64Guest
	echo "---Ensure OS: CentOS operating systems are changed to RHEL equiv ..."
	# TODO: Add support for matching id and ostype for cent and changing it to rhel
	#sed -i.bak 's/<OperatingSystemSection ovf:id="93" vmw:osType="ubuntuGuest">/<OperatingSystemSection ovf:id="93" vmw:osType="ubuntuGuest">/g' $OVF_PATH
	echo "---Ensure OS Complete."
}

#FUNCTION: ensureNIC - Make sure a NIC is present in the OVF
function ensureNIC {
	CONVERT="0"
	echo "---Ensure NIC settings ..."
	# Is there a networks section
	echo "----Checking Networks Section ..."
	NETWORKS=$("${OVF_TOOL}" "$OVF_PATH" | grep Networks: | wc -l)
    
    if [ "$NETWORKS" = "0" ]; then
        echo "----Unable to locate Networks Section ${NETWORKS} ..."
    	CONVERT="1"
    else
        echo "----Networks Section found."
    fi
    
    echo "----Checking NICs Section ..."
    NICS=$("${OVF_TOOL}" "$OVF_PATH" | grep Networks: | wc -l)
    
    if [ "$NICS" = "0" ]; then
        echo "----Unable to locate NIC ${NICS} ..."
    	CONVERT="1"
    else
        echo "----NIC Found."
    fi
    
    if [ "$CONVERT" = "0" ]; then
    	echo "----Need to Convert"
    	convertOVFtoVMX
    	addNIC
    	convertVMXtoOVF
    fi
    
    NETWORKS=""
    NIC="" 
    CONVERT="" 
    
    echo "----Checking NIC Section Complete."
    echo "----Checking Networks Section Complete."
    echo "----Ensure NIC Settings Complete."
}

#FUNCTION: convertOVFtoVMX - Convert to VMX to ease adding a nic properly
function convertOVFtoVMX {
    echo "----Converting OVF to VMX ..."
    "${OVF_TOOL}" "${OVF_PATH}" "${PROCESS_DIR}"/"${NAME}"/VMX/"${NAME}".vmx
    cp "${OVF_PATH}" "${PROCESS_DIR}"/"${NAME}"/"${OVF_PRE}"_ovf
    echo "----Conversion Complete."
}

#FUNCTION: addNIC - Add NIC properties to VMX
function addNIC {
    echo "----###Adding NIC Sections to VMX ..."
    echo ethernet0.present = "TRUE" >> "${PROCESS_DIR}"/"${NAME}"/VMX/"${NAME}".vmwarevm/"${NAME}".vmx
    echo ethernet0.connectionType = "bridged" >> "${PROCESS_DIR}"/"${NAME}"/VMX/"${NAME}".vmwarevm/"${NAME}".vmx
    echo ethernet0.wakeOnPcktRcv = "FALSE" >> "${PROCESS_DIR}"/"${NAME}"/VMX/"${NAME}".vmwarevm/"${NAME}".vmx
    echo ethernet0.addressType = "generated" >> "${PROCESS_DIR}"/"${NAME}"/VMX/"${NAME}".vmwarevm/"${NAME}".vmx
    echo ethernet0.linkStatePropagation.enable = "TRUE" >> "${PROCESS_DIR}"/"${NAME}"/VMX/"${NAME}".vmwarevm/"${NAME}".vmx
    echo ethernet0.generatedAddress = "00:0c:29:d7:39:09" >> "${PROCESS_DIR}"/"${NAME}"/VMX/"${NAME}".vmwarevm/"${NAME}".vmx
    echo ethernet0.generatedAddressOffset = "0" >> "${PROCESS_DIR}"/"${NAME}"/VMX/"${NAME}".vmwarevm/"${NAME}".vmx
    echo "----Add NIC Sections Complete."
}

#FUNCTION: convertVMXtoOVF - Once NIC has been added, convert back
function convertVMXtoOVF {
    echo "----Converting VMX to OVF ..."
    "${OVF_TOOL}" "${PROCESS_DIR}"/"${NAME}"/VMX/"${NAME}".vmwarevm/"${NAME}".vmx "${PROCESS_DIR}"/"${NAME}".ovf
    echo "----Conversion Complete."
}

#FUNCTION: ensureVMToolsVersion - This function ensures that the VMDK has an appropriate ddb.toolsVersion.
function ensureVMToolsVersion {
	echo "---Ensuring VMTools ..."
	for f in "${PROCESS_DIR}"/"${NAME}"/*.vmdk; do
		echo "----Checking VMDK for tools in ${f}..."
		TOOLS=$(LC_ALL=C sed -n '/ddb.toolsVersion = "8384"/p' "${f}" | wc -l)
		echo $TOOLS
        if [ $TOOLS = 0 ]; then
			addVMTools $f
        else
            echo "----ddb.toolsVersion Exists."
		fi
		TOOLS=""
	done
	echo "---Ensure VMTools Complete."
}

#FUNCTION: addVMToolsVersion - If no dd.toolsVersion is found, add it.
function addVMTools() {
	echo "----###Adding ddb.toolsVersion ..."
	DESC="${PROCESS_DIR}"/"${NAME}"/"descriptor.txt"
	dd if=$1 of=$DESC bs=1 skip=512 count=1024
    LC_ALL=C sed -i.bak '/ddb.virtualHWVersion = "6"/a ddb.toolsVersion = "8384"' $DESC
    dd conv=notrunc if=$DESC of=$1 bs=1 seek=512 count=1024
    DESC=""
    echo "----Add Complete."
}

#FUNCTION: generateManifest - Generate Manifest file with folder name
function generateManifest {
	echo "----Generating Manifest ..."
	OVF_BAK=$(find "${PROCESS_DIR}"/TEST -name *_ovf | wc -l)
	CUR_DIR="${PWD}"
	cd "${PROCESS_DIR}"/"${NAME}"
	
	if [ $OVF_BAK = 1 ]; then
		echo "----Backup file exists, generating manifest based on converted OVF ..."
		openssl sha1 "${NAME}"*.vmdk "${NAME}".ovf > "${NAME}".mf
	else
		echo "----Generating manifest based on original ..."
		openssl sha1 "${OVF_PRE}"*.vmdk "${OVF_FILE}" > "${NAME}".mf
	fi

	cd "${CUR_DIR}"
	CUR_DIR=""
	echo "----Generate Manifest Complete."	
}

main