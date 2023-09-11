#!/bin/bash
#########################################
## sftpUtil Script
#########################################

#running the script 
#sh sftpUtil.sh JOB_NAME

#Directory Configs.
CONFIG_FILE=/opt/knowesis/opolo/telstra/scripts/test/sftpUtil-so.config
LOG_DIR=/opt/knowesis/sift/scripts/log
DATE_LOG=$(date +"%Y%m")
LOG_FILE=$LOG_DIR/sftpUtil_$DATE_LOG.log
#Configs read from sftpUtil.config
SOURCE_PATH=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $2}')
FILENAME_PATTERN=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $3}')
FNAME=$(eval echo $FILENAME_PATTERN)
DESTINATION_USER=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $4}')
DESTINATION_SERVER=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $5}')
DESTINATION_PATH=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $6}')
ENC_DEC=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $7}')
SPLIT_COUNT=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $8}')
PGP_USER_ID=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $9}')
KEY_FILE=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $10}')
MODE=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $11}')
REMOVE_FIRST_LINE=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $12}')
COMPRS_DECMPRS=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $13}')
CHARS_TO_REMOVE=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $14}')
PROCESSED_DIR=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $15}')
CHECK_FOR_EOT=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $16}')
OUTPUT_EXTENSION=$(grep ^$1~ $CONFIG_FILE | awk -F'~' '{print $17}')

if [ "$1" == "help" ]
then
    clear
    echo " #    # ###### #      #####  "
    echo " #    # #      #      #    # "
    echo " ###### #####  #      #    # "
    echo " #    # #      #      #####  "
    echo " #    # #      #      #      "
    echo " #    # ###### ###### #      "
    echo ""                             
    echo "Run the script using the following command : bash sftpUtil.sh JOB_NAME"
    echo "-  -  -  -  -  -  -  -  -  -  -  -  -  -  -"
    echo ""
    echo "You can configure the confiuration file as follows :"
    echo "-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -"

    #to-do
    echo "1. JOB_NAME = "
    echo "2. SOURCE_PATH = "
    echo "3. FILENAME_PATTERN = "
    echo "4. DESTINATION_USER = "
    echo "5. DESTINATION_SERVER = "
    echo "6. DESTINATION_PATH = "
    echo "7. ENCRYPT OR DECRYPT = "
    echo "8. SPLIT COUNT = "
    echo "9. PGP_USER_ID = "
    echo "10. KEY_FILE = "   
    echo "11. MODE = "   
    echo "12. REMOVE_FIRST_LINE = "
    echo "13. COMPRS_DECMPRS = "
    echo "14. CHARS_TO_REMOVE = "
    echo "15. PROCESSED_DIR = "
    echo "16. CHECK_FOR_EOT = "
    echo "17. OUTPUT_EXTENSION = "
    echo ""
    echo "Following is the configuration file :"
    echo "-  -  -  -  -  -  -  -  -  -  -  -  -"
    echo ""
    cat $CONFIG_FILE
    echo ""
    echo "Logs are created in the following directory : $LOG_DIR"
    echo "-  -  -  -  -  -  -  -  -  -  -  -  -  -"
    echo ""
    exit 0
fi

#Logger Function
function logger {
    echo "$(date) | $1" >> $LOG_FILE
}

#Function to perform Encryption & Decryption
function encDec {
    status=0
    if [ $ENC_DEC == "ENC" ]
    then
        gpg -o $1.pgp -r $PGP_USER_ID -e $1
        status=$?
    elif [ $ENC_DEC == "DEC" ]
    then
        logger "INFO  | Decrypting $1 and generating $2"
        gpg --ignore-mdc-error -o $2 -d $1
        status=$?
        logger "INFO  | Descryption done with status : $status"
        tr -cd '\11\12\15\40-\176' < $2 > tmpfile; mv tmpfile $2
        logger "INFO  | extra chars were removed with status : $?"
    else
        logger "INFO  | encryption decryption not required"
        return 0
    fi
    return $status
}

#Function to remove ExtraChars
function removeExtraChar {
    for chars in $EXTRA_CHARS_TO_REMOVE;do sed -i "s/$chars//g" $1 ;done
}

#Function to compress and decompress the incoming File
function comprsDecmprs {
    status=0
    if [ $COMPRS_DECMPRS == "C" ]
    then
        gzip $1
        status=$?
    elif [ $COMPRS_DECMPRS == "D" ]
    then
        gunzip $1
        status=$?
    else
        logger "INFO  | compresion / decompression not required"
        return 0
    fi
    return $status
}

