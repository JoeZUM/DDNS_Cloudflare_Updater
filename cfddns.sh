#!/bin/bash

#the aim of this script is to periodicall update the external IP address by calling the cloudflare api

ZONE_ID=
DNS_NAME=
X_Auth_Email=
X_Auth_Key=
API_TOKEN= 
PRINT_LOGFILE=false #for debugging purposes: set to true to print the log file to console after script exits

############################
#####     Logging      #####
############################

# Logging (#chose between DEBUG, INFO or OFF)
LOG_LEVEL="INFO"
LOG_FILE="cfddns.log"


#create logfile in case it does not yet exist
        if ! [ -f "cfddns.log" ]; then

        touch cfddns.log

                if [ $LOG_LEVEL == "DEBUG" ]; then
                        LOG_MESSAGE="New logfile created."
                        echo "$(date +"%Y-%m-%d %H:%M:%S") - $LOG_MESSAGE" >> "$LOG_FILE"
                fi
        fi


# Function to write to the log file
write_log() {
        local MESSAGE_LEVEL=$1
        local LOG_MESSAGE=$2

        case $LOG_LEVEL in
                "OFF")
                                #do nothing
                        ;;
                "INFO")
                        if [[ $MESSAGE_LEVEL = "INFO" ]]; then
                                echo "$(date +"%Y-%m-%d %H:%M:%S") - $LOG_MESSAGE" >> "$LOG_FILE"
                        fi
                        ;;
                "DEBUG")
                                echo "$(date +"%Y-%m-%d %H:%M:%S") - $LOG_MESSAGE" >> "$LOG_FILE"
                        ;;
        esac
}


# function to print logile to the console
print_log() {
        if [ $PRINT_LOGFILE == true ]; then
                local logfile="./cfddns.log"
                cat "$logfile"
        fi
}

############################
#####    Functions     #####
############################

# Function to validate IPv4 address using regex
validate_ipv4() {
    local ipv4_pattern="^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
    if [[ $1 =~ $ipv4_pattern ]]; then
        echo "$1 is a valid IPv4 address"
    else
        echo "$1 is NOT a valid IPv4 address"
    fi
}


# Function to test API token
validate_api_token() {
    local api_token=$1

    # Make the curl request and store the response in a variable
    local response=$(curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $api_token")

    # Check if the response contains any errors
    local errors_empty=$(echo "$json" | jq '.errors | length == 0')
    if [ "$errors_empty" = false ]; then
        echo "Error occurred while validating API token: $response"
        exit 1  # Exit with a non-zero status to indicate an error
    fi

    # Echo the response
    local message=$(echo "$response" | jq -r '.messages[0].message')
    echo "$message"
}


# Function to update DNS records using the Cloudflare API
update_ip_address(){

   local DNS_RECORD_ID=$1
   local external_ip=$2
   local UPDATE_URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_RECORD_ID"

        # Make the API call
        update_response=$(curl -s -X PUT \
                -H "Content-Type: application/json" \
                -H "X-Auth-Email: $X_Auth_Email" \
                -H "X-Auth-Key: $X_Auth_Key" \
                -d '{"content": "'"$external_ip"'",
                     "name": "'"$DNS_NAME"'",
                     "proxied": false,
                     "type": "A",
                     "ttl": 3600
                    }' \
                $UPDATE_URL)

        write_log "DEBUG" " $update_response"

        # Check if the API call was successful (HTTP status code 200)
        if [ $? -eq 0 ]; then
                write_log "INFO" "The IP address was successfully updated!"
                print_log
                exit 0
        else
                write_log "DEBUG" "ERROR calling the API!"
                write_log "DEBUG" "$update_response"
                print_log
                exit 1
        fi
}

############################
#### Gather Information ####
############################

# Validate API token
if [ -z "$API_TOKEN" ]; then
        validation_result=$(validate_api_token "$API_TOKEN")
        write_log "DEBUG" "$validation_result"
fi

# Get current external IP
external_ip=$(curl -s https://ifconfig.co/ip)
write_log "DEBUG" "Retrieved current external IP address: $external_ip"


#validate IP format
ip_validation=$(validate_ipv4 "$external_ip")
write_log "DEBUG" "$ip_validation"


# Get dns_record and parse record id and ip address
RECORDS_URL="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records"

RECORDS=$(curl -s -X GET \
        -H "Content-Type: application/json" \
        -H "X-Auth-Email: $X_Auth_Email" \
        -H "X-Auth-Key: $X_Auth_Key" \
        "$RECORDS_URL")


#extract the record id from the api response
record_id=$(echo "$RECORDS" | jq -r --arg DNS_NAME "$DNS_NAME" '.result[] | select(.name == $DNS_NAME) | .id')


#extract the ip address from the api response
record_ip=$(echo "$RECORDS" | jq -r --arg DNS_NAME "$DNS_NAME" '.result[] | select(.name == $DNS_NAME) | .content')

write_log "DEBUG" "Successfully retrieved record ID for $DNS_NAME: $record_id"
write_log "DEBUG" "Successfully retrieved record IP address  for $DNS_NAME: $record_ip"


#compare record ip (from Cloudflare) with current external ip (from https://ifconfig.co/ip)
if [ "$external_ip" = "$record_ip" ]; then
   write_log "INFO" "The IP address retrieved from Cloudflare is still up to date: No records were updated!"
   print_log
   exit 0
else
   write_log "DEBUG" "The IP address retrieved from Cloudflare is different from the current external IP address"
   update_ip_address $record_id $external_ip
fi
