#!/system/bin/sh

# Base stuff we need
POGOPKG=com.nianticlabs.pokemongo
CONFIGFILE='/data/local/tmp/emagic.config'
logfile=/data/local/tmp/emagic.log
setprop net.dns1 1.1.1.1 && setprop net.dns2 8.8.8.8

# Check if $CONFIGFILE exists and has data.
get_config() {
	if [[ -s $CONFIGFILE ]]; then
		log "$CONFIGFILE exists and has data. Data will be pulled."
		source $CONFIGFILE
		export timezone discord_webhook
	else
		log "Failed to pull the config file. Make sure $CONFIGFILE exists and has the correct data."
	fi
}

runningMitm() {
	busybox ps aux | grep -E -C0 "pokemod|gocheats|sy1vi3|ares" |
		grep -C0 -v grep |
		awk -F ' ' '
            /com.pokemod/ { print $NF } 
            /com.sy1vi3/ { print $NF } 
            /com.nianticlabs.pokemongo.ares/ { print $NF } 
            /com.gocheats.launcher/ { print $NF }
        ' |
		grep -E -C0 "gocheats|pokemod|sy1vi3|ares" |
		sed -e 's/^[0-9]*://' -e 's@:.*@@g' |
		sort | uniq
}

installedMitm() {
	if [ "$(pm list packages com.pokemod.aegis.beta)" = "package:com.pokemod.aegis.beta" ]; then
		log "Found Aegis developer version!"
		MITMPKG=com.pokemod.aegis.beta
	elif [ "$(pm list packages com.pokemod.aegis)" = "package:com.pokemod.aegis" ]; then
		log "Found Aegis production version!"
		MITMPKG=com.pokemod.aegis
	elif [ "$(pm list packages com.nianticlabs.pokemongo.ares)" = "package:com.nianticlabs.pokemongo.ares" ]; then
		log "Found Cosmog (Ares pkg name version)!"
		MITMPKG=com.nianticlabs.pokemongo.ares
	elif [ "$(pm list packages com.gocheats.launcher)" = "package:com.gocheats.launcher" ]; then
		log "Found GC!"
		MITMPKG=com.gocheats.launcher
	else
		log "No MITM installed. Abort!"
		exit 1
	fi
}

# Keeping this for the webhook mainly
getDeviceName() {
	if [[ $MITMPKG == com.pokemod.atlas* ]] && [ -f /data/local/tmp/atlas_config.json ]; then
		mitmDeviceName=$(jq -r '.deviceName' /data/local/tmp/atlas_config.json)
	elif [[ $MITMPKG == com.pokemod.aegis* ]] && [ -f /data/local/tmp/aegis_config.json ]; then
		mitmDeviceName=$(jq -r '.deviceName' /data/local/tmp/aegis_config.json)
	elif { [[ "$MITMPKG" == "com.sy1vi3.cosmog" || "$MITMPKG" == "com.nianticlabs.pokemongo.ares" ]] && [ -f /data/local/tmp/cosmog.json ]; }; then
		mitmDeviceName=$(jq -r '.device_id' /data/local/tmp/cosmog.json)
	elif [[ $MITMPKG == com.gocheats.launcher ]] && [ -f /data/local/tmp/config.json ]; then
		mitmDeviceName=$(jq -r '.device_name' /data/local/tmp/config.json)
	else
		log "Couldn't find the config file"
	fi
}