#Function to push the EOD data to Destination-Server
function push {
    for file in $SOURCE_PATH/$FNAME;
    do
    if [[ "$file" != *"$SOURCE_PATH"* ]]; then
    file=$SOURCE_PATH/$file
    fi
        # 1. check for eot file
        eotFile=${file%%.*}.eot 

        # Checking for the Presence of EOT flag 
        if [ "$CHECK_FOR_EOT" == "Y" ];
        then
            # Check if the eot is not present
            if [ ! -f "$eotFile" ];
            then
                logger "ERROR | No eot file found for Transfer for $file. "
                continue;
            fi
        
            #1.b check for the actual file (not the eot file). if the file is older than 1 minute then pick up the file for processing
            if [ ! $(find $file -mmin +1) ]
            then
                logger "ERROR | No eot file found for Transfer for $file. And the actual file is quite fresh, it is possibly still being written to. Will continue to the next file"
                continue;
            fi 
        fi

        #2. encrypt
        encDec "$file"
        #3. check if encryption has failed, then loop over to the next file else proceed with sftps
        if [ $? -ne 0 ];
        then
            logger "ERROR | encryption failed for $file. Moving to the next file"
            continue;
        fi
        
        #4. evaluate the filename to be transfered
        fileToTransfer=$file
        if [ $ENC_DEC == "ENC" ]
        then
            fileToTransfer=$file.pgp
        fi

        #5. sftp
#         sftp -o "IdentityFile=$KEY_FILE" $DESTINATION_USER@$DESTINATION_SERVER<<EOF
#         put $fileToTransfer $DESTINATION_PATH
#         quit
# EOF

#         6. check if sftp was successful, if yes then send eot file else  
#         if [ $? -eq 0 ];
#         then
#             logger "INFO  | SFTP for $file successful. Status : $?"
#             sftp -o "IdentityFile=$KEY_FILE" $DESTINATION_USER@$DESTINATION_SERVER <<EOF &>/dev/null
#             put $eotFile $DESTINATION_PATH
#             quit
# EOF 
#         else
#             logger "ERROR | SFTP for $file failed. Status : $?"
#         fi
        
        #5. sftp
        sftp $DESTINATION_USER@$DESTINATION_SERVER<<EOF
        put $fileToTransfer $DESTINATION_PATH
        quit
EOF
        
        #6. check if sftp was successful, if yes then send eot file else
        if [ $? -eq 0 ];
        then
            logger "INFO | SFTP for $file successful. Status : $?"
            sftp $DESTINATION_USER@$DESTINATION_SERVER<<EOF &>/dev/null
            put $eotFile $DESTINATION_PATH
            quit
EOF
        else
            logger "ERROR | SFTP for $file failed. Status : $?"
        fi

        #9. move the original file to processed dir
        mv ${file%%.*}.* $PROCESSED_DIR
    done
}

# Function to Pull files from Incoming folder and mv to DataSource Loc.
function pull {
    echo "pull called"
    for file in $SOURCE_PATH/$FNAME;
    do
        if [[ "$file" != *"$SOURCE_PATH"* ]]; then
            file=$SOURCE_PATH/$file
        fi
        # 1.a check for eot file
        eotFile=${file%%.*}.eot 
	
	chmod 775 $file $eotFile

        # Checking for the Presence of EOT flag 
        if [ "$CHECK_FOR_EOT" == "Y" ];
        then
            # Check if the eot is not present
            if [ ! -f "$eotFile" ];
            then
                logger "ERROR | No eot file found for Transfer for $file. "
                continue;
            fi
        fi

        #1.b check for the actual file (not the eot file). if the file is older than 1 minute then pick up the file for processing
        if [ ! $(find $file -mmin +1) ]
        then
            logger "ERROR | The actual file is quite fresh, it is possibly still being written to. Will continue to the next file"
            continue;
        fi 
                

        #2. decrypt
        encDec "$file" "${file%.*}"
        #3. check if decryption has failed, then loop over to the next file else proceed with sftps
        if [ $? -ne 0 ];
        then
            logger "ERROR | Decryption failed for $file. Moving to the next file"
            continue;
        fi
        
        #4 Removes File Header based on the REMOVE_FIRST_LINE flag.
        if [ $REMOVE_FIRST_LINE == "Y" ];
        then
            sed -i '1d' ${file%.pgp}
        fi

        #5.Compress / Decompress the file based on the flag
        comprsDecmprs "$file"
        # check if Compress / Decompress has failed, then loop over to the next file else proceed with sftps
        if [ $? -ne 0 ];
        then
            logger "ERROR | Decompress failed for $file. Moving to the next file"
            continue;
        fi

        #6. Check to remove extra chars from the incoming files
        if [ -z $CHARS_TO_REMOVE ];
        then
            logger "INFO | No extra chars to be removed from $file. "
        else
            removeExtraChar "$file"
            logger "INFO  | Extra chars removed from $file"
        fi

	## removing non-Ascii characters from the incoming files
	iconv -c -f utf-8 -t ascii  $file > temp; mv temp $file

        #7. Split
	base_name=$( basename $(echo $file | awk -F'.' '{print $1}'))_
        split -d -a 2 -l $SPLIT_COUNT $(echo $file | awk -F'.' '{print $1}').${OUTPUT_EXTENSION} $DESTINATION_PATH/$base_name
        if [ $? -ne 0 ];
        then
            logger "ERROR | split command failed for ${file%.pgp} with status $?. Moving to the next file"
            continue;
        fi
        logger "INFO  | Split command successfully executed"

        #8. For each of the split files mv (rename) the files over to the destination path
        for splitFiles in $(find $DESTINATION_PATH -type f -name "${base_name}*");
        do
            mv $splitFiles ${splitFiles}.${OUTPUT_EXTENSION}
        done
    #9. move the original file to processed dir
    mv ${file%%.*}.* $PROCESSED_DIR
    done
}

#Checking for the Incoming Mode
if [ "$MODE" == "PUSH" ]
then
    logger "INFO  | Starting sftp from hostname to $DESTINATION_SERVER"
    push
elif [ "$MODE" == "PULL" ]
then
    logger "INFO  | Starting to pick DataSource Incoming files"
    pull
else
    logger "ERROR | Invalid mode for the script. Only valid values are PUSH/PULL"
fi
