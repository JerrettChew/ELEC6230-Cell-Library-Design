cell="fulladder"
file="sp_out.txt"
key1="tdrr"
keys=("tdrr" "tdfr" "\$DATA1" ".TITLE")
inSignal=()
inCap=()

#cut -d " " << $file

# extract input capacitance from file $1 (a .mt0 file)
# concatenate average of all measurements to file $2
extract_input_capacitance () {
  local infile=$1
  local outfile=$2
  
  # variables to store data read from input file
  local valueFlag=0
  local inSignal=()
  local inCap=()

  while IFS=" " read  -a k; do
    # get measured values (lines after tdfr and tdrr)
    #[[ ${k[*]} =~ ${keys[0]} ]] && echo "flag1"
    #[[ ${k[*]} =~ ${keys[1]} ]] && echo "flag2"
    [[ ${k[*]} =~ "tdavgc" ]] && valueFlag=1 && continue
  
    # get sim parameters
    if [[ "SIMPARAM:" == ${k[0]} ]]; then
      #echo "${k[1]} > ${k[2]}"
      inSignal=(${inSignal[*]} ${k[1]})
    fi
  
    if [[ $valueFlag == 1 ]]; then
      echo ${k[*]}
      if [[ ${k[2]} != "failed" && ${k[3]} != "failed" ]]; then
        inCap=(${inCap[*]} ${k[1]})
      else
        inCap=(${inCap[*]} "failed")
      fi
      valueFlag=0
    fi
  done <"$file"

  echo "In signal: ${inSignal[*]}"
  echo "Input Capacitance: ${inCap[*]}"

  # Lists and variables to average all measurements
  local currentIn=${inSignal[0]}
  local currentCap=${inCap[0]}
  local n=0
  local capTotal=0
  
  for ((i=0; i<${#inCap[@]}; i++)); do
    if [[ $currentIn != ${inSignal[$i]} ]]
    then
      # convert to femtofarads unit and take average
      temp=$(echo "${capTotal}/${n}*10^15" | bc -l)
      # shorten the output to 2 decimal precision
      temp=$(echo "scale=2; $temp * 100 / 100" | bc)
    
      echo $currentIn, input capacitance: $temp
      currentIn=${inSignal[$i]}
      currentCap=${inCap[$i]}
      n=0
      capTotal=0
    fi
  
    if [[ ${inCap[$i]} != "failed" ]]; then
      n=$((n + 1))
      # convert riseValue[i] from scientific notation to a decimal number
      temp=$(echo "${inCap[$i]}" | sed -r 's/[e]+/*10^/g' | bc -l)
      # add temp to total
      capTotal=$(echo "${temp}+${capTotal}" | bc -l)
      echo $temp
      echo $capTotal
      echo $n
    fi
  done

  # convert to femtofarads unit and take average
  # shorten the output to 2 decimal precision
  temp=$(echo "${capTotal}/${n}*10^15" | bc -l)
  temp=$(echo "scale=2; $temp * 100 / 100" | bc)
    
  echo $currentIn, input capacitance: $temp
}

extract_input_capacitance $file