# Send a webhook to discord if it's configured
webhook() {
	# Check if discord_webhook variable is set
	if [[ -z "$discord_webhook" ]]; then
		log "discord_webhook variable is not set. Cannot send webhook."
		return
	fi

	# Check internet connectivity by pinging 8.8.8.8 and 1.1.1.1
	if ! ping -c 1 -W 1 8.8.8.8 >/dev/null && ! ping -c 1 -W 1 1.1.1.1 >/dev/null; then
		log "No internet connectivity. Skipping webhook."
		return
	fi

	local message="$1"
	local local_ip="$(ip route get 1.1.1.1 | awk '{print $7}')"
	local wan_ip="$(curl -s -k https://ipinfo.io/ip)"
	local mac_address="$(ip link show eth0 | awk '/ether/ {print $2}')"
	local mac_address_nodots="$(ip link show eth0 | awk '/ether/ {print $2}' | tr -d ':')"
	local timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
	local mitm_version="NOT INSTALLED"
	local pogo_version="$(dumpsys package com.nianticlabs.pokemongo | grep versionName | cut -d "=" -f 2)"
	local agent=""
	local playStoreVersion=""
	local temperature="$(cat /sys/class/thermal/thermal_zone0/temp | awk '{print substr($0, 1, length($0)-3)}')"
	playStoreVersion=$(dumpsys package com.android.vending | grep versionName | head -n 1 | cut -d "=" -f 2)
	android_version=$(getprop ro.build.version.release)

	getDeviceName

	# Get mitm version
	mitm_version="$(dumpsys package "$MITMPKG" | awk -F "=" '/versionName/ {print $2}')"

	# Get pogo version
	pogo_version="$(dumpsys package com.nianticlabs.pokemongo | awk -F "=" '/versionName/ {print $2}')"

	# Create a temporary directory to store the files
	local temp_dir="/data/local/tmp/webhook_${timestamp}"
	mkdir "$temp_dir"

	# Retrieve the logcat logs
	logcat -v colors -d >"$temp_dir/logcat_${MITMPKG}_${timestamp}_${mac_address_nodots}_selfSentLog.log"

	# Create the payload JSON
	payload_json=$(jq -n \
		--arg username "$mitmDeviceName" \
		--arg content "$message" \
		--arg deviceName "$mitmDeviceName" \
		--arg localIp "$local_ip" \
		--arg wanIp "$wan_ip" \
		--arg mac "$mac_address" \
		--arg temp "$temperature" \
		--arg mitm "$MITMPKG" \
		--arg mitmVersion "$mitm_version" \
		--arg pogoVersion "$pogo_version" \
		--arg playStoreVersion "$playStoreVersion" \
		--arg androidVersion "$android_version" \
		'{
                    username: $username,
                    content: $content,
                    embeds: [
                      {
                        title: $deviceName,
                        fields: [
                          {name: "Local IP", value: $localIp, inline: true},
                          {name: "WAN IP", value: $wanIp, inline: true},
                          {name: "MAC", value: $mac, inline: true},
                          {name: "Temperature", value: $temp, inline: true},
                          {name: "MITM Package", value: $mitm, inline: true},
                          {name: "MITM Version", value: $mitmVersion, inline: true},
                          {name: "PoGo Version", value: $pogoVersion, inline: true},
                          {name: "Play Store Version", value: $playStoreVersion, inline: true},
                          {name: "Android Version", value: $androidVersion, inline: true}
                        ]
                      }
                    ]
                  }')

	log "Sending discord webhook"
	# Upload the payload JSON and logcat logs to Discord
	if [[ $MITMPKG == com.pokemod.atlas* ]]; then
		curl -X POST -k -H "Content-Type: multipart/form-data" \
			-F "payload_json=$payload_json" \
			-F "logcat=@$temp_dir/logcat_${MITMPKG}_${timestamp}_${mac_address_nodots}_selfSentLog.log" \
			-F "atlaslog=@/data/local/tmp/atlas.log" \
			"$discord_webhook"
	# Check for com.pokemod.aegis* package and send webhook with aegis.log (or specific log for aegis)
	elif [[ $MITMPKG == com.pokemod.aegis* ]]; then
		curl -X POST -k -H "Content-Type: multipart/form-data" \
			-F "payload_json=$payload_json" \
			-F "logcat=@$temp_dir/logcat_${MITMPKG}_${timestamp}_${mac_address_nodots}_selfSentLog.log" \
			-F "aegislog=@/data/local/tmp/aegis.log" \
			"$discord_webhook"
	else
		# curl -X POST -k -H "Content-Type: multipart/form-data" -F "payload_json=$payload_json" "$discord_webhook" -F "logcat=@$temp_dir/logcat_${MITMPKG}_${timestamp}_${mac_address_nodots}_selfSentLog.log"
		curl -X POST -k -H "Content-Type: multipart/form-data" \
			-F "payload_json=$payload_json" \
			-F "logcat=@$temp_dir/logcat_${MITMPKG}_${timestamp}_${mac_address_nodots}_selfSentLog.log" \
			"$discord_webhook"
	fi
	# Clean up temporary files
	rm -rf "$temp_dir"
}

get_config
MITMPKG=""
installedMitm

# Disable playstore alltogether (no auto updates)
# if [ "$(pm list packages -e com.android.vending)" = "package:com.android.vending" ]; then
# 	log "Disabling Play Store"
# 	pm disable-user com.android.vending
# fi

