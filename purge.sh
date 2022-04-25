#!/bin/bash

#
# This script is to purge the s3 of older versions
#

# minimum version to keep
# MIN_VERSION=1.0.2

# stable | test
# RELEASE_TYPE=stable

# bucket name
# S3_BUCKET=homebridge-repo

# region
# S3_REGION=us-west-2

# from https://stackoverflow.com/a/4025065
vercomp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

# loop over the objects in the bucket and find packages to remove
for i in $(aws s3api list-objects --region $S3_REGION --bucket "$S3_BUCKET" --prefix pool/$RELEASE_TYPE/h/ho/ | jq ".Contents[] | .Key"); do
  version=${i#*_}
  version=${version%_*}
  vercomp $MIN_VERSION $version
  result=$?
  if [ $result -eq 1 ]; then
    key=$(echo "$i" | tr -d '"')
    echo "Removing ($version) from s3 at $key"
    aws s3api delete-object --region $S3_REGION --bucket "$S3_BUCKET" --key="$key"  --output=json
    echo $?
  fi
done
