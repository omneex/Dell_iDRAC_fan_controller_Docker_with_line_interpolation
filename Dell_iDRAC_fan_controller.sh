#!/bin/bash

if [[ $FAN_SPEED == 0x* ]]
then
  DECIMAL_FAN_SPEED=$(printf '%d' $FAN_SPEED)
  HEXADECIMAL_FAN_SPEED=$FAN_SPEED
else
  DECIMAL_FAN_SPEED=$FAN_SPEED
  HEXADECIMAL_FAN_SPEED=$(printf '0x%02x' $FAN_SPEED)
fi

echo "Idrac/IPMI host: $IDRAC_HOST"
if [[ $IDRAC_HOST != "local" ]]
then
  echo "Idrac/IPMI username: $IDRAC_USERNAME"
  echo "Idrac/IPMI password: $IDRAC_PASSWORD"
fi
echo "Fan speed objective: $DECIMAL_FAN_SPEED%"
echo "CPU temperature treshold: $CPU_TEMPERATURE_TRESHOLD°C"
echo "Check interval: ${CHECK_INTERVAL}s"

readonly DELL_FRESH_AIR_COMPLIANCE=45

while true; do
  if [[ $IDRAC_HOST == "local" ]]
  then
    LOGIN_STRING='open'
  else
    LOGIN_STRING="lanplus -H $IDRAC_HOST -U $IDRAC_USERNAME -P $IDRAC_PASSWORD"
  fi

  DATA=$(ipmitool -I $LOGIN_STRING sdr type temperature | grep degrees)
  INLET_TEMPERATURE=$(echo "$DATA" | grep Inlet | grep -Po '\d{2}' | tail -1)
  EXHAUST_TEMPERATURE=$(echo "$DATA" | grep Exhaust | grep -Po '\d{2}' | tail -1)
  CPU_DATA=$(echo "$DATA" | grep "3\." | grep -Po '\d{2}')
  CPU1_TEMPERATURE=$(echo $CPU_DATA | awk '{print $1;}')
  CPU2_TEMPERATURE=$(echo $CPU_DATA | awk '{print $2;}')

  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m' # No Color

  echo "------------------------------------"
  echo "Current"
  echo "- inlet temperature is $INLET_TEMPERATURE°C"
  echo "- CPU 1 temperature is $CPU1_TEMPERATURE°C"
  echo "- CPU 2 temperature is $CPU2_TEMPERATURE°C"
  echo "- Exhaust temperature is $EXHAUST_TEMPERATURE°C"

  CPU1_OVERHEAT () { [ $CPU1_TEMPERATURE -gt $CPU_TEMPERATURE_TRESHOLD ]; }
  CPU2_OVERHEAT () { [ $CPU2_TEMPERATURE -gt $CPU_TEMPERATURE_TRESHOLD ]; }

  if CPU1_OVERHEAT
  then
    if CPU2_OVERHEAT
    then
      printf "CPU 1 and CPU 2 temperatures are ${RED}too high${NC}. Activating default dynamic fan control."
    else
      printf "CPU 1 temperature is ${RED}too high${NC}. Activating default dynamic fan control."
    fi
    ipmitool -I $LOGIN_STRING raw 0x30 0x30 0x01 0x01
  elif CPU2_OVERHEAT
  then
    printf "CPU 2 temperature is ${RED}too high${NC}. Activating default dynamic fan control."
    ipmitool -I $LOGIN_STRING raw 0x30 0x30 0x01 0x01
  else
    printf "CPUs temperatures are ${GREEN}OK${NC}. Using manual fan control with ${DECIMAL_FAN_SPEED}%% fan speed."
    ipmitool -I $LOGIN_STRING raw 0x30 0x30 0x01 0x00
    ipmitool -I $LOGIN_STRING raw 0x30 0x30 0x02 0xff $HEXADECIMAL_FAN_SPEED
  fi
  sleep $CHECK_INTERVAL
done