# Set mitm mock location permission as ignore
if ! appops get $MITMPKG android:mock_location | grep -qm1 'No operations'; then
	log "Removing mock location permissions from $MITMPKG"
	appops set $MITMPKG android:mock_location 2
fi

# Disable all location providers
if ! settings get 2>/dev/null; then
	log "Checking allowed location providers as 'shell' user"
	allowedProviders=".$(su shell -c settings get secure location_providers_allowed)"
else
	log "Checking allowed location providers"
	allowedProviders=".$(settings get secure location_providers_allowed)"
fi

if [ "$allowedProviders" != "." ]; then
	log "Disabling location providers..."
	if ! settings put secure location_providers_allowed -gps,-wifi,-bluetooth,-network >/dev/null; then
		log "Running as 'shell' user"
		su shell -c 'settings put secure location_providers_allowed -gps,-wifi,-bluetooth,-network'
	fi
fi

# Make sure the device doesn't randomly turn off
if [ "$(settings get global stay_on_while_plugged_in)" != 3 ]; then
	log "Setting Stay On While Plugged In"
	settings put global stay_on_while_plugged_in 3
fi

# Disable package verifier
if [ "$(settings get global package_verifier_enable)" != 0 ]; then
	log "Disable package verifier"
	settings put global package_verifier_enable 0
fi
if [ "$(settings get global verifier_verify_adb_installs)" != 0 ]; then
	log "Disable package verifier over adb"
	settings put global verifier_verify_adb_installs 0
fi

# Disable play protect
if [ "$(settings get global package_verifier_user_consent)" != -1 ]; then
	log "Disable play protect"
	settings put global package_verifier_user_consent -1
fi

# Check if the timezone variable is set
if [ -n "$timezone" ]; then
	# Set the timezone using the variable
	setprop persist.sys.timezone "$timezone"
	log "Timezone set to $timezone"
else
	log "Timezone variable not set. Skipping timezone change."
fi

# Check if ADB is disabled (adb_enabled is set to 0)
adb_status=$(settings get global adb_enabled)
if [ "$adb_status" -eq 0 ]; then
	log "ADB is currently disabled. Enabling it..."
	settings put global adb_enabled 1
fi

# Check if ADB over Wi-Fi is disabled (adb_wifi_enabled is set to 0)
adb_wifi_status=$(settings get global adb_wifi_enabled)
if [ "$adb_wifi_status" -eq 0 ]; then
	log "ADB over Wi-Fi is currently disabled. Enabling it..."
	settings put global adb_wifi_enabled 1
fi

# Check and set permissions for adb_keys
adb_keys_file="/data/misc/adb/adb_keys"
if [ -e "$adb_keys_file" ]; then
	current_permissions=$(stat -c %a "$adb_keys_file")
	if [ "$current_permissions" -ne 640 ]; then
		log "Changing permissions for $adb_keys_file to 640..."
		chmod 640 "$adb_keys_file"
	fi
fi

# Download cacert to use certs instead of curl -k
cacert_path="/data/local/tmp/cacert.pem"
if [ ! -f "$cacert_path" ]; then
	log "Downloading cacert.pem..."
	curl -k -o "$cacert_path" https://curl.se/ca/cacert.pem
fi

if ! [ -z "$MITMPKG" ]; then
	(
		log "Starting in 2 minutes, installed MITM: $MITMPKG"
		counter=0
		log "Count at $counter"
		webhook "Device boot!"

		# this again... but simple(I think)
		while :; do
			sleep_duration=120
			sleep $((sleep_duration + $RANDOM % 10))
			if [[ $counter -gt 3 ]]; then
				log "Count threshold of $counter reached. Rebooting device..."
				webhook "Restart threshold of $counter reached. Rebooting device..."
				reboot
				sleep 60 # In case reboot takes too long for some reason
			fi

			log "Health check started!"
			if [[ "$MITMPKG" == "com.nianticlabs.pokemongo.ares" ]]; then
				if busybox ps -a | grep -v grep | grep "com.nianticlabs.pokemongo.ares"; then
					log "$MITMPKG is running. Nothing to do here."
					counter=0
				else
					log "$MITMPKG is not running, let's start it up!"
					am start -n "$MITMPKG"/.MainActivity
					# monkey -p "$MITMPKG" 1
					counter=$((counter + 1))
				fi
			fi
			continue
		done
	) &
else
	log "No known MITM was found installed on the device. Cya."
fi

#ENDOFFILE